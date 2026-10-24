#pragma once
#include <stdint.h>
#include "../Shared/TuningLimits.h"
#include "../Shared/CurvePolicy.h"

// Independently implemented policy for the audited G815LW firmware interface.
// Curve bytes: eight Celsius breakpoints followed by eight firmware percentages.
struct ROGFanCurve { uint8_t bytes[16]; };
struct ROGTuningRequest { ROGFanCurve curves[3]; uint32_t pl1,pl2; };
static constexpr uint32_t ROGPowerMinW=ROG_MIN_POWER_W,ROGPowerMaxW=ROG_MAX_POWER_W;
static inline bool ROGValidCurve(const ROGFanCurve &c) {
    return ROGCurveOrdered(c.bytes,20);
}
static inline bool ROGValidTuning(const ROGTuningRequest &r) {
    if(r.pl1<ROGPowerMinW||r.pl2<ROGPowerMinW||r.pl1>ROGPowerMaxW||r.pl2>ROGPowerMaxW||r.pl1>r.pl2)return false;
    for(const auto &c:r.curves)if(!ROGValidCurve(c))return false;
    return true;
}
// Factory tables are displayed exactly as received. They can contain repeated
// breakpoints and are not silently rewritten into a custom curve.
static inline bool ROGFactoryCurveReadable(const ROGFanCurve &c) {
    bool nonzero=false;
    for(unsigned i=0;i<8;i++){if(c.bytes[i]>100||c.bytes[i+8]>100)return false;nonzero|=c.bytes[i+8]!=0;}
    return nonzero;
}
struct ROGTuningState {
    bool ready=false,active=false,powerReadback=false,curveAcknowledged=false,restoreAttempted=false,restoreConfirmed=false;
    uint32_t baseMode=0,mode=0,pl1=0,pl2=0;
    int lastStatus=0,restoreStatus=0;
    ROGFanCurve factory[3]={};
    ROGFanCurve quiet[3]={};
};
enum ROGTuningResult { ROGTuneOK=0,ROGTuneInvalid=1,ROGTuneNotReady=2,ROGTuneUnsupported=3,ROGTuneIO=4,ROGTuneReadback=5 };

// IO is a narrow adapter, not an arbitrary firmware command executor. All calls
// below are synchronous; recovery cannot interrupt an ACPI/SMI call that hangs.
template<class IO> class ROGTuningEngine {
    IO &io;ROGTuningState &s;
    int finish(int result){s.lastStatus=result;return result;}
    bool context(uint32_t &mode) {
        uint32_t ac=0;return io.modelMatches()&&io.readContext(ac,mode)&&ac==1&&(mode<=2||(mode==4&&(s.ready||s.active||s.restoreAttempted)));
    }
    void recover() {
        s.restoreAttempted=true;s.ready=false;s.active=false;s.powerReadback=false;s.curveAcknowledged=false;
        uint32_t mode=0,ac=0;
        bool ok=io.restoreFactory(s.baseMode);
        s.restoreConfirmed=ok&&io.readContext(ac,mode)&&mode==s.baseMode;
        s.restoreStatus=s.restoreConfirmed?ROGTuneOK:ROGTuneIO;
        // If rollback cannot be confirmed, keep the actual firmware mode visible.
        if(io.readContext(ac,mode))s.mode=mode;
    }
public:
    ROGTuningEngine(IO &adapter,ROGTuningState &state):io(adapter),s(state){}
    int read() {
        uint32_t mode=0;if(!context(mode)){s.ready=false;return finish(ROGTuneNotReady);}
        uint32_t base=mode==4?s.baseMode:mode;
        s.ready=false;s.powerReadback=false;s.curveAcknowledged=false;s.restoreAttempted=false;s.restoreConfirmed=false;
        s.mode=mode;s.baseMode=base;
        // Curve banks swap Turbo and Silent relative to factory mode numbers.
        uint32_t bank=base==1?2:base==2?1:0;
        for(unsigned i=0;i<3;i++)if(!io.readFactoryCurve(i,bank,s.factory[i])||!ROGFactoryCurveReadable(s.factory[i]))return finish(ROGTuneUnsupported);
        for(unsigned i=0;i<3;i++)if(!io.readFactoryCurve(i,1,s.quiet[i])||!ROGCurveOrdered(s.quiet[i].bytes,0))return finish(ROGTuneUnsupported);
        if(!io.powerSupported())return finish(ROGTuneUnsupported);
        if(!io.readPower(s.pl1,s.pl2))return finish(ROGTuneIO);
        s.ready=true;return finish(ROGTuneOK);
    }
    int apply(const ROGTuningRequest &r) {
        if(!ROGValidTuning(r))return finish(ROGTuneInvalid);
        if(!s.ready)return finish(ROGTuneNotReady);
        for(unsigned i=0;i<3;i++)if(!ROGCurveAboveQuiet(r.curves[i].bytes,s.quiet[i].bytes))return finish(ROGTuneInvalid);
        uint32_t mode=0;if(!context(mode)||(mode!=4&&mode!=s.baseMode))return finish(ROGTuneNotReady);
        if(!io.powerSupported())return finish(ROGTuneUnsupported);
        s.restoreAttempted=false;s.restoreConfirmed=false;s.powerReadback=false;s.curveAcknowledged=false;
        for(unsigned i=0;i<3;i++)if(!io.writeCurve(i,r.curves[i])){recover();return finish(ROGTuneIO);}
        uint32_t ac=0;if(!io.readContext(ac,mode)||ac!=1||mode!=4){recover();return finish(ROGTuneReadback);}
        s.mode=mode;s.curveAcknowledged=true;
        uint32_t before1=0,before2=0;
        if(!io.readPower(before1,before2)){recover();return finish(ROGTuneIO);}
        // Choose ordering so a lower PL2 does not temporarily fall below PL1.
        bool lowerPL1First=before1>r.pl2;
        bool ok=lowerPL1First?(io.writePL1(r.pl1)&&io.writePL2(r.pl2)):(io.writePL2(r.pl2)&&io.writePL1(r.pl1));
        if(!ok){recover();return finish(ROGTuneIO);}
        if(!io.readContext(ac,mode)||ac!=1||mode!=4||!io.readPower(s.pl1,s.pl2)||s.pl1!=r.pl1||s.pl2!=r.pl2){recover();return finish(ROGTuneReadback);}
        s.mode=mode;s.active=true;s.powerReadback=true;return finish(ROGTuneOK);
    }
    int restore() {
        // Revalidate identity and AC before invoking the fixed factory endpoint.
        uint32_t mode=0;if(!s.ready&&!s.active&&!s.restoreAttempted)return finish(ROGTuneNotReady);
        if(!context(mode))return finish(ROGTuneNotReady);
        recover();return finish(s.restoreConfirmed?ROGTuneOK:ROGTuneReadback);
    }
};
