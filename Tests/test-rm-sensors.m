#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import "RMRUSD.h"
#include <assert.h>
#include <unistd.h>

static uint8_t page[4096] __attribute__((aligned(4096)));
static unsigned opens,closes,frees,maps,unmaps,calls,failAt;
static BOOL wrongVersion,shortMap,freezePower;
static int sampleSleep(useconds_t us){
    assert(us==100000);
    size_t offsets[]={ROGRUSDTemperature,ROGRUSDMemoryTemperature,ROGRUSDClocks,ROGRUSDInstantPower,ROGRUSDAveragePower,ROGRUSDUtil,ROGRUSDPState};
    for(unsigned i=0;i<7;i++){uint64_t *t=(uint64_t*)(page+offsets[i]);if(freezePower&&offsets[i]==ROGRUSDInstantPower)continue;if(*t&&*t<ROGRUSDSequenceStart)*t+=100000000;}
    return 0;
}
static CFMutableDictionaryRef match(const char *name){assert(!strcmp(name,"NVRM"));return CFDictionaryCreateMutable(NULL,0,NULL,NULL);}
static io_service_t matchingService(mach_port_t p,CFDictionaryRef d){(void)p;CFRelease(d);return 1;}
static CFTypeRef property(io_registry_entry_t s,CFStringRef key,CFAllocatorRef a,IOOptionBits o){
    (void)s;(void)a;(void)o;NSString *k=(__bridge NSString*)key;
    return CFBridgingRetain([k isEqual:@"nvrm-kext-version"]?(wrongVersion?@"other":@"2.4.3"):@"com.nullmoth.NVRM");
}
static kern_return_t releaseObject(io_object_t o){(void)o;return 0;}
static kern_return_t openService(io_service_t s,task_port_t t,uint32_t type,io_connect_t *c){(void)s;(void)t;assert(type==0);*c=10+opens++;return 0;}
static kern_return_t closeService(io_connect_t c){assert(c==10||c==11);closes++;return 0;}
static kern_return_t call(io_connect_t c,uint32_t selector,const uint64_t *scalar,uint32_t count,const void *in,size_t size,uint64_t *out,uint32_t *outCount,void *result,size_t *resultSize){
    (void)out;(void)outCount;assert(c==10&&selector==1&&count==1&&in==result&&size==*resultSize);
    if(*scalar==0x29){ROGRMFree *p=result;assert(p->root==0xcba00001&&p->parent==0&&p->object==p->root);p->status=0;frees++;return 0;}
    if(++calls==failAt)return kIOReturnError;
    switch(*scalar){
        case 0x2b:{ROGRMAlloc *p=result;assert(size==32);assert(p->cls==0x41||p->cls==0x80||p->cls==0x2080||p->cls==0xde);
            if(p->cls==0xde)assert(*(uint64_t*)(uintptr_t)p->params==0x1f);p->status=0;break;}
        case 0x2a:{ROGRMControl *p=result;assert(size==32);void *params=(void*)(uintptr_t)p->params;
            switch(p->cmd){case 0x201:memset(params,0xff,p->size);*(uint32_t*)params=0x200;break;
                case 0x205:assert(p->size==32);break;
                case 0x20800110:assert(p->size==68);strcpy((char*)params+4,"NVIDIA test GPU");break;
                default:assert(!"unexpected or write control");}p->status=0;break;}
        case 0x4e:{ROGRMMap *p=result;assert(size==56&&p->memory==0xcba00004&&p->flags==1&&p->length==3152&&p->fd==22);p->status=0;break;}
        default:assert(!"unexpected escape");
    }return 0;
}
static kern_return_t scalarCall(io_connect_t c,uint32_t selector,const uint64_t *in,uint32_t count,uint64_t *out,uint32_t *n){assert(c==11&&selector==2&&!in&&!count&&*n==1);*out=22;return 0;}
static kern_return_t mapMemory(io_connect_t c,uint32_t type,task_port_t task,mach_vm_address_t *a,mach_vm_size_t *n,IOOptionBits options){
    (void)task;assert(c==11&&type==0&&(options&kIOMapReadOnly));*a=(uintptr_t)page;*n=shortMap?64:sizeof page;maps++;return 0;
}
static kern_return_t unmapMemory(io_connect_t c,uint32_t type,task_port_t task,mach_vm_address_t a){(void)task;assert(c==11&&type==0&&a==(uintptr_t)page);unmaps++;return 0;}
#define IOServiceMatching match
#define IOServiceGetMatchingService matchingService
#define IORegistryEntryCreateCFProperty property
#define IOObjectRelease releaseObject
#define IOServiceOpen openService
#define IOServiceClose closeService
#define IOConnectCallMethod call
#define IOConnectCallScalarMethod scalarCall
#define IOConnectMapMemory64 mapMemory
#define IOConnectUnmapMemory64 unmapMemory
#define usleep sampleSleep
#import "RMSensors.m"

