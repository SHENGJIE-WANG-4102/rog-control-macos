#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#include <unistd.h>
int main(int argc,const char **argv) { @autoreleasepool {
    bool refresh=argc==2&&!strcmp(argv[1],"--refresh");
    bool mode=argc==3&&!strcmp(argv[1],"--mode")&&strlen(argv[2])==1&&argv[2][0]>='0'&&argv[2][0]<='2';
    if (!mode&&!refresh&&!(argc==2&&!strcmp(argv[1],"--read"))) {
        fprintf(stderr,"Usage: profile-client --read | --refresh | --mode 0|1|2\n");return 2;
    }
    if ((mode||refresh)&&geteuid()!=0) { fprintf(stderr,"Administrator privileges required to request telemetry.\n");return 2; }
    io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("ROGFirmwareProbe"));
    if (!service) { fprintf(stderr,"Telemetry probe is not loaded.\n");return 1; }
    CFTypeRef rawVersion=IORegistryEntryCreateCFProperty(service,CFSTR("BridgeVersion"),kCFAllocatorDefault,0);
    id version=CFBridgingRelease(rawVersion);
    if ((mode||refresh)&&![version isEqual:@"1.3.0"]) {
        fprintf(stderr,"Probe 1.3.0 is not active; the installed update needs a restart. No firmware request sent.\n");
        IOObjectRelease(service);return 1;
    }
    kern_return_t status=KERN_SUCCESS;
    if (refresh) status=IORegistryEntrySetCFProperties(service,(__bridge CFTypeRef)@{@"Refresh":@YES});
    if (mode) status=IORegistryEntrySetCFProperties(service,(__bridge CFTypeRef)@{@"FactoryMode":@((unsigned)(argv[2][0]-'0'))});
    NSMutableDictionary *report=[NSMutableDictionary dictionary];
    for (NSString *key in @[@"BridgeVersion",@"ReadOnly",@"OnDemandOnly",@"FirmwareQueriesAtStart",@"QueryState",@"Snapshot",@"FactoryModesOnly",@"ModeRequested",@"ModeBefore",@"ModeAfter",@"ModeMatched",@"ModeReadbackValid",@"ModeWriteIOReturn",@"ModeSupportRaw",@"ModeReplyRaw"]) {
        CFTypeRef value=IORegistryEntryCreateCFProperty(service,(__bridge CFStringRef)key,kCFAllocatorDefault,0);
        id object=CFBridgingRelease(value);if (object) report[key]=object;
    }
    report[@"CommandIOReturn"]=@((uint32_t)status);
    report[@"RequestedRefresh"]=@(refresh);
    if (mode) report[@"RequestedMode"]=@((unsigned)(argv[2][0]-'0'));
    report[@"CapturedAt"]=[[NSISO8601DateFormatter new] stringFromDate:[NSDate date]];
    NSError *error=nil;
    NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
    if (!json) { fprintf(stderr,"JSON error: %s\n",error.localizedDescription.UTF8String);IOObjectRelease(service);return 1; }
    fwrite(json.bytes,1,json.length,stdout);fputc('\n',stdout);
    IOObjectRelease(service);return status==KERN_SUCCESS?0:1;
} }
