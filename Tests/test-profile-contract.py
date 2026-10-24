"""Compile the actual mode methods against a host firmware simulator.

Verifies command boundaries and failure handling; cannot validate real SMI
behaviour, BIOS responsiveness, or actual fan/power changes.
"""
import pathlib,subprocess,tempfile
base=pathlib.Path(__file__).resolve().parents[1]
source=(base/'Driver/ROGFirmwareProbe.cpp').read_text()
methods=source[source.index('IOReturn ROGFirmwareProbe::modeWmi'):source.index('IOReturn ROGFirmwareProbe::setProperties')]
fixture=r'''
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
using IOReturn=int;
constexpr int kIOReturnSuccess=0,kIOReturnUnsupported=1,kIOReturnBadArgument=2,kIOReturnNotFound=3,kIOReturnNoMemory=4,kIOReturnNotReady=5,kIOReturnError=6;
struct State {bool verified=true,ec=true,wrongName=false,method=true,present=true,readError=false,apply=true;uint32_t mode=1,power=1,reply=1;int queryStatus=0,writeStatus=0,queries=0,writes=0,refs=0,sleeps=0,snapshots=0;} g;
struct OSObject {virtual ~OSObject()=default;void release(){delete this;}};
struct OSNumber:OSObject {uint64_t v;static OSNumber*withNumber(uint64_t v,unsigned){auto p=new OSNumber;p->v=v;return p;}uint32_t unsigned32BitValue(){return v;}};
struct OSData:OSObject {std::vector<uint8_t>b;static OSData*withBytes(void*data,size_t size){auto p=new OSData;p->b.assign((uint8_t*)data,(uint8_t*)data+size);return p;}};
#define OSDynamicCast(type,obj) dynamic_cast<type*>(obj)
struct IORegistryEntry {virtual ~IORegistryEntry()=default;static IORegistryEntry*fromPath(const char*);void release(){g.refs--;}};
struct IOACPIPlatformDevice:IORegistryEntry {
 const char*getName(){return g.wrongName?"OTHER":"EC0";}
 int validateObject(const char*m){assert(!strcmp(m,"WMNB"));return g.method?0:kIOReturnNotFound;}
 int evaluateObject(const char*m,OSObject**out,OSObject**p,unsigned count){
  assert(!strcmp(m,"WMNB")&&count==3);
  assert(dynamic_cast<OSNumber*>(p[0])->v==0);
  auto op=dynamic_cast<OSNumber*>(p[1])->v;auto data=dynamic_cast<OSData*>(p[2]);
  assert(data&&data->b.size()==24);uint32_t words[6];memcpy(words,data->b.data(),24);
  assert(words[0]==0x120075&&words[2]==0&&words[3]==0&&words[4]==0&&words[5]==0);
  if(op==0x53545344){g.queries++;assert(words[1]==0);if(g.queryStatus)return g.queryStatus;*out=OSNumber::withNumber(g.present?0x10001:0xfffffffe,32);return 0;}
  assert(op==0x53564544&&words[1]<=2);g.writes++;if(g.apply)g.mode=words[1];if(g.writeStatus)return g.writeStatus;*out=OSNumber::withNumber(g.reply,32);return 0;
 }
} ec;
IORegistryEntry*IORegistryEntry::fromPath(const char*p){assert(!strcmp(p,"IOACPIPlane:/_SB/PC00@0/LPCB@1f0000/EC0"));if(!g.ec)return nullptr;g.refs++;return &ec;}
void IOSleep(unsigned ms){assert(ms==50);g.sleeps++;}
struct ROGModelProfile {const char *ecRegistryPath;};
static const ROGModelProfile modelProfile={"IOACPIPlane:/_SB/PC00@0/LPCB@1f0000/EC0"};
struct ROGFirmwareProbe {
 const ROGModelProfile *profile=&modelProfile;
 IOACPIPlatformDevice *device=&ec;
 bool verifyFirmware(){return g.verified;}
 template<class T>void setProperty(const char*,T){}
 void setProperty(const char*,uint32_t,unsigned){}
 void removeProperty(const char*){}
 int readByte(IOACPIPlatformDevice*d,const char*name,uint32_t&value){assert(d==&ec);if(g.readError)return 9;if(!strcmp(name,"FANM"))value=g.mode;else {assert(!strcmp(name,"ACIN"));value=g.power;}return 0;}
 int snapshot(){g.snapshots++;return 0;}
 IOReturn modeWmi(uint32_t,uint32_t,uint32_t&);
 IOReturn factoryMode(uint32_t);
};
'''
checks=r'''
int main(){ROGFirmwareProbe p;auto reset=[](){assert(g.refs==0);g=State{};};
 assert(p.factoryMode(3)==kIOReturnBadArgument&&!g.writes&&!g.queries);reset();
 assert(p.factoryMode(0xffffffff)==kIOReturnBadArgument&&!g.writes&&!g.queries);reset();
 g.verified=false;assert(p.factoryMode(0)==kIOReturnUnsupported&&!g.writes&&!g.queries);reset();
 g.ec=false;assert(p.factoryMode(0)==kIOReturnNotFound&&!g.writes&&!g.queries);reset();
 g.wrongName=true;assert(p.factoryMode(0)==kIOReturnNotFound&&!g.writes&&!g.queries);reset();
 g.power=0;assert(p.factoryMode(0)==kIOReturnNotReady&&!g.writes&&!g.queries);reset();
 g.mode=3;assert(p.factoryMode(0)==kIOReturnNotReady&&!g.writes&&!g.queries);reset();
 g.mode=4;assert(p.factoryMode(1)==0&&g.mode==1&&g.writes==1);reset();
 g.readError=true;assert(p.factoryMode(0)==kIOReturnNotReady&&!g.writes&&!g.queries);reset();
 g.present=false;assert(p.factoryMode(0)==kIOReturnUnsupported&&!g.writes&&g.queries==1);reset();
 g.queryStatus=7;assert(p.factoryMode(0)==7&&!g.writes);reset();
 g.method=false;assert(p.factoryMode(0)==kIOReturnNotFound&&!g.writes);reset();
 assert(p.factoryMode(1)==0&&!g.writes&&!g.queries&&g.mode==1);reset();
 assert(p.factoryMode(2)==0&&g.writes==1&&g.mode==2&&g.sleeps==0);assert(p.factoryMode(0)==0&&g.mode==0);assert(p.factoryMode(1)==0&&g.mode==1);reset();
 g.writeStatus=8;assert(p.factoryMode(0)==8&&g.writes==1);reset();
 g.reply=0;assert(p.factoryMode(0)==kIOReturnError&&g.writes==1);reset();
 g.apply=false;assert(p.factoryMode(0)==kIOReturnError&&g.mode==1&&g.writes==1&&g.sleeps==10);reset();
 uint32_t raw=0;assert(p.modeWmi(0x54494e49,0,raw)==kIOReturnUnsupported&&!g.writes&&!g.queries);
 assert(p.modeWmi(0x53564544,4,raw)==kIOReturnBadArgument&&!g.writes&&!g.queries);reset();
 puts("PASS: argument bounds, exact 24-byte payload and endpoint, firmware/model/EC/power guards, unsupported query, write errors, readback mismatch, finite polling, no-op, both profiles and restoration, reference release");
}
'''
with tempfile.TemporaryDirectory() as temporary:
    path=pathlib.Path(temporary)
    (path/'test.cpp').write_text(fixture+methods+checks)
    subprocess.run(['/usr/bin/clang++','-std=c++17','-Wall','-Wextra','-Werror',str(path/'test.cpp'),'-o',str(path/'test')],check=True)
    subprocess.run([str(path/'test')],check=True)
# Static boundary check complements the simulator: these lifecycle methods must
# never gain ACPI reads/writes or asynchronous firmware callbacks.
for start,end in [('bool ROGFirmwareProbe::start','void ROGFirmwareProbe::stop'),('void ROGFirmwareProbe::stop','void ROGFirmwareProbe::free'),('void ROGFirmwareProbe::free','bool ROGFirmwareProbe::verifyFirmware')]:
    body=source[source.index(start):source.index(end)]
    assert not any(x in body for x in ['evaluateObject','evaluateInteger','factoryMode(','modeWmi(','snapshot(','verifyFirmware(','tuningCommand(','tuningWmi(','tuneCurve(','tunePower(','IOTimer','thread_call'])
assert source.count('device->evaluateObject("WMNB"')==1
print('PASS: no firmware calls in start/stop/free; single fixed WMNB dispatch site')
