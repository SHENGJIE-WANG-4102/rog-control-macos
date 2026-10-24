#import "Bridge.h"
#import <Security/Security.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <libproc.h>
#include <pwd.h>
#include <poll.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>

static NSString *const Service=@"com.macdriver.ROGControlHelper";
static NSString *const Installed=@"/Library/PrivilegedHelperTools/com.macdriver.ROGControlHelper";
static NSString *const Config=@"/Library/Application Support/ROGControl/Client.plist";
static NSString *const LaunchPlist=@"/Library/LaunchDaemons/com.macdriver.ROGControlHelper.plist";
static NSString *hex(NSData *data) {NSMutableString *s=[NSMutableString string];const uint8_t *b=data.bytes;for(NSUInteger i=0;i<data.length;i++)[s appendFormat:@"%02x",b[i]];return s;}
static NSString *staticHash(NSString *path) {
    SecStaticCodeRef code=NULL;CFDictionaryRef info=NULL;NSString *hash=nil;
    if(SecStaticCodeCreateWithPath((__bridge CFURLRef)[NSURL fileURLWithPath:path],kSecCSDefaultFlags,&code)==errSecSuccess&&SecStaticCodeCheckValidity(code,kSecCSStrictValidate,NULL)==errSecSuccess&&SecCodeCopySigningInformation((SecCodeRef)code,kSecCSSigningInformation,&info)==errSecSuccess)
        hash=hex((__bridge NSData*)CFDictionaryGetValue(info,kSecCodeInfoUnique));
    if(info)CFRelease(info);if(code)CFRelease(code);return hash;
}
static BOOL approved(pid_t pid,uid_t uid,NSString *hash) {
    struct proc_bsdinfo proc={0};if(proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&proc,sizeof(proc))!=sizeof(proc)||proc.pbi_uid!=uid)return NO;
    SecCodeRef code=NULL;CFDictionaryRef info=NULL;BOOL valid=NO;
    NSDictionary *attributes=@{(__bridge NSString*)kSecGuestAttributePid:@(pid)};
    if(SecCodeCopyGuestWithAttributes(NULL,(__bridge CFDictionaryRef)attributes,kSecCSDefaultFlags,&code)==errSecSuccess&&SecCodeCheckValidity(code,kSecCSStrictValidate,NULL)==errSecSuccess&&SecCodeCopySigningInformation(code,kSecCSSigningInformation,&info)==errSecSuccess)
        valid=[hex((__bridge NSData*)CFDictionaryGetValue(info,kSecCodeInfoUnique)) isEqual:hash];
    if(info)CFRelease(info);if(code)CFRelease(code);return valid;
}
static int run(NSArray<NSString*> *arguments) {
    NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@"/bin/launchctl"];task.arguments=arguments;
    task.standardOutput=NSFileHandle.fileHandleWithNullDevice;task.standardError=NSFileHandle.fileHandleWithNullDevice;
    if(![task launchAndReturnError:NULL])return -1;[task waitUntilExit];return task.terminationStatus;
}
static BOOL ensureDirectory(NSString *path) {
    NSFileManager *fm=NSFileManager.defaultManager;
    if(![fm fileExistsAtPath:path]&&![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:NULL])return NO;
    struct stat st={0};return lstat(path.fileSystemRepresentation,&st)==0&&S_ISDIR(st.st_mode)&&st.st_uid==0&&!(st.st_mode&0022);
}
static int install(uid_t uid,NSString *app) {
    if(uid==0||!getpwuid(uid))return 2;
    NSString *client=[app stringByAppendingPathComponent:@"Contents/MacOS/ROGControl"];
    NSString *source=[app stringByAppendingPathComponent:@"Contents/Resources/ROGControlHelper"];
    NSString *hash=staticHash(client);
    if(hash.length!=40||!staticHash(source))return 2;
    if(!ensureDirectory(@"/Library/PrivilegedHelperTools")||!ensureDirectory(@"/Library/Application Support/ROGControl")||!ensureDirectory(@"/Library/LaunchDaemons"))return 3;
    NSData *binary=[NSData dataWithContentsOfFile:source];if(!binary||binary.length>4*1024*1024)return 3;
    NSString *stage=[Installed stringByAppendingString:@".new"];
    // Trusted root directory; reject unexpected symbolic links before replacement.
    struct stat st={0};if(lstat(stage.fileSystemRepresentation,&st)==0)return 3;
    int fd=open(stage.fileSystemRepresentation,O_CREAT|O_EXCL|O_WRONLY|O_NOFOLLOW,0755);if(fd<0)return 3;
    const uint8_t *bytes=binary.bytes;size_t remaining=binary.length;BOOL good=YES;
    while(remaining){ssize_t n=write(fd,bytes,remaining);if(n<=0){good=NO;break;}bytes+=n;remaining-=(size_t)n;}
    if(fsync(fd)||fchown(fd,0,0)||fchmod(fd,0755))good=NO;close(fd);
    if(!good||!staticHash(stage)){unlink(stage.fileSystemRepresentation);return 3;}
    NSDictionary *config=@{@"uid":@(uid),@"clientCDHash":hash};
    NSDictionary *plist=@{@"Label":Service,@"ProgramArguments":@[Installed,@"--daemon"],@"RunAtLoad":@YES,@"KeepAlive":@YES,@"ThrottleInterval":@10,@"ProcessType":@"Background",@"StandardErrorPath":@"/var/log/rog-control-macos.log"};
    NSData *configData=[NSPropertyListSerialization dataWithPropertyList:config format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    NSData *plistData=[NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    if(!configData||!plistData){unlink(stage.fileSystemRepresentation);return 3;}
    // Stop only this project's existing service. No driver or boot cache changes.
    run(@[@"bootout",@"system",LaunchPlist]);
    if(rename(stage.fileSystemRepresentation,Installed.fileSystemRepresentation))return 3;
    if(![configData writeToFile:Config options:NSDataWritingAtomic error:NULL]||![plistData writeToFile:LaunchPlist options:NSDataWritingAtomic error:NULL])return 3;
    chown(Config.fileSystemRepresentation,0,0);chmod(Config.fileSystemRepresentation,0644);chown(LaunchPlist.fileSystemRepresentation,0,0);chmod(LaunchPlist.fileSystemRepresentation,0644);
    int result=run(@[@"bootstrap",@"system",LaunchPlist]);
    if(!result)printf("Installed persistent control component. No firmware requests issued.\n");
    return result;
}
static void reply(int fd,NSDictionary *value) {
    NSData *data=[NSJSONSerialization dataWithJSONObject:value options:0 error:NULL];NSMutableData *wire=[data mutableCopy];[wire appendBytes:"\n" length:1];
    const char *bytes=wire.bytes;size_t left=wire.length;while(left){ssize_t n=write(fd,bytes,left);if(n<=0)break;bytes+=n;left-=(size_t)n;}
}
static int serve(void) {
    struct stat policy={0};if(lstat(Config.fileSystemRepresentation,&policy)||!S_ISREG(policy.st_mode)||policy.st_uid!=0||(policy.st_mode&0022))return 2;
    NSDictionary *config=[NSDictionary dictionaryWithContentsOfURL:[NSURL fileURLWithPath:Config] error:NULL];
    id value=config[@"uid"];NSString *hash=config[@"clientCDHash"];
    if(![value isKindOfClass:NSNumber.class]||[value unsignedLongLongValue]==0||[value unsignedLongLongValue]>UINT32_MAX||![hash isKindOfClass:NSString.class]||hash.length!=40)return 2;
    uid_t uid=[value unsignedIntValue];struct passwd *user=getpwuid(uid);if(!user)return 2;
    NSString *path=[NSString stringWithFormat:@"/var/run/rogctrl-%u.sock",uid];struct sockaddr_un address={0};address.sun_family=AF_UNIX;
    strlcpy(address.sun_path,path.fileSystemRepresentation,sizeof(address.sun_path));
    // /var/run is root-owned. Remove only a socket at our fixed service path.
    struct stat old={0};if(lstat(address.sun_path,&old)==0){if(!S_ISSOCK(old.st_mode))return 3;unlink(address.sun_path);}
    umask(0077);int server=socket(AF_UNIX,SOCK_STREAM,0);if(server<0)return 3;
    if(bind(server,(struct sockaddr*)&address,sizeof(address))||chown(address.sun_path,uid,user->pw_gid)||chmod(address.sun_path,0600)||listen(server,4)){close(server);return 3;}
    signal(SIGPIPE,SIG_IGN);
    // Idle boot path: no driver matching, SMC sampling or firmware access until
    // an approved GUI sends a request. No automatic performance-mode changes.
    for(;;){@autoreleasepool{
        struct pollfd p={server,POLLIN,0};int ready=poll(&p,1,1000);if(ready<0&&errno==EINTR)continue;if(ready<=0)continue;
        int client=accept(server,NULL,NULL);if(client<0)continue;
        uid_t peerUid=0;gid_t peerGid=0;pid_t peerPid=0;socklen_t length=sizeof(peerPid);
        if(getpeereid(client,&peerUid,&peerGid)||peerUid!=uid||getsockopt(client,SOL_LOCAL,LOCAL_PEERPID,&peerPid,&length)||!approved(peerPid,uid,hash)){close(client);continue;}
        struct timeval timeout={2,0};setsockopt(client,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));setsockopt(client,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));
        NSMutableData *wire=[NSMutableData data];BOOL complete=NO;
        for(unsigned i=0;i<4096;i++){char byte;ssize_t n=read(client,&byte,1);if(n!=1)break;if(byte=='\n'){complete=YES;break;}[wire appendBytes:&byte length:1];}
        id request=complete?[NSJSONSerialization JSONObjectWithData:wire options:NSJSONReadingFragmentsAllowed error:NULL]:nil;
        if(!ROGValidRequest(request)||[request[@"command"] isEqual:@"quit"])reply(client,@{@"error":@"不支持的请求。",@"CommandIOReturn":@1});
        else reply(client,ROGReadRequest(request));
        close(client);
    }}
}
int main(int argc,const char **argv){@autoreleasepool{
    if(geteuid()!=0)return 2;
    if(argc==2&&!strcmp(argv[1],"--daemon"))return serve();
    if(argc==4&&!strcmp(argv[1],"--install")){
        char *end=NULL;errno=0;unsigned long uid=strtoul(argv[2],&end,10);
        if(errno||!argv[2][0]||*end||uid==0||uid>UINT32_MAX)return 2;
        return install((uid_t)uid,[NSString stringWithUTF8String:argv[3]]);
    }
    if(argc==2&&!strcmp(argv[1],"--uninstall")){
        run(@[@"bootout",@"system",LaunchPlist]);unlink(LaunchPlist.fileSystemRepresentation);unlink(Config.fileSystemRepresentation);unlink(Installed.fileSystemRepresentation);puts("Removed control component. Driver and selected firmware mode left unchanged.");return 0;
    }
    return 2;
}}
