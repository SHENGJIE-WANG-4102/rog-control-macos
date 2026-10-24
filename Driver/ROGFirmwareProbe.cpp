// G815LW on-demand factory-profile bridge. No ACPI calls at start/stop/free.
// Only administrator requests reach fixed ASUS endpoints; no raw EC/MSR API.
// Curves and PL1/PL2 are explicit transactions, never startup/timer callbacks.
#include <IOKit/IOService.h>
#include <IOKit/IOUserClient.h>
#include <IOKit/IOLocks.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include <libkern/c++/OSContainers.h>
#include <mach/task.h>
#include <mach/kmod.h>
#include "Profiles.hpp"
#include "TuningPolicy.hpp"

class ROGFirmwareProbe : public IOService {
    OSDeclareDefaultStructors(ROGFirmwareProbe)
    IOACPIPlatformDevice *device {nullptr};
    const ROGModelProfile *profile {nullptr};
    IOLock *lock {nullptr};
    bool stopped {true};
    uint64_t serial {0};
    ROGTuningState tuning {};
    struct TuningIO;
    bool verifyFirmware();
    IOReturn readByte(IOACPIPlatformDevice *ec,const char *field,uint32_t &value);
    IOReturn readFan(IOACPIPlatformDevice *ec,unsigned index,uint32_t &rpm);
    IOReturn snapshot();
    IOReturn factoryMode(uint32_t);
    IOReturn modeWmi(uint32_t,uint32_t,uint32_t &);
    IOReturn tuningWmi(uint32_t,uint32_t,const uint8_t *,unsigned,OSObject **);
    bool tuneCurve(unsigned,uint32_t,ROGFanCurve &,bool);
    bool tunePower(unsigned,uint32_t,bool);
    bool tuneContext(uint32_t &,uint32_t &);
    bool tuneReadPower(uint32_t &,uint32_t &);
    void publishTuning();
    IOReturn tuningCommand(unsigned,const ROGTuningRequest *);
public:
    bool init(OSDictionary *) override;
    bool start(IOService *) override;
    void stop(IOService *) override;
    void free() override;
    IOReturn setProperties(OSObject *) override;
};
OSDefineMetaClassAndStructors(ROGFirmwareProbe,IOService)

