#import "Sensors.h"
#import <IOKit/IOKitLib.h>
#include <unistd.h>
#include <math.h>
#include <fcntl.h>

typedef struct {uint8_t major,minor,build,reserved;uint16_t release;} ROGSMCVersion;
typedef struct {uint16_t version,length;uint32_t cpu,gpu,mem;} ROGSMCLimits;
typedef struct {uint32_t size,type;uint8_t attributes;} ROGSMCKeyInfo;
typedef struct {uint32_t key;ROGSMCVersion version;ROGSMCLimits limits;ROGSMCKeyInfo info;uint8_t result,status,command;uint32_t data32;uint8_t bytes[32];} ROGSMCMessage;
_Static_assert(sizeof(ROGSMCMessage)==80,"AppleSMC ABI size");

static NSNumber *readSMC(io_connect_t connection,const char *key) {
    ROGSMCMessage input={0},output={0};size_t size=sizeof(output);
    for(unsigned i=0;i<4;i++)input.key=(input.key<<8)|(uint8_t)key[i];
    input.command=9;
    if(IOConnectCallStructMethod(connection,2,&input,sizeof(input),&output,&size)||output.result||output.info.size>32)return nil;
    uint32_t length=output.info.size,type=output.info.type;
    input.info.size=length;input.command=5;memset(&output,0,sizeof(output));size=sizeof(output);
    if(IOConnectCallStructMethod(connection,2,&input,sizeof(input),&output,&size)||output.result)return nil;
    char format[5]={(char)(type>>24),(char)(type>>16),(char)(type>>8),(char)type,0};double value=NAN;
    if(length==2&&!strcmp(format,"sp78"))value=(int16_t)((output.bytes[0]<<8)|output.bytes[1])/256.0;
    else if(length==2&&!strcmp(format,"sp96"))value=(int16_t)((output.bytes[0]<<8)|output.bytes[1])/64.0;
    else if(length==4&&!strcmp(format,"flt ")){float f;memcpy(&f,output.bytes,4);value=f;}
    return isfinite(value)?@(value):nil;
}
static NSDictionary *metric(NSNumber *value,NSString *unit,NSString *source,double low,double high) {
    if(!value||!isfinite(value.doubleValue)||value.doubleValue<low||value.doubleValue>high)return @{@"available":@NO,@"unit":unit};
    return @{@"available":@YES,@"value":value,@"unit":unit,@"source":source};
}
static NSDictionary *powerMetricsSample(void) {
    NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/powermetrics"];
    task.arguments=@[@"--samplers",@"cpu_power",@"-n",@"1",@"-i",@"200",@"-f",@"plist",@"--handle-invalid-values"];
    char temporary[]="/var/tmp/rogctrl-powermetrics.XXXXXX";int fd=mkstemp(temporary);if(fd<0)return @{};unlink(temporary);
    NSFileHandle *output=[[NSFileHandle alloc]initWithFileDescriptor:fd closeOnDealloc:YES];
    task.standardOutput=output;task.standardError=[NSFileHandle fileHandleWithNullDevice];
    if(![task launchAndReturnError:NULL])return @{};
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:2];
    // This sampler is fixed and read-only; no shell, paths or options come from a client.
    while(task.running&&deadline.timeIntervalSinceNow>0)usleep(10000);
    if(task.running){[task terminate];return @{};}
    [output seekToFileOffset:0];NSData *raw=[output readDataOfLength:1024*1024];if(task.terminationStatus!=0)return @{};
    const char *bytes=raw.bytes;const char *end=raw.length?memchr(bytes,0,raw.length):NULL;
    NSData *first=end?[raw subdataWithRange:NSMakeRange(0,(NSUInteger)(end-bytes))]:raw;
    id value=[NSPropertyListSerialization propertyListWithData:first options:NSPropertyListImmutable format:NULL error:NULL];
    return [value isKindOfClass:NSDictionary.class]?value:@{};
}
NSDictionary *ROGHardwareSensors(BOOL refresh) {
    io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("AppleSMC"));io_connect_t connection=0;
    NSNumber *temperature=nil,*package=nil,*gpuTemperature=nil;
    if(service){kern_return_t status=IOServiceOpen(service,mach_task_self(),0,&connection);IOObjectRelease(service);
        if(!status){temperature=readSMC(connection,"TC0P");package=readSMC(connection,"PCPR");gpuTemperature=readSMC(connection,"TG0D");if(!gpuTemperature)gpuTemperature=readSMC(connection,"TG0P");IOServiceClose(connection);}}
    static NSDictionary *sample;static NSDate *sampleAt;
    if(refresh&&geteuid()==0&&(!sampleAt||-sampleAt.timeIntervalSinceNow>0.5)){sample=powerMetricsSample();sampleAt=NSDate.date;}
    id hz=sample[@"processor"][@"freq_hz"];
    NSNumber *mhz=[hz isKindOfClass:NSNumber.class]?@([hz doubleValue]/1e6):nil;
    // PCPC is mapped to core-domain power by SMCProcessor. PCPR is the package
    // energy domain; do not label the core-only PCPC number as package power.
    return @{@"CPU":@{@"temperature":metric(temperature,@"°C",@"SMC TC0P",5,125),@"power":metric(package,@"W",@"SMC PCPR · CPU package",0,500),@"frequency":metric(mhz,@"MHz",@"powermetrics · interval average",10,10000)},
             @"GPU":@{@"temperature":metric(gpuTemperature,@"°C",@"SMC TG0D / TG0P",5,125),@"power":@{@"available":@NO,@"unit":@"W"},@"frequency":@{@"available":@NO,@"unit":@"MHz"}},
             @"GPUStatus":@"GPU 监控后端尚未适配当前驱动；未读到有效数据的项目显示为不可用。"};
}
