#include "../Driver/TuningPolicy.hpp"
#include <cassert>
#include <cstdio>
#include <vector>

struct Firmware {
    bool model=true,ac=true,supported=true,curveReadable=true,restoreFails=false,mismatch=false,powerReadFails=false,cutPower=false;
    uint32_t mode=1,pl1=140,pl2=175,bank=99;unsigned reads=0,writes=0,curveWrites=0,failWrite=0,restores=0;
    std::vector<unsigned> order,banks;
    bool modelMatches(){reads++;return model;}
    bool readContext(uint32_t &a,uint32_t &m){reads++;a=ac;m=mode;return true;}
    bool readFactoryCurve(unsigned index,uint32_t b,ROGFanCurve &c){assert(index<3);reads++;bank=b;banks.push_back(b);c={{30,40,50,60,70,80,90,100,0,10,20,30,50,70,90,100}};if(b==1)c={{30,40,50,60,70,80,90,100,0,5,10,20,30,40,50,60}};return curveReadable;}
    bool powerSupported(){reads++;return supported;}
    bool readPower(uint32_t &a,uint32_t &b){reads++;a=pl1;b=pl2;if(mismatch&&curveWrites==3&&order.size()>=2)a=0;return !powerReadFails;}
    bool writeCurve(unsigned index,const ROGFanCurve &c){assert(index<3&&ROGValidCurve(c));writes++;curveWrites++;if(writes==failWrite)return false;mode=4;if(cutPower&&curveWrites==3)ac=false;return true;}
    bool writePL1(uint32_t w){assert(w<=175&&w>=5);order.push_back(1);writes++;if(writes==failWrite)return false;pl1=w;return true;}
    bool writePL2(uint32_t w){assert(w<=175&&w>=5);order.push_back(2);writes++;if(writes==failWrite)return false;pl2=w;return true;}
    bool restoreFactory(uint32_t target){assert(target<=2);restores++;if(restoreFails)return false;mode=target;return true;}
};
static ROGTuningRequest request(){ROGTuningRequest r={};r.pl1=80;r.pl2=100;for(auto &c:r.curves)c={{30,40,50,60,70,80,90,100,0,10,20,30,50,70,90,100}};return r;}
int main(){
    auto r=request();assert(ROGValidTuning(r));r.pl1=r.pl2=175;assert(ROGValidTuning(r));
    for(auto watts:{0u,4u,176u,255u,0xffffffffu}){r=request();r.pl1=watts;assert(!ROGValidTuning(r));r=request();r.pl2=watts;assert(!ROGValidTuning(r));}
    r=request();r.pl1=101;assert(!ROGValidTuning(r));
    r=request();r.curves[0].bytes[2]=r.curves[0].bytes[1];assert(!ROGValidTuning(r));
    r=request();r.curves[1].bytes[12]=20;assert(!ROGValidTuning(r));
    r=request();r.curves[2].bytes[15]=99;assert(ROGValidTuning(r));
    r=request();r.curves[0].bytes[8]=101;assert(!ROGValidTuning(r));
    for(unsigned mode=0;mode<3;mode++){
        Firmware f;f.mode=mode;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(!f.reads&&!f.writes);
        assert(e.apply(request())==ROGTuneNotReady&&!f.reads&&!f.writes);
        assert(e.read()==0&&s.ready&&s.baseMode==mode&&f.banks[0]==(mode==1?2u:mode==2?1u:0u)&&f.banks[3]==1&&!f.writes);
        assert(e.apply(request())==0&&s.active&&s.powerReadback&&s.curveAcknowledged&&f.mode==4&&s.pl1==80&&s.pl2==100);
        assert(f.order[0]==1&&f.order[1]==2);assert(e.restore()==0&&f.mode==mode&&s.restoreConfirmed&&!s.ready&&!s.active);
    }
    {Firmware f;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);e.read();auto bad=request();bad.pl2=176;unsigned reads=f.reads;assert(e.apply(bad)==ROGTuneInvalid&&f.reads==reads&&!f.writes);}
    {Firmware f;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(!e.read());auto low=request();for(auto &c:low.curves)for(unsigned i=8;i<16;i++)c.bytes[i]=0;assert(ROGValidTuning(low));unsigned reads=f.reads;assert(e.apply(low)==ROGTuneInvalid&&!f.writes&&f.reads==reads);}
    {Firmware f;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(!e.read());auto quiet=request();for(unsigned i=0;i<3;i++)quiet.curves[i]=s.quiet[i];assert(!e.apply(quiet)&&s.active&&quiet.curves[0].bytes[15]==60);}
    {Firmware f;f.model=false;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(e.read()==ROGTuneNotReady&&!f.writes);}
    {Firmware f;f.ac=false;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(e.read()==ROGTuneNotReady&&!f.writes);}
    {Firmware f;f.mode=4;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(e.read()==ROGTuneNotReady&&!f.writes);}
    {Firmware f;f.supported=false;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(e.read()==ROGTuneUnsupported&&!f.writes);}
    {Firmware f;f.curveReadable=false;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(e.read()==ROGTuneUnsupported&&!s.ready&&!f.writes);}
    for(unsigned failure=1;failure<=5;failure++){
        Firmware f;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(!e.read());f.failWrite=failure;
        assert(e.apply(request())==ROGTuneIO&&f.restores==1&&f.mode==1&&s.restoreConfirmed&&!s.active&&!s.powerReadback);
    }
    {Firmware f;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(!e.read());f.mode=0;assert(e.apply(request())==ROGTuneNotReady&&!f.writes);}
    {Firmware f;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(!e.read());f.model=false;assert(e.apply(request())==ROGTuneNotReady&&!f.writes);}
    {Firmware f;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(!e.read());f.ac=false;assert(e.apply(request())==ROGTuneNotReady&&!f.writes);}
    {Firmware f;f.pl1=40;f.pl2=60;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(!e.read()&&!e.apply(request()));assert(f.order[0]==2&&f.order[1]==1);}
    {Firmware f;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(!e.read());f.mismatch=true;assert(e.apply(request())==ROGTuneReadback&&s.restoreConfirmed&&!s.active);}
    {Firmware f;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(!e.read());f.cutPower=true;assert(e.apply(request())==ROGTuneReadback&&s.restoreConfirmed&&f.order.empty());}
    {Firmware f;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(!e.read());f.powerReadFails=true;assert(e.apply(request())==ROGTuneIO&&s.restoreConfirmed);}
    {Firmware f;ROGTuningState s;ROGTuningEngine<Firmware> e(f,s);assert(!e.read());f.failWrite=4;f.restoreFails=true;assert(e.apply(request())==ROGTuneIO&&!s.restoreConfirmed&&s.restoreAttempted&&f.mode==4);f.restoreFails=false;assert(!e.restore()&&s.restoreConfirmed&&f.mode==1);}
    puts("PASS: 175W hard cap, PL1/PL2 relationship and ordering, curve validation, model/AC/mode guards, explicit-only IO, bank mapping, every partial-write failure, independent power readback, rollback confirmation and retry");
}
