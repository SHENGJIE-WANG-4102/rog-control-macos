#import "Bridge.h"
#include <unistd.h>
int main(int argc,const char **argv){@autoreleasepool{
    NSDictionary *request=nil;
    if(argc==2&&!strcmp(argv[1],"--read"))request=@{@"command":@"tuningRead"};
    else if(argc==2&&!strcmp(argv[1],"--restore"))request=@{@"command":@"tuningRestore"};
    else if(argc==3&&!strcmp(argv[1],"--apply")){
        NSFileHandle *file=[NSFileHandle fileHandleForReadingAtPath:[NSString stringWithUTF8String:argv[2]]];NSData *data=[file readDataOfLength:4097];[file closeFile];
        if(!data||data.length>4096){fprintf(stderr,"Invalid or oversized JSON request.\n");return 2;}
        id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        if(!ROGValidRequest(value)||![value[@"command"] isEqual:@"tuningApply"]){fprintf(stderr,"Invalid tuning request; PL1/PL2 must be <=175W.\n");return 2;}request=value;
    }
    if(!request){fprintf(stderr,"Usage: tuning-client --read | --restore | --apply request.json\n");return 2;}
    if(geteuid()!=0){fprintf(stderr,"Administrator privileges required.\n");return 2;}
    NSDictionary *result=ROGReadRequest(request);NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:NULL];
    if(!data)return 1;fwrite(data.bytes,1,data.length,stdout);putchar('\n');return [result[@"CommandIOReturn"] unsignedIntValue]?1:0;
}return 0;}
