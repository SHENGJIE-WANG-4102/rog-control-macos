#import "Bridge.h"
#import "Sensors.h"
#import <IOKit/IOKitLib.h>
#import <CoreFoundation/CoreFoundation.h>
#include <unistd.h>
#include <math.h>
#include "../Shared/TuningLimits.h"

static BOOL integer(id value,NSInteger low,NSInteger high) {
    if(![value isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID())return NO;
    double d=[value doubleValue];return isfinite(d)&&d==floor(d)&&d>=low&&d<=high;
}

BOOL ROGValidRequest(id request) {
    if (![request isKindOfClass:NSDictionary.class]) return NO;
    NSDictionary *d=request;NSString *command=d[@"command"];
    if (![command isKindOfClass:NSString.class]) return NO;
    if ([command isEqual:@"status"]||[command isEqual:@"refresh"]||[command isEqual:@"quit"]) return d.count==1;
    if([command isEqual:@"tuningRead"]||[command isEqual:@"tuningRestore"])return d.count==1;
    if([command isEqual:@"tuningApply"]){
        if(d.count!=4||!integer(d[@"pl1"],ROG_MIN_POWER_W,ROG_MAX_POWER_W)||!integer(d[@"pl2"],ROG_MIN_POWER_W,ROG_MAX_POWER_W)||[d[@"pl1"] intValue]>[d[@"pl2"] intValue])return NO;
        id curves=d[@"curves"];if(![curves isKindOfClass:NSArray.class]||[curves count]!=ROG_FAN_COUNT)return NO;
        for(id curve in curves){if(![curve isKindOfClass:NSArray.class]||[curve count]!=16)return NO;
            for(unsigned i=0;i<8;i++){if(!integer(curve[i],20,100)||!integer(curve[i+8],0,100))return NO;
                if(i&&([curve[i] intValue]<=[curve[i-1] intValue]||[curve[i+8] intValue]<[curve[i+7] intValue]))return NO;}
        }return YES;
    }
    if (![command isEqual:@"mode"]||d.count!=2) return NO;
    id mode=d[@"mode"];
    if (![mode isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)mode)==CFBooleanGetTypeID()) return NO;
    double value=[mode doubleValue];return isfinite(value)&&value==floor(value)&&value>=0&&value<=2;
}

NSDictionary *ROGRead(NSString *command,NSNumber *mode) {
    return ROGReadRequest(mode?@{@"command":command,@"mode":mode}:@{@"command":command});
}
NSDictionary *ROGReadRequest(NSDictionary *request) {
    if(!ROGValidRequest(request)||[request[@"command"] isEqual:@"quit"])return @{@"error":@"不支持的操作或参数。",@"CommandIOReturn":@1};
    NSString *command=request[@"command"];NSNumber *mode=request[@"mode"];
    io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("ROGFirmwareProbe"));
    if (!service) return @{@"error":@"未找到模式驱动。",@"CommandIOReturn":@1};
    NSMutableDictionary *report=[NSMutableDictionary dictionary];
    id version=CFBridgingRelease(IORegistryEntryCreateCFProperty(service,CFSTR("BridgeVersion"),kCFAllocatorDefault,0));
    BOOL mutation=![command isEqual:@"status"];
    kern_return_t status=KERN_SUCCESS;
    BOOL tuning=[command hasPrefix:@"tuning"];
    BOOL compatible=[version isEqual:@"1.3.0"]||[version isEqual:@"1.4.0"]||[version isEqual:@"1.5.0"];
    if (mutation&&(!compatible||geteuid()!=0||(tuning&&![version isEqual:@"1.5.0"]))) {
        IOObjectRelease(service);return @{@"error":@"驱动版本不匹配或当前会话未授权。",@"CommandIOReturn":@1};
    }
    if ([command isEqual:@"refresh"]) status=IORegistryEntrySetCFProperties(service,(__bridge CFTypeRef)@{@"Refresh":@YES});
    else if ([command isEqual:@"mode"]&&mode&&ROGValidRequest(@{@"command":command,@"mode":mode}))
        status=IORegistryEntrySetCFProperties(service,(__bridge CFTypeRef)@{@"FactoryMode":mode});
    else if([command isEqual:@"tuningRead"])status=IORegistryEntrySetCFProperties(service,(__bridge CFTypeRef)@{@"TuningRead":@YES});
    else if([command isEqual:@"tuningRestore"])status=IORegistryEntrySetCFProperties(service,(__bridge CFTypeRef)@{@"TuningRestore":@YES});
    else if([command isEqual:@"tuningApply"])status=IORegistryEntrySetCFProperties(service,(__bridge CFTypeRef)@{@"TuningApply":@{@"curves":request[@"curves"],@"pl1":request[@"pl1"],@"pl2":request[@"pl2"]}});
    else if (mutation) {IOObjectRelease(service);return @{@"error":@"不支持的操作。",@"CommandIOReturn":@1};}
    for (NSString *key in @[@"BridgeVersion",@"OnDemandOnly",@"FirmwareQueriesAtStart",@"FactoryModesOnly",@"QueryState",@"Snapshot",@"ModeMatched",@"ModeRequested",@"ModeAfter",@"ModeWriteIOReturn",@"Tuning",@"TuningImplemented",@"MaximumPowerWatts"]) {
        id value=CFBridgingRelease(IORegistryEntryCreateCFProperty(service,(__bridge CFStringRef)key,kCFAllocatorDefault,0));
        if (value) report[key]=value;
    }
    IOObjectRelease(service);report[@"CommandIOReturn"]=@((uint32_t)status);report[@"command"]=command;
    report[@"Sensors"]=ROGHardwareSensors([command isEqual:@"refresh"]);
    report[@"CapturedAt"]=[[NSISO8601DateFormatter new] stringFromDate:NSDate.date];
    if (status!=KERN_SUCCESS) report[@"error"]=[NSString stringWithFormat:@"操作未完成（0x%08x），请重新读取状态。",(unsigned)status];
    return report;
}