bool ROGFirmwareProbe::init(OSDictionary *dict) {
    if (!IOService::init(dict)) return false;
    lock=IOLockAlloc();return lock!=nullptr;
}
bool ROGFirmwareProbe::start(IOService *provider) {
    auto candidate=OSDynamicCast(IOACPIPlatformDevice,provider);
    if (!candidate||strcmp(provider->getName(),"ATKD")) return false;
    // _UID is an existing registry property, not an ACPI evaluation.
    auto uid=OSDynamicCast(OSString,provider->getProperty("_UID"));
    if (!uid||!uid->isEqualTo("ATK")||!IOService::start(provider)) return false;
    device=candidate;device->retain();stopped=false;
    setProperty("BridgeVersion","1.5.0");
    setProperty("ReadOnly",false);
    setProperty("FactoryModesOnly",false);setProperty("OnDemandOnly",true);
    setProperty("TuningImplemented",true);setProperty("MaximumPowerWatts",ROGPowerMaxW,32);
    setProperty("FirmwareQueriesAtStart",static_cast<uint64_t>(0),32);
    setProperty("QueryState","awaiting-explicit-refresh");
    registerService();return true;
}
void ROGFirmwareProbe::stop(IOService *provider) {
    IOLockLock(lock);stopped=true;
    OSSafeReleaseNULL(device);
    IOLockUnlock(lock);
    IOService::stop(provider);
}
void ROGFirmwareProbe::free() {
    OSSafeReleaseNULL(device);
    if (lock) IOLockFree(lock);
    IOService::free();
}
bool ROGFirmwareProbe::verifyFirmware() {
    profile=nullptr;
    const OSData *data=device->getACPITableData("DSDT",0);
    if (!data||data->getLength()>1024*1024) return false;
    auto bytes=static_cast<const uint8_t *>(data->getBytesNoCopy());
    uint64_t hash=0xcbf29ce484222325ULL;
    for (unsigned i=0;i<data->getLength();i++) hash=(hash^bytes[i])*0x100000001b3ULL;
    setProperty("DSDTFingerprint",hash,64);
    for (const auto &candidate:ROGProfiles) {
        if (candidate.dsdtLength==data->getLength()&&candidate.dsdtFNV1a==hash) {
            profile=&candidate;setProperty("MatchedModel",candidate.model);return true;
        }
    }
    removeProperty("MatchedModel");return false;
}
IOReturn ROGFirmwareProbe::readByte(IOACPIPlatformDevice *ec,const char *field,uint32_t &value) {
    // Only literal FieldUnit names from the audited DSDT are allowed.
    const char *allowed[]={"FANM","ACIN","FA1L","FA1H","FA2L","FA2H","FA3L","FA3H","M6F0","M6F1"};
    bool permitted=false;
    for (auto name:allowed) if (!strcmp(name,field)) { permitted=true;break; }
    if (!permitted) return kIOReturnUnsupported;
    if (!ec||strlen(field)!=4) return kIOReturnBadArgument;
    uint32_t raw=0;
    // AppleACPIPlatformExpert rejects object names longer than four characters.
    // Resolve the registry device separately and evaluate a leaf relative to EC0.
    IOReturn status=ec->evaluateInteger(field,&raw);
    if (status!=kIOReturnSuccess) return status;
    if (raw>255) return kIOReturnBadArgument;
    value=raw;return kIOReturnSuccess;
}
IOReturn ROGFirmwareProbe::readFan(IOACPIPlatformDevice *ec,unsigned index,uint32_t &rpm) {
    if (index<1||index>3) return kIOReturnBadArgument;
    char high[5],low[5];snprintf(high,sizeof(high),"FA%uH",index);snprintf(low,sizeof(low),"FA%uL",index);
    for (unsigned attempt=0;attempt<2;attempt++) {
        uint32_t h1=0,l=0,h2=0;
        IOReturn status=readByte(ec,high,h1);if (status) return status;
        status=readByte(ec,low,l);if (status) return status;
        status=readByte(ec,high,h2);if (status) return status;
        if (h1==h2) { rpm=(h1<<8)|l;return kIOReturnSuccess; }
    }
    return kIOReturnNotReady;
}
IOReturn ROGFirmwareProbe::snapshot() {
    auto result=OSDictionary::withCapacity(5);
    if (!result) return kIOReturnNoMemory;
    bool verified=verifyFirmware();
    result->setObject("ModelVerified",verified?kOSBooleanTrue:kOSBooleanFalse);
    IOReturn overall=kIOReturnUnsupported;
    if (verified) {
        auto entry=IORegistryEntry::fromPath(profile->ecRegistryPath);
        auto ec=OSDynamicCast(IOACPIPlatformDevice,entry);
        bool ecReady=ec&&!strcmp(ec->getName(),"EC0");
        result->setObject("EC0Found",ecReady?kOSBooleanTrue:kOSBooleanFalse);
        auto fields=OSDictionary::withCapacity(2);
        auto fans=OSDictionary::withCapacity(3);
        overall=kIOReturnSuccess;
        if (!ecReady) overall=kIOReturnNotFound;
        if (!fields||!fans) overall=kIOReturnNoMemory;
        if (fields&&fans&&ecReady) {
            const char *names[]={"FANM","ACIN"};
            for (auto name:names) {
                uint32_t value=0;IOReturn status=readByte(ec,name,value);
                auto reading=OSDictionary::withCapacity(2);
                auto code=OSNumber::withNumber(static_cast<uint32_t>(status),32);
                if (reading&&code) reading->setObject("IOReturn",code);
                if (code) code->release();
                if (status==kIOReturnSuccess) {
                    auto number=OSNumber::withNumber(value,32);
                    if (reading&&number) reading->setObject("Value",number);
                    if (number) number->release();
                } else overall=kIOReturnError;
                if (reading) { fields->setObject(name,reading);reading->release(); }
                else overall=kIOReturnNoMemory;
            }
            const char *labels[]={"CPU","GPU","Mid"};
            for (unsigned i=0;i<3;i++) {
                uint32_t rpm=0;IOReturn status=readFan(ec,i+1,rpm);
                auto reading=OSDictionary::withCapacity(3);
                auto code=OSNumber::withNumber(static_cast<uint32_t>(status),32);
                if (reading&&code) reading->setObject("IOReturn",code);
                if (code) code->release();
                bool valid=status==kIOReturnSuccess&&rpm<=12000;
                if (reading) reading->setObject("Valid",valid?kOSBooleanTrue:kOSBooleanFalse);
                if (status==kIOReturnSuccess) {
                    auto number=OSNumber::withNumber(rpm,32);
                    if (reading&&number) reading->setObject("RawRPM",number);
                    if (number) number->release();
                }
                if (!valid) overall=kIOReturnError;
                if (reading) { fans->setObject(labels[i],reading);reading->release(); }
                else overall=kIOReturnNoMemory;
            }
            result->setObject("FirmwareFields",fields);
            result->setObject("Fans",fans);
        }
        if (fields) fields->release();if (fans) fans->release();
        if (entry) entry->release();
    }
    auto sequence=OSNumber::withNumber(++serial,64);
    if (sequence) { result->setObject("Serial",sequence);sequence->release(); }
    auto code=OSNumber::withNumber(static_cast<uint32_t>(overall),32);
    if (code) { result->setObject("IOReturn",code);code->release(); }
    // One immutable dictionary per completed request; readers cannot mix samples.
    setProperty("Snapshot",result);result->release();
    setProperty("QueryState",overall==kIOReturnSuccess?"completed":"failed-or-partial");
    return overall;
}
#include "Tuning.inc"
IOReturn ROGFirmwareProbe::modeWmi(uint32_t operation,uint32_t value,uint32_t &raw) {
    // Neither the device id nor the ACPI method name comes from userspace.
    if (operation!=0x53545344U && operation!=0x53564544U) return kIOReturnUnsupported;
    if (operation==0x53564544U && value>2) return kIOReturnBadArgument;
    if (device->validateObject("WMNB")!=kIOReturnSuccess) return kIOReturnNotFound;
    uint32_t arguments[6]={0x00120075U,value,0,0,0,0};
    OSObject *parameters[3]={OSNumber::withNumber(static_cast<uint64_t>(0),32),
        OSNumber::withNumber(operation,32),OSData::withBytes(arguments,sizeof(arguments))};
    OSObject *result=nullptr;IOReturn status=kIOReturnNoMemory;
    if (parameters[0]&&parameters[1]&&parameters[2])
        status=device->evaluateObject("WMNB",&result,parameters,3);
    if (status==kIOReturnSuccess) {
        auto number=OSDynamicCast(OSNumber,result);
        if (number) raw=number->unsigned32BitValue();
        else status=kIOReturnBadArgument;
    }
    if (result) result->release();
    for (auto parameter:parameters) if (parameter) parameter->release();
    return status;
}
IOReturn ROGFirmwareProbe::factoryMode(uint32_t mode) {
    if (mode>2) return kIOReturnBadArgument;
    if (!verifyFirmware()) return kIOReturnUnsupported;
    auto entry=IORegistryEntry::fromPath(profile->ecRegistryPath);
    auto ec=OSDynamicCast(IOACPIPlatformDevice,entry);
    IOReturn status=kIOReturnNotReady;
    uint32_t power=0,before=0,after=0,support=0,reply=0;
    if (!ec||strcmp(ec->getName(),"EC0")) status=kIOReturnNotFound;
    else if (readByte(ec,"ACIN",power)||power!=1||readByte(ec,"FANM",before)||(before>2&&before!=4))
        status=kIOReturnNotReady;
    else if (before==mode) status=kIOReturnSuccess;
    else {
        status=modeWmi(0x53545344U,0,support);
        if (!status && (support==0xfffffffeU||!(support&0x10000U))) status=kIOReturnUnsupported;
        if (!status) {
            status=modeWmi(0x53564544U,mode,reply);
            if (!status&&reply!=1) status=kIOReturnError;
            if (!status) {
                bool matched=false;
                for (unsigned attempt=0;attempt<10;attempt++) {
                    if (!readByte(ec,"FANM",after)&&after==mode) { matched=true;break; }
                    IOSleep(50);
                }
                if (!matched) status=kIOReturnError;
            }
        }
    }
    // A write failure still gets a readback if the node is valid. Record before
    // and after independently; never label an unconfirmed write successful.
    bool afterValid=ec && !strcmp(ec->getName(),"EC0") && readByte(ec,"FANM",after)==kIOReturnSuccess;
    setProperty("ModeRequested",mode,32);setProperty("ModeBefore",before,32);
    setProperty("ModeWriteIOReturn",static_cast<uint32_t>(status),32);
    setProperty("ModeSupportRaw",support,32);setProperty("ModeReplyRaw",reply,32);
    setProperty("ModeReadbackValid",afterValid);
    if (afterValid) setProperty("ModeAfter",after,32);else removeProperty("ModeAfter");
    setProperty("ModeMatched",status==kIOReturnSuccess&&afterValid&&after==mode);
    if (entry) entry->release();
    snapshot();
    return status;
}
IOReturn ROGFirmwareProbe::setProperties(OSObject *properties) {
    if (IOUserClient::clientHasPrivilege(current_task(),kIOClientPrivilegeAdministrator)!=kIOReturnSuccess)
        return kIOReturnNotPrivileged;
    auto dict=OSDynamicCast(OSDictionary,properties);
    if (!dict||dict->getCount()!=1) return kIOReturnUnsupported;
    bool refresh=dict->getObject("Refresh")==kOSBooleanTrue;
    auto requested=OSDynamicCast(OSNumber,dict->getObject("FactoryMode"));
    bool tuneRead=dict->getObject("TuningRead")==kOSBooleanTrue;
    bool tuneRestore=dict->getObject("TuningRestore")==kOSBooleanTrue;
    auto tuneApply=OSDynamicCast(OSDictionary,dict->getObject("TuningApply"));
    if (!refresh&&!requested&&!tuneRead&&!tuneRestore&&!tuneApply) return kIOReturnUnsupported;
    if (requested&&requested->unsigned64BitValue()>2) return kIOReturnBadArgument;
    ROGTuningRequest tuningRequest={};
    if(tuneApply){
        if(tuneApply->getCount()!=3)return kIOReturnBadArgument;
        auto pl1=OSDynamicCast(OSNumber,tuneApply->getObject("pl1"));auto pl2=OSDynamicCast(OSNumber,tuneApply->getObject("pl2"));
        auto curves=OSDynamicCast(OSArray,tuneApply->getObject("curves"));
        if(!pl1||!pl2||pl1->unsigned64BitValue()>ROGPowerMaxW||pl2->unsigned64BitValue()>ROGPowerMaxW||!curves||curves->getCount()!=3)return kIOReturnBadArgument;
        tuningRequest.pl1=pl1->unsigned32BitValue();tuningRequest.pl2=pl2->unsigned32BitValue();
        for(unsigned i=0;i<3;i++){auto points=OSDynamicCast(OSArray,curves->getObject(i));if(!points||points->getCount()!=16)return kIOReturnBadArgument;
            for(unsigned j=0;j<16;j++){auto n=OSDynamicCast(OSNumber,points->getObject(j));if(!n||n->unsigned64BitValue()>255)return kIOReturnBadArgument;tuningRequest.curves[i].bytes[j]=n->unsigned8BitValue();}}
        if(!ROGValidTuning(tuningRequest))return kIOReturnBadArgument;
    }
    if (!IOLockTryLock(lock)) return kIOReturnBusy;
    IOReturn status=kIOReturnNotReady;
    if (!stopped&&device&&!isInactive()) {
        if (refresh) status=snapshot();
        else if(requested){status=factoryMode(requested->unsigned32BitValue());if(!status){tuning=ROGTuningState{};publishTuning();}}
        else status=tuningCommand(tuneRead?0:tuneApply?1:2,tuneApply?&tuningRequest:nullptr);
    }
    IOLockUnlock(lock);return status;
}
extern "C" {
extern kern_return_t _start(kmod_info_t *,void *);
extern kern_return_t _stop(kmod_info_t *,void *);
KMOD_EXPLICIT_DECL(com.macdriver.ROGFirmwareProbe,"1.5.0",_start,_stop)
__private_extern__ kmod_start_func_t *_realmain=nullptr;
__private_extern__ kmod_stop_func_t *_antimain=nullptr;
__private_extern__ int _kext_apple_cc=__APPLE_CC__;
}