static void fixture(void){
    memset(page,0,sizeof page);memset(progress,0,sizeof progress);opens=closes=frees=maps=unmaps=calls=failAt=0;wrongVersion=shortMap=freezePower=NO;
    uint64_t now=(uint64_t)(NSDate.date.timeIntervalSince1970*1e9);
    ROGRMTemperature t={now,50*256+128};memcpy(page+ROGRUSDTemperature,&t,sizeof t);memcpy(page+ROGRUSDMemoryTemperature,&t,sizeof t);
    ROGRMClocks c={.timestamp=now,.domains={{2000,1995000},{9001,9001000}}};memcpy(page+ROGRUSDClocks,&c,sizeof c);
    ROGRMPower p={now,42500,0,0};memcpy(page+ROGRUSDInstantPower,&p,sizeof p);memcpy(page+ROGRUSDAveragePower,&p,sizeof p);
    ROGRMVRAM v={ROGRUSDSequenceStart+2,16ull<<30,12ull<<30};memcpy(page+ROGRUSDMemory,&v,sizeof v);
    ROGRMUtil u={.timestamp=now,.gpuBusy=42,.memoryBusy=9};memcpy(page+ROGRUSDUtil,&u,sizeof u);
    ROGRMPState s={now,16};memcpy(page+ROGRUSDPState,&s,sizeof s);
}
int main(void){@autoreleasepool{
    fixture();NSDictionary *gpu=ROGRMSensors()[@"GPU"];
    assert([gpu[@"temperature"][@"value"] doubleValue]==50.5);
    assert([gpu[@"frequency"][@"value"] doubleValue]==1995);
    assert([gpu[@"power"][@"value"] doubleValue]==42.5);
    assert([gpu[@"memoryUsed"][@"value"] doubleValue]==4);
    assert([gpu[@"memoryTotal"][@"value"] doubleValue]==16);
    assert([gpu[@"memoryFrequency"][@"value"] doubleValue]==9001);
    assert([gpu[@"utilization"][@"value"] doubleValue]==42);
    assert([gpu[@"pstate"][@"value"] intValue]==4);
    assert(opens==2&&closes==2&&frees==1&&maps==1&&unmaps==1);
    fixture();wrongVersion=YES;assert(!ROGRMSensors()[@"GPU"]&&opens==0&&calls==0);
    for(unsigned i=1;i<=8;i++){fixture();failAt=i;assert(!ROGRMSensors()[@"GPU"]);assert(opens==closes&&frees==(i>1?1u:0u));}
    fixture();shortMap=YES;assert(!ROGRMSensors()[@"GPU"]&&maps==unmaps&&opens==closes&&frees==1);
    fixture();freezePower=YES;gpu=ROGRMSensors()[@"GPU"];
    assert(![gpu[@"power"][@"available"] boolValue]&&[gpu[@"temperature"][@"available"] boolValue]);
    fixture();*(uint64_t*)(page+ROGRUSDTemperature)=UINT64_MAX;assert(![ROGRMSensors()[@"GPU"][@"temperature"][@"available"] boolValue]);
    fixture();*(uint64_t*)(page+ROGRUSDMemory)=ROGRUSDSequenceStart+1;assert(![ROGRMSensors()[@"GPU"][@"memoryUsed"][@"available"] boolValue]);
    fixture();((ROGRMVRAM*)(page+ROGRUSDMemory))->free=UINT64_MAX;assert(![ROGRMSensors()[@"GPU"][@"memoryUsed"][@"available"] boolValue]);
    fixture();((ROGRMUtil*)(page+ROGRUSDUtil))->gpuBusy=101;assert(![ROGRMSensors()[@"GPU"][@"utilization"][@"available"] boolValue]);
    ROGRMTemperature out;assert(!ROGRMReadSection(page,sizeof page,SIZE_MAX,&out,sizeof out));
    assert(!ROGRMReadSection(page,ROGRUSDTemperature+8,ROGRUSDTemperature,&out,sizeof out));
    ROGRMProgress tracking={0};
    assert(!ROGRMObserve(&tracking,UINT64_C(1790000000000000000),100));
    assert(ROGRMObserve(&tracking,UINT64_C(1790000000000000001),200));
    assert(ROGRMObserve(&tracking,UINT64_C(1790000000000000001),UINT64_C(2000000200)));
    assert(!ROGRMObserve(&tracking,UINT64_C(1790000000000000001),UINT64_C(4000000201)));
    assert(ROGRMObserve(&tracking,UINT64_C(1790000000000000002),UINT64_C(4000000300)));
    assert(!ROGRMObserve(&tracking,UINT64_C(1790000000000000003),UINT64_C(9000000300)));
    assert(ROGRMObserve(&tracking,UINT64_C(1790000000000000004),UINT64_C(9000000400)));
    assert(!ROGRMObserve(&tracking,1,UINT64_C(9000000500)));
    assert(ROGRMObserve(&tracking,2,UINT64_C(9000000600)));
    assert(!ROGRMValidSequence(0)&&!ROGRMValidSequence(UINT64_MAX));
    puts("PASS: RM allowlisted queries, version gate, units, clock domain, P-state mask, VRAM bounds, freshness, invalid/write timestamps, range checks, mapping bounds, cleanup on all request failures");
}return 0;}
