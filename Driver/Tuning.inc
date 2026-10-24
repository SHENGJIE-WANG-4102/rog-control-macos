// Explicit tuning requests only. Never called from start/stop/free or timers.
IOReturn ROGFirmwareProbe::tuningWmi(uint32_t operation,uint32_t endpoint,const uint8_t *payload,unsigned length,OSObject **result) {
    const uint32_t curves[]={0x00110024U,0x00110025U,0x00110032U};
    bool curve=false;for(auto e:curves)if(endpoint==e)curve=true;
    bool power=endpoint==0x001200A3U||endpoint==0x001200A0U;
    if(!result||!payload||(!curve&&!power)||(operation!=0x53545344U&&operation!=0x53564544U))return kIOReturnUnsupported;
    *result=nullptr;
    if(operation==0x53545344U){if(length!=4)return kIOReturnBadArgument;uint32_t arg=0;memcpy(&arg,payload,4);if((curve&&arg>2)||(power&&arg))return kIOReturnBadArgument;}
    else if(curve){if(length!=16)return kIOReturnBadArgument;ROGFanCurve c;memcpy(c.bytes,payload,16);if(!ROGValidCurve(c))return kIOReturnBadArgument;}
    else {uint32_t watts=0;if(length!=4)return kIOReturnBadArgument;memcpy(&watts,payload,4);if(watts<ROGPowerMinW||watts>ROGPowerMaxW)return kIOReturnBadArgument;}
    if(device->validateObject("WMNB")!=kIOReturnSuccess)return kIOReturnNotFound;
    uint8_t bytes[24]={};memcpy(bytes,&endpoint,4);memcpy(bytes+4,payload,length);
    OSObject *args[3]={OSNumber::withNumber(static_cast<uint64_t>(0),32),OSNumber::withNumber(operation,32),OSData::withBytes(bytes,sizeof bytes)};
    IOReturn status=kIOReturnNoMemory;
    if(args[0]&&args[1]&&args[2])status=device->evaluateObject("WMNB",result,args,3);
    for(auto arg:args)if(arg)arg->release();return status;
}
bool ROGFirmwareProbe::tuneCurve(unsigned index,uint32_t bank,ROGFanCurve &curve,bool write) {
    if(index>2||bank>2)return false;
    const uint32_t endpoints[]={0x00110024U,0x00110025U,0x00110032U};OSObject *result=nullptr;
    const uint8_t *payload=write?curve.bytes:reinterpret_cast<const uint8_t*>(&bank);
    IOReturn status=tuningWmi(write?0x53564544U:0x53545344U,endpoints[index],payload,write?16:4,&result);
    bool ok=false;
    if(!status){
        if(write){auto n=OSDynamicCast(OSNumber,result);ok=n&&n->unsigned32BitValue()==1;}
        else {auto data=OSDynamicCast(OSData,result);ok=data&&data->getLength()==16;if(ok)memcpy(curve.bytes,data->getBytesNoCopy(),16);}
    }
    if(result)result->release();return ok;
}
bool ROGFirmwareProbe::tunePower(unsigned which,uint32_t value,bool write) {
    if(which>1)return false;
    uint32_t endpoint=which?0x001200A0U:0x001200A3U;OSObject *result=nullptr;
    IOReturn status=tuningWmi(write?0x53564544U:0x53545344U,endpoint,reinterpret_cast<const uint8_t*>(&value),4,&result);
    auto n=OSDynamicCast(OSNumber,result);uint32_t raw=n?n->unsigned32BitValue():0;
    bool ok=!status&&n&&(write?raw==1:(raw!=0xfffffffeU&&(raw&0x10000U)));
    if(result)result->release();return ok;
}
bool ROGFirmwareProbe::tuneContext(uint32_t &ac,uint32_t &mode) {
    if(!profile)return false;
    auto entry=IORegistryEntry::fromPath(profile->ecRegistryPath);auto ec=OSDynamicCast(IOACPIPlatformDevice,entry);
    bool ok=ec&&!strcmp(ec->getName(),"EC0")&&!readByte(ec,"ACIN",ac)&&!readByte(ec,"FANM",mode);
    if(entry)entry->release();return ok;
}
bool ROGFirmwareProbe::tuneReadPower(uint32_t &pl1,uint32_t &pl2) {
    if(!profile)return false;
    auto entry=IORegistryEntry::fromPath(profile->ecRegistryPath);auto ec=OSDynamicCast(IOACPIPlatformDevice,entry);
    bool ok=ec&&!strcmp(ec->getName(),"EC0")&&!readByte(ec,"M6F0",pl1)&&!readByte(ec,"M6F1",pl2);
    if(entry)entry->release();return ok;
}
struct ROGFirmwareProbe::TuningIO {
    ROGFirmwareProbe *p;
    bool modelMatches(){return p->verifyFirmware();}
    bool readContext(uint32_t &ac,uint32_t &mode){return p->tuneContext(ac,mode);}
    bool readFactoryCurve(unsigned i,uint32_t bank,ROGFanCurve &c){return p->tuneCurve(i,bank,c,false);}
    bool powerSupported(){return p->tunePower(0,0,false)&&p->tunePower(1,0,false);}
    bool readPower(uint32_t &a,uint32_t &b){return p->tuneReadPower(a,b);}
    bool writeCurve(unsigned i,const ROGFanCurve &c){ROGFanCurve copy=c;return p->tuneCurve(i,0,copy,true);}
    bool writePL1(uint32_t w){return p->tunePower(0,w,true);}
    bool writePL2(uint32_t w){return p->tunePower(1,w,true);}
    bool restoreFactory(uint32_t mode){uint32_t reply=0;return !p->modeWmi(0x53564544U,mode,reply)&&reply==1;}
};
void ROGFirmwareProbe::publishTuning() {
    OSDictionary *d=OSDictionary::withCapacity(15);if(!d)return;
    auto number=[&](const char *key,uint32_t v){OSNumber *n=OSNumber::withNumber(v,32);if(n){d->setObject(key,n);n->release();}};
    auto boolean=[&](const char *key,bool v){d->setObject(key,v?kOSBooleanTrue:kOSBooleanFalse);};
    boolean("Ready",tuning.ready);boolean("Active",tuning.active);boolean("PowerReadback",tuning.powerReadback);boolean("CurveAcknowledged",tuning.curveAcknowledged);
    boolean("RestoreAttempted",tuning.restoreAttempted);boolean("RestoreConfirmed",tuning.restoreConfirmed);
    number("BaseMode",tuning.baseMode);number("FirmwareMode",tuning.mode);number("PL1",tuning.pl1);number("PL2",tuning.pl2);number("MaximumWatts",ROGPowerMaxW);
    number("Status",static_cast<uint32_t>(tuning.lastStatus));number("RestoreStatus",static_cast<uint32_t>(tuning.restoreStatus));
    auto publishCurves=[&](const char *key,const ROGFanCurve *values){
        OSArray *curves=OSArray::withCapacity(3);
        if(curves){for(unsigned i=0;i<3;i++){OSArray *points=OSArray::withCapacity(16);if(points){for(auto byte:values[i].bytes){OSNumber *n=OSNumber::withNumber(byte,8);if(n){points->setObject(n);n->release();}}curves->setObject(points);points->release();}}d->setObject(key,curves);curves->release();}
    };
    publishCurves("FactoryCurves",tuning.factory);publishCurves("QuietCurves",tuning.quiet);
    setProperty("Tuning",d);d->release();
}
IOReturn ROGFirmwareProbe::tuningCommand(unsigned command,const ROGTuningRequest *request) {
    TuningIO io={this};ROGTuningEngine<TuningIO> engine(io,tuning);int result=ROGTuneInvalid;
    if(command==0)result=engine.read();else if(command==1&&request)result=engine.apply(*request);else if(command==2)result=engine.restore();
    publishTuning();snapshot();
    switch(result){case ROGTuneOK:return kIOReturnSuccess;case ROGTuneInvalid:return kIOReturnBadArgument;case ROGTuneNotReady:return kIOReturnNotReady;case ROGTuneUnsupported:return kIOReturnUnsupported;default:return kIOReturnError;}
}
