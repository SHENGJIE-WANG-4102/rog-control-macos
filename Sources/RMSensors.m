#import "RMSensors.h"
#import "RMRUSD.h"
#import <IOKit/IOKitLib.h>
#include <unistd.h>
#include <math.h>
#include <mach/mach_time.h>

// The helper serializes requests. These observations retain no GPU objects and
// do not poll in the background; each field confirms its own timestamp progress.
static ROGRMProgress progress[7];
static uint64_t monotonicNS(void) {
    mach_timebase_info_data_t tb;mach_timebase_info(&tb);
    return (uint64_t)((__uint128_t)mach_continuous_time()*tb.numer/tb.denom);
}

typedef struct { io_connect_t ctl; NSString *__strong error; } RM;
static BOOL escape(RM *rm,uint32_t cmd,void *params,size_t size) {
    uint64_t scalar=cmd;size_t output=size;
    kern_return_t kr=IOConnectCallMethod(rm->ctl,1,&scalar,1,params,size,NULL,NULL,params,&output);
    if(kr||output!=size){rm->error=[NSString stringWithFormat:@"RM 传输失败：0x%08x",kr];return NO;}return YES;
}
static uint32_t allocate(RM *rm,uint32_t root,uint32_t parent,uint32_t object,uint32_t cls,void *params,uint32_t size) {
    ROGRMAlloc p={root,parent,object,cls,(uintptr_t)params,size,UINT32_MAX};
    BOOL ok=escape(rm,0x2b,&p,sizeof p);
    if(!ok||p.status){if(ok)rm->error=[NSString stringWithFormat:@"RM 对象 0x%x 不可用：0x%x",cls,p.status];return 0;}return p.object;
}
static BOOL control(RM *rm,uint32_t root,uint32_t object,uint32_t cmd,void *params,uint32_t size) {
    ROGRMControl p={root,object,cmd,0,(uintptr_t)params,size,UINT32_MAX};
    BOOL ok=escape(rm,0x2a,&p,sizeof p);
    if(!ok||p.status){if(ok)rm->error=[NSString stringWithFormat:@"RM 查询 0x%x 不可用：0x%x",cmd,p.status];return NO;}return YES;
}
static NSDictionary *metric(double value,BOOL valid,NSString *unit,NSString *source,double low,double high) {
    if(!valid||!isfinite(value)||value<low||value>high)return @{@"available":@NO,@"unit":unit};
    return @{@"available":@YES,@"value":@(value),@"unit":unit,@"source":source};
}
static NSDictionary *decode(const volatile void *bytes,size_t length) {
    uint64_t now=monotonicNS();
    ROGRMTemperature temp={0},memTemp={0};ROGRMClocks clocks={0};ROGRMPower power={0},average={0};ROGRMVRAM memory={0};ROGRMUtil util={0};ROGRMPState state={0};
    BOOL t=ROGRMReadSection(bytes,length,ROGRUSDTemperature,&temp,sizeof temp);
    BOOL mt=ROGRMReadSection(bytes,length,ROGRUSDMemoryTemperature,&memTemp,sizeof memTemp);
    BOOL c=ROGRMReadSection(bytes,length,ROGRUSDClocks,&clocks,sizeof clocks);
    BOOL p=ROGRMReadSection(bytes,length,ROGRUSDInstantPower,&power,sizeof power);
    BOOL a=ROGRMReadSection(bytes,length,ROGRUSDAveragePower,&average,sizeof average);
    t=ROGRMObserve(&progress[0],t?temp.timestamp:0,now);mt=ROGRMObserve(&progress[1],mt?memTemp.timestamp:0,now);
    c=ROGRMObserve(&progress[2],c?clocks.timestamp:0,now);p=ROGRMObserve(&progress[3],p?power.timestamp:0,now);a=ROGRMObserve(&progress[4],a?average.timestamp:0,now);
    BOOL m=ROGRMReadSection(bytes,length,ROGRUSDMemory,&memory,sizeof memory)&&memory.timestamp>=ROGRUSDSequenceStart&&memory.total>0&&memory.free<=memory.total&&memory.total<UINT64_C(1099511627776);
    BOOL u=ROGRMReadSection(bytes,length,ROGRUSDUtil,&util,sizeof util);u=ROGRMObserve(&progress[5],u?util.timestamp:0,now);
    BOOL s=ROGRMReadSection(bytes,length,ROGRUSDPState,&state,sizeof state);s=ROGRMObserve(&progress[6],s?state.timestamp:0,now)&&state.mask&&!(state.mask&(state.mask-1));
    double gib=1073741824.0;
    NSMutableDictionary *gpu=[@{
        @"temperature":metric(temp.fixedCelsius/256.0,t,@"°C",@"NVIDIA RM · GPU temperature",-20,130),
        @"frequency":metric(clocks.domains[0].actualKHz/1000.0,c,@"MHz",@"NVIDIA RM · actual graphics clock",0,10000),
        @"power":metric(power.gpuMW/1000.0,p,@"W",@"NVIDIA RM · instantaneous GPU power",0,1000),
        @"averagePower":metric(average.gpuMW/1000.0,a,@"W",@"NVIDIA RM · average GPU power",0,1000),
        @"memoryTemperature":metric(memTemp.fixedCelsius/256.0,mt,@"°C",@"NVIDIA RM · memory temperature",-20,130),
        @"memoryFrequency":metric(clocks.domains[1].actualKHz/1000.0,c,@"MHz",@"NVIDIA RM · actual memory clock (not effective data rate)",0,30000),
        @"utilization":metric(util.gpuBusy,u,@"%",@"NVIDIA RM · GPU busy",0,100),
        @"memoryBusy":metric(util.memoryBusy,u,@"%",@"NVIDIA RM · memory controller busy (not allocated VRAM)",0,100),
        @"memoryUsed":metric(m?(memory.total-memory.free)/gib:0,m,@"GiB",@"NVIDIA RM · PMA allocated memory / allocatable pool, excluding reserved VRAM",0,1024),
        @"memoryTotal":metric(memory.total/gib,m,@"GiB",@"NVIDIA RM · PMA allocatable pool, excluding reserved VRAM",0,1024)
    } mutableCopy];
    gpu[@"pstate"]=s?@{@"available":@YES,@"value":@(__builtin_ctz(state.mask)),@"source":@"NVIDIA RM · P-state"}:@{@"available":@NO};
    gpu[@"sampleTimestampsNS"]=@{@"temperature":@(temp.timestamp),@"clocks":@(clocks.timestamp),@"power":@(power.timestamp)};
    return gpu;
}
NSDictionary *ROGRMSensors(void) {
    io_service_t service=IOServiceGetMatchingService(kIOMainPortDefault,IOServiceMatching("NVRM"));
    if(!service)return @{@"status":@"未找到 NVIDIA RM 驱动。"};
    NSString *version=CFBridgingRelease(IORegistryEntryCreateCFProperty(service,CFSTR("nvrm-kext-version"),kCFAllocatorDefault,0));
    NSString *publisher=CFBridgingRelease(IORegistryEntryCreateCFProperty(service,CFSTR("CFBundleIdentifier"),kCFAllocatorDefault,0));
    // RUSD has no negotiated layout version. Enable only the tested 2.4.3 /
    // NVIDIA 610.57.04 pairing; a different driver needs its ABI checked first.
    if(![version isEqual:@"2.4.3"]||![publisher isEqual:@"com.nullmoth.NVRM"]){IOObjectRelease(service);return @{@"status":@"当前 RM 驱动版本尚未核对遥测布局。"};}
    RM rm={0,nil};io_connect_t mapping=0;uint32_t root=0;mach_vm_address_t address=0;mach_vm_size_t length=0;
    NSDictionary *gpu=nil;NSString *name=nil;
    do {
        kern_return_t kr=IOServiceOpen(service,mach_task_self(),0,&rm.ctl);
        if(kr){rm.error=[NSString stringWithFormat:@"无法打开 RM：0x%08x",kr];break;}
        ROGRMRootParams rp={.client=0xcba00001,.pid=getpid()};strlcpy(rp.name,"ROG Control telemetry",sizeof rp.name);
        root=allocate(&rm,0,0,rp.client,0x41,&rp,sizeof rp);if(!root)break;
        uint32_t ids[32];memset(ids,0xff,sizeof ids);
        if(!control(&rm,root,root,0x201,ids,sizeof ids))break;
        uint32_t id=UINT32_MAX;for(unsigned i=0;i<32;i++)if(ids[i]!=UINT32_MAX){id=ids[i];break;}
        if(id==UINT32_MAX){rm.error=@"RM 没有已连接的 GPU。";break;}
        ROGRMIdInfo info={.gpuId=id};if(!control(&rm,root,root,0x205,&info,sizeof info))break;
        ROGRMDeviceParams dp={.device=info.device};
        uint32_t device=allocate(&rm,root,root,0xcba00002,0x80,&dp,sizeof dp);if(!device)break;
        uint32_t sub=allocate(&rm,root,device,0xcba00003,0x2080,&info.subdevice,sizeof info.subdevice);if(!sub)break;
        struct { uint32_t flags; char name[64]; } np={0};
        if(!control(&rm,root,sub,0x20800110,&np,sizeof np))break;
        name=[[NSString alloc]initWithBytes:np.name length:strnlen(np.name,sizeof np.name) encoding:NSASCIIStringEncoding];
        // These bits request sensor polling only, not performance policies.
        uint64_t mask=0x1f;uint32_t shared=allocate(&rm,root,sub,0xcba00004,0xde,&mask,sizeof mask);if(!shared)break;
        kr=IOServiceOpen(service,mach_task_self(),0,&mapping);if(kr){rm.error=@"无法打开 RM 共享数据映射连接。";break;}
        uint64_t fd=0;uint32_t count=1;kr=IOConnectCallScalarMethod(mapping,2,NULL,0,&fd,&count);
        if(kr||count!=1||fd>INT32_MAX){rm.error=@"RM 映射描述符不可用。";break;}
        ROGRMMap map={.client=root,.device=sub,.memory=shared,.length=ROGRUSDSize,.status=UINT32_MAX,.flags=1,.fd=(int32_t)fd};
        if(!escape(&rm,0x4e,&map,sizeof map))break;
        if(map.status){rm.error=[NSString stringWithFormat:@"RM 共享数据映射失败：0x%x",map.status];break;}
        kr=IOConnectMapMemory64(mapping,0,mach_task_self(),&address,&length,kIOMapAnywhere|kIOMapReadOnly);
        if(kr||length<ROGRUSDSize){rm.error=@"RM 共享数据大小或映射无效。";break;}
        gpu=decode((const volatile void*)(uintptr_t)address,(size_t)length);
        // At startup/after idle, observe an actual update before displaying live
        // values. Retry for at most 0.5 s; later snapshots use the observations.
        for(unsigned retry=0;retry<5;retry++) {
            BOOL warming=NO;for(unsigned i=0;i<7;i++)if(progress[i].timestamp&&!progress[i].confirmed)warming=YES;
            if(!warming)break;usleep(100000);
            gpu=decode((const volatile void*)(uintptr_t)address,(size_t)length);
        }
    }while(0);
    if(address)IOConnectUnmapMemory64(mapping,0,mach_task_self(),address);
    if(mapping)IOServiceClose(mapping);
    // Root owns only our private device/subdevice/shared-data objects. Freeing
    // it stops our sensor-poll vote. Never free another client's GPU resources.
    if(root){ROGRMFree f={root,0,root,UINT32_MAX};escape(&rm,0x29,&f,sizeof f);}
    if(rm.ctl)IOServiceClose(rm.ctl);IOObjectRelease(service);
    return gpu?@{@"GPU":gpu,@"name":name?:@"NVIDIA GPU",@"driverVersion":version,@"status":@"NVIDIA RM 共享遥测；无有效读数的项目显示为不可用。"}:@{@"status":rm.error?:@"RM 遥测不可用。"};
}
