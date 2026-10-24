#import "Bridge.h"
#import "Sensors.h"
#import <IOKit/IOKitLib.h>
#import <CoreFoundation/CoreFoundation.h>
#include <unistd.h>
#include <math.h>

BOOL ROGValidRequest(id request) {
    if (![request isKindOfClass:NSDictionary.class]) return NO;
    NSDictionary *d=request;NSString *command=d[@"command"];
    if (![command isKindOfClass:NSString.class]) return NO;
    if ([command isEqual:@"status"]||[command isEqual:@"refresh"]||[command isEqual:@"quit"]) return d.count==1;
    if (![command isEqual:@"mode"]||d.count!=2) return NO;
    id mode=d[@"mode"];
    if (![mode isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)mode)==CFBooleanGetTypeID()) return NO;
    double value=[mode doubleValue];return isfinite(value)&&value==floor(value)&&value>=0&&value<=2;
}

NSDictionary *ROGRead(NSString *command,NSNumber *mode) {
    io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("ROGFirmwareProbe"));
    if (!service) return @{@"error":@"未找到模式驱动。",@"CommandIOReturn":@1};
    NSMutableDictionary *report=[NSMutableDictionary dictionary];
    id version=CFBridgingRelease(IORegistryEntryCreateCFProperty(service,CFSTR("BridgeVersion"),kCFAllocatorDefault,0));
    BOOL mutation=![command isEqual:@"status"];
    kern_return_t status=KERN_SUCCESS;
    if (mutation&&(![version isEqual:@"1.3.0"]||geteuid()!=0)) {
        IOObjectRelease(service);return @{@"error":@"驱动版本不匹配或当前会话未授权。",@"CommandIOReturn":@1};
    }
    if ([command isEqual:@"refresh"]) status=IORegistryEntrySetCFProperties(service,(__bridge CFTypeRef)@{@"Refresh":@YES});
    else if ([command isEqual:@"mode"]&&mode&&ROGValidRequest(@{@"command":command,@"mode":mode}))
        status=IORegistryEntrySetCFProperties(service,(__bridge CFTypeRef)@{@"FactoryMode":mode});
    else if (mutation) {IOObjectRelease(service);return @{@"error":@"不支持的操作。",@"CommandIOReturn":@1};}
    for (NSString *key in @[@"BridgeVersion",@"OnDemandOnly",@"FirmwareQueriesAtStart",@"FactoryModesOnly",@"QueryState",@"Snapshot",@"ModeMatched",@"ModeRequested",@"ModeAfter",@"ModeWriteIOReturn"]) {
        id value=CFBridgingRelease(IORegistryEntryCreateCFProperty(service,(__bridge CFStringRef)key,kCFAllocatorDefault,0));
        if (value) report[key]=value;
    }
    IOObjectRelease(service);report[@"CommandIOReturn"]=@((uint32_t)status);report[@"command"]=command;
    report[@"Sensors"]=ROGHardwareSensors([command isEqual:@"refresh"]);
    report[@"CapturedAt"]=[[NSISO8601DateFormatter new] stringFromDate:NSDate.date];
    if (status!=KERN_SUCCESS) report[@"error"]=[NSString stringWithFormat:@"操作未完成（0x%08x），请重新读取状态。",(unsigned)status];
    return report;
}
