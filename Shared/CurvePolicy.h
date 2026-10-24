#pragma once
#include <stdint.h>

typedef struct {uint32_t numerator,denominator;} ROGCurveSample;
static inline int ROGCurveOrdered(const uint8_t *c,int minimumTemperature) {
    for(unsigned i=0;i<8;i++){
        if(c[i]<minimumTemperature||c[i]>100||c[i+8]>100)return 0;
        if(i&&(c[i]<=c[i-1]||c[i+8]<c[i+7]))return 0;
    }return 1;
}
// Endpoint extension matches the firmware's eight-point curve representation.
// Keep rational values so a curve identical to the factory preset remains valid.
static inline ROGCurveSample ROGCurveSampleAt(const uint8_t *c,unsigned temperature) {
    if(temperature<=c[0])return (ROGCurveSample){c[8],1};
    for(unsigned i=1;i<8;i++)if(temperature<=c[i]){
        unsigned span=c[i]-c[i-1];
        return (ROGCurveSample){c[i+7]*(c[i]-temperature)+c[i+8]*(temperature-c[i-1]),span};
    }
    return (ROGCurveSample){c[15],1};
}
static inline unsigned ROGCurveFloorAt(const uint8_t *quiet,unsigned temperature) {
    ROGCurveSample s=ROGCurveSampleAt(quiet,temperature);return (s.numerator+s.denominator-1)/s.denominator;
}
static inline int ROGCurveAboveQuiet(const uint8_t *curve,const uint8_t *quiet) {
    if(!ROGCurveOrdered(curve,20)||!ROGCurveOrdered(quiet,0))return 0;
    // Every knot is an integer Celsius value. Comparing all integer temperatures
    // also bounds every linear interval between knots, including both tails.
    for(unsigned t=20;t<=100;t++){
        ROGCurveSample a=ROGCurveSampleAt(curve,t),b=ROGCurveSampleAt(quiet,t);
        if(a.numerator*b.denominator<b.numerator*a.denominator)return 0;
    }return 1;
}
static inline void ROGCurveRaise(uint8_t *curve,unsigned index,unsigned value) {
    if(value>100)value=100;
    if(curve[index+8]<value)curve[index+8]=(uint8_t)value;
    for(unsigned i=index+1;i<8;i++)if(curve[i+8]<curve[i+7])curve[i+8]=curve[i+7];
}
static inline unsigned ROGCurveCeilPositive(int numerator,unsigned denominator) {
    return numerator>0?((unsigned)numerator+denominator-1)/denominator:0;
}
// Repair only by raising points after the user's intended raise/lower cascade.
// Prefer the other endpoint of a segment so the grabbed point stays where the
// user put it whenever a bounded straight segment can satisfy the quiet floor.
static inline int ROGCurveRepairFloor(uint8_t *curve,const uint8_t *quiet,unsigned selected) {
    if(!ROGCurveOrdered(curve,20)||!ROGCurveOrdered(quiet,0))return 0;
    for(unsigned t=20;t<=100;t++){
        ROGCurveSample a=ROGCurveSampleAt(curve,t),b=ROGCurveSampleAt(quiet,t);
        if(a.numerator*b.denominator>=b.numerator*a.denominator)continue;
        if(t<=curve[0]){ROGCurveRaise(curve,0,ROGCurveFloorAt(quiet,t));continue;}
        if(t>=curve[7]){ROGCurveRaise(curve,7,ROGCurveFloorAt(quiet,t));continue;}
        unsigned right=1;while(right<7&&t>curve[right])right++;
        unsigned left=right-1,wa=curve[right]-t,wb=t-curve[left],span=wa+wb;
        if(selected==right&&wa){
            unsigned need=ROGCurveCeilPositive((int)(b.numerator*span)-(int)(curve[right+8]*wb*b.denominator),wa*b.denominator);
            ROGCurveRaise(curve,left,need);
            if(need>100&&wb)ROGCurveRaise(curve,right,ROGCurveCeilPositive((int)(b.numerator*span)-(int)(100*wa*b.denominator),wb*b.denominator));
        }else if(wb){
            unsigned need=ROGCurveCeilPositive((int)(b.numerator*span)-(int)(curve[left+8]*wa*b.denominator),wb*b.denominator);
            ROGCurveRaise(curve,right,need);
            if(need>100&&wa)ROGCurveRaise(curve,left,ROGCurveCeilPositive((int)(b.numerator*span)-(int)(100*wb*b.denominator),wa*b.denominator));
        }
    }return ROGCurveAboveQuiet(curve,quiet);
}
