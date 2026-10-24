#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonDigest.h>
#import "Bridge.h"
#import "Sensors.h"
#import "TuningController.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <sys/stat.h>

static NSString *const HelperPath=@"/Library/PrivilegedHelperTools/com.macdriver.ROGControlHelper";
static NSString *modeName(NSInteger mode) {return mode==2?@"安静":mode==0?@"性能":mode==1?@"Turbo":mode==4?@"自定义":@"未知";}
static void updateText(NSTextField *field,NSString *text) {
    if(![field.stringValue isEqualToString:text?:@""])field.stringValue=text?:@"";
}
static void updateColor(NSTextField *field,NSColor *color) {
    if(![field.textColor isEqual:color])field.textColor=color;
}
static void updateTooltip(NSView *view,NSString *value) {if(![view.toolTip isEqual:value])view.toolTip=value;}
static void enable(NSControl *control,BOOL value) {if(control.enabled!=value)control.enabled=value;}
static void title(NSButton *button,NSString *value) {if(![button.title isEqual:value])button.title=value;}
static NSTextField *label(NSString *text,CGFloat size,BOOL bold) {
    NSTextField *v=[NSTextField labelWithString:text];v.font=bold?[NSFont systemFontOfSize:size weight:NSFontWeightSemibold]:[NSFont systemFontOfSize:size];return v;
}
static NSStackView *stack(NSArray<NSView*>*views,NSUserInterfaceLayoutOrientation orientation,CGFloat spacing) {
    NSStackView *s=[NSStackView stackViewWithViews:views];s.orientation=orientation;s.spacing=spacing;s.alignment=orientation==NSUserInterfaceLayoutOrientationVertical?NSLayoutAttributeLeading:NSLayoutAttributeCenterY;return s;
}
static NSView *card(NSView *content) {
    NSBox *box=[NSBox new];box.boxType=NSBoxCustom;box.borderWidth=1;box.cornerRadius=14;
    box.fillColor=NSColor.controlBackgroundColor;box.borderColor=[NSColor.separatorColor colorWithAlphaComponent:0.3];box.titlePosition=NSNoTitle;
    [box addSubview:content];content.translatesAutoresizingMaskIntoConstraints=NO;
    [NSLayoutConstraint activateConstraints:@[[content.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:18],[content.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-18],[content.topAnchor constraintEqualToAnchor:box.topAnchor constant:17],[content.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-17]]];return box;
}
static NSString *fileHash(NSString *path) {
    NSData *data=[NSData dataWithContentsOfFile:path];if(!data||data.length>UINT32_MAX)return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *hash=[NSMutableString string];for(unsigned i=0;i<sizeof(digest);i++)[hash appendFormat:@"%02x",digest[i]];return hash;
}
static NSDictionary *request(NSString *path,NSDictionary *command) {
    int fd=socket(AF_UNIX,SOCK_STREAM,0);if(fd<0)return @{@"error":@"无法建立授权连接。"};
    struct timeval timeout={8,0};int yes=1;setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof(timeout));setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    struct sockaddr_un address={0};address.sun_family=AF_UNIX;
    if(strlen(path.fileSystemRepresentation)>=sizeof(address.sun_path)){close(fd);return @{@"error":@"连接路径无效。"};}
    strlcpy(address.sun_path,path.fileSystemRepresentation,sizeof(address.sun_path));
    if(connect(fd,(struct sockaddr*)&address,sizeof(address))){close(fd);return @{@"error":@"授权会话已结束，请重新授权。"};}
    NSData *json=[NSJSONSerialization dataWithJSONObject:command options:0 error:NULL];NSMutableData *wire=[json mutableCopy];[wire appendBytes:"\n" length:1];
    const char *bytes=wire.bytes;size_t left=wire.length;
    while(left){ssize_t n=write(fd,bytes,left);if(n<=0){close(fd);return @{@"error":@"发送失败。"};}bytes+=n;left-=(size_t)n;}
    NSMutableData *reply=[NSMutableData data];BOOL complete=NO;
    while(reply.length<65536){char buffer[1024];ssize_t n=read(fd,buffer,sizeof(buffer));if(n<=0)break;char *end=memchr(buffer,'\n',(size_t)n);[reply appendBytes:buffer length:end?(NSUInteger)(end-buffer):(NSUInteger)n];if(end){complete=YES;break;}}
    close(fd);id value=complete?[NSJSONSerialization JSONObjectWithData:reply options:0 error:NULL]:nil;
    return [value isKindOfClass:NSDictionary.class]?value:@{@"error":@"读取超时或响应无效，请重新授权。"};
}

@interface ROGDocument:NSView
@end
@implementation ROGDocument
- (BOOL)isFlipped{return YES;}
@end

@interface ROGApp:NSObject<NSApplicationDelegate>
@property NSWindow *window;
@property NSTextField *supply,*message,*current;
@property NSArray<NSTextField*> *fanValues;
@property NSMutableDictionary<NSString*,NSTextField*> *sensorValues;
@property NSView *document;
@property NSStackView *rootView;
@property NSSegmentedControl *modes;
@property NSButton *authorizeButton,*applyButton,*refreshButton,*automatic;
@property NSProgressIndicator *progress;
@property NSTimer *timer;
@property NSString *socketPath;
@property BOOL connected,busy,onAC,hasPending,backgroundRead,progressOn,reconnectSuppressed;
@property NSDictionary *deferredCommand;
@property NSInteger actualMode;
@property ROGTuningController *tuningController;
@property NSDictionary *lastResponse;
@property NSSegmentedControl *sections;
@property NSTabView *pages;
@end
@implementation ROGApp
- (void)buildInterface {
    self.actualMode=-1;
    self.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,740,740) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    self.window.title=@"ROG Control for macOS";self.window.backgroundColor=NSColor.windowBackgroundColor;self.window.releasedWhenClosed=NO;self.window.minSize=NSMakeSize(720,560);
    NSTextField *title=label(@"ROG Control",28,YES),*subtitle=label(@"macOS 性能与硬件控制",13,NO);subtitle.textColor=NSColor.secondaryLabelColor;
    NSStackView *heading=stack(@[title,subtitle],NSUserInterfaceLayoutOrientationVertical,5);
    self.authorizeButton=[NSButton buttonWithTitle:@"授权控制…" target:self action:@selector(authorize:)];self.authorizeButton.bezelStyle=NSBezelStyleRounded;
    NSStackView *right=stack(@[self.authorizeButton],NSUserInterfaceLayoutOrientationHorizontal,12);
    self.sections=[NSSegmentedControl segmentedControlWithLabels:@[@"监控",@"调校"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(selectSection:)];self.sections.selectedSegment=0;
    for(NSInteger i=0;i<2;i++)[self.sections setWidth:72 forSegment:i];
    NSStackView *header=stack(@[heading,[NSView new],self.sections,right],NSUserInterfaceLayoutOrientationHorizontal,16);
    self.current=label(@"当前模式 —",17,YES);self.supply=label(@"等待读取",12,NO);updateColor(self.supply,NSColor.secondaryLabelColor);
    NSStackView *modeTitle=stack(@[self.current,[NSView new],self.supply],NSUserInterfaceLayoutOrientationHorizontal,16);
    self.modes=[NSSegmentedControl segmentedControlWithLabels:@[@"安静",@"性能",@"Turbo"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(selectMode:)];self.modes.segmentStyle=NSSegmentStyleRounded;self.modes.selectedSegment=-1;
    for(NSInteger i=0;i<3;i++)[self.modes setWidth:130 forSegment:i];
    self.applyButton=[NSButton buttonWithTitle:@"应用档位" target:self action:@selector(apply:)];self.applyButton.bezelStyle=NSBezelStyleRounded;
    NSStackView *selector=stack(@[self.modes,[NSView new],self.applyButton],NSUserInterfaceLayoutOrientationHorizontal,14);
    NSStackView *modeContent=stack(@[modeTitle,selector],NSUserInterfaceLayoutOrientationVertical,14);
    [modeTitle.widthAnchor constraintEqualToAnchor:modeContent.widthAnchor].active=YES;[selector.widthAnchor constraintEqualToAnchor:modeContent.widthAnchor].active=YES;
    NSView *modeCard=card(modeContent);
    NSMutableArray *fanCards=[NSMutableArray array],*values=[NSMutableArray array];
    NSArray *names=@[@"CPU 风扇",@"GPU 风扇",@"第三风扇"];
    for(NSString *name in names){
        NSTextField *nameLabel=label(name,12,YES);nameLabel.textColor=NSColor.secondaryLabelColor;
        NSTextField *value=label(@"—",32,YES);value.font=[NSFont monospacedDigitSystemFontOfSize:32 weight:NSFontWeightMedium];[values addObject:value];
        NSTextField *unit=label(@"RPM",11,NO);unit.textColor=NSColor.tertiaryLabelColor;
        [fanCards addObject:card(stack(@[nameLabel,value,unit],NSUserInterfaceLayoutOrientationVertical,9))];
    }
    self.fanValues=values;NSStackView *fans=stack(fanCards,NSUserInterfaceLayoutOrientationHorizontal,12);fans.distribution=NSStackViewDistributionFillEqually;
    self.sensorValues=[NSMutableDictionary dictionary];NSMutableArray *sensorCards=[NSMutableArray array];
    for(NSString *device in @[@"CPU",@"GPU"]){
        NSMutableArray *columns=[NSMutableArray array];
        NSArray *keys=@[@"temperature",@"frequency",@"power"],*titles=[device isEqual:@"CPU"]?@[@"温度",@"平均频率",@"封装功耗"]:@[@"温度",@"频率",@"功耗"];
        for(NSUInteger i=0;i<keys.count;i++){
            NSTextField *caption=label(titles[i],11,NO);caption.textColor=NSColor.secondaryLabelColor;
            NSTextField *number=label(@"不可用",22,YES);number.font=[NSFont monospacedDigitSystemFontOfSize:22 weight:NSFontWeightMedium];
            self.sensorValues[[NSString stringWithFormat:@"%@.%@",device,keys[i]]]=number;
            [columns addObject:stack(@[caption,number],NSUserInterfaceLayoutOrientationVertical,6)];
        }
        NSStackView *row=stack(columns,NSUserInterfaceLayoutOrientationHorizontal,16);row.distribution=NSStackViewDistributionFillEqually;
        NSStackView *body=stack(@[label(device,14,YES),row],NSUserInterfaceLayoutOrientationVertical,12);
        [row.widthAnchor constraintEqualToAnchor:body.widthAnchor].active=YES;[sensorCards addObject:card(body)];
    }
    self.refreshButton=[NSButton buttonWithTitle:@"刷新读数" target:self action:@selector(refresh:)];self.refreshButton.bezelStyle=NSBezelStyleRounded;
    self.automatic=[NSButton checkboxWithTitle:@"每秒刷新" target:self action:@selector(automaticChanged:)];self.automatic.state=NSControlStateValueOn;
    self.progress=[NSProgressIndicator new];self.progress.style=NSProgressIndicatorStyleSpinning;self.progress.controlSize=NSControlSizeSmall;self.progress.displayedWhenStopped=NO;
    NSStackView *tools=stack(@[self.refreshButton,self.automatic,[NSView new],self.progress],NSUserInterfaceLayoutOrientationHorizontal,14);
    self.message=label(@"",12,NO);self.message.lineBreakMode=NSLineBreakByWordWrapping;self.message.maximumNumberOfLines=2;self.message.hidden=YES;updateColor(self.message,NSColor.secondaryLabelColor);
    NSStackView *sensorRow=stack(sensorCards,NSUserInterfaceLayoutOrientationHorizontal,12);sensorRow.distribution=NSStackViewDistributionFillEqually;
    NSMutableArray *gpuColumns=[NSMutableArray array];
    NSArray *gpuKeys=@[@"memoryUsed",@"memoryTemperature",@"memoryFrequency",@"utilization"],*gpuTitles=@[@"显存分配",@"显存温度",@"显存时钟",@"GPU 利用率"];
    for(NSUInteger i=0;i<gpuKeys.count;i++){
        NSTextField *caption=label(gpuTitles[i],11,NO);caption.textColor=NSColor.secondaryLabelColor;
        NSTextField *number=label(@"不可用",17,YES);number.font=[NSFont monospacedDigitSystemFontOfSize:17 weight:NSFontWeightMedium];
        self.sensorValues[[NSString stringWithFormat:@"GPU.%@",gpuKeys[i]]]=number;
        [gpuColumns addObject:stack(@[caption,number],NSUserInterfaceLayoutOrientationVertical,6)];
    }
    NSStackView *gpuRow=stack(gpuColumns,NSUserInterfaceLayoutOrientationHorizontal,12);gpuRow.distribution=NSStackViewDistributionFillEqually;
    NSStackView *gpuBody=stack(@[label(@"显存与负载",14,YES),gpuRow],NSUserInterfaceLayoutOrientationVertical,12);
    [gpuRow.widthAnchor constraintEqualToAnchor:gpuBody.widthAnchor].active=YES;NSView *gpuCard=card(gpuBody);
    NSStackView *root=stack(@[modeCard,fans,sensorRow,gpuCard],NSUserInterfaceLayoutOrientationVertical,14);self.rootView=root;
    NSScrollView *scroll=[NSScrollView new];scroll.hasVerticalScroller=YES;scroll.autohidesScrollers=YES;scroll.drawsBackground=NO;
    NSView *content=self.window.contentView;
    self.document=[[ROGDocument alloc]initWithFrame:NSMakeRect(0,0,740,740)];self.document.translatesAutoresizingMaskIntoConstraints=NO;scroll.documentView=self.document;
    [NSLayoutConstraint activateConstraints:@[[self.document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],[self.document.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],[self.document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor]]];
    [self.document addSubview:root];root.translatesAutoresizingMaskIntoConstraints=NO;
    [NSLayoutConstraint activateConstraints:@[[root.leadingAnchor constraintEqualToAnchor:self.document.leadingAnchor constant:24],[root.trailingAnchor constraintEqualToAnchor:self.document.trailingAnchor constant:-24],[root.topAnchor constraintEqualToAnchor:self.document.topAnchor constant:24],[root.bottomAnchor constraintEqualToAnchor:self.document.bottomAnchor constant:-24]]];
    for(NSView *v in @[modeCard,fans,sensorRow,gpuCard])[v.widthAnchor constraintEqualToAnchor:root.widthAnchor].active=YES;
    self.tuningController=[ROGTuningController new];__weak ROGApp *weakSelf=self;
    self.tuningController.submit=^(NSDictionary *command){[weakSelf perform:command];};
    self.pages=[NSTabView new];self.pages.tabViewType=NSNoTabsNoBorder;
    NSTabViewItem *monitor=[[NSTabViewItem alloc]initWithIdentifier:@"monitor"];monitor.view=scroll;[self.pages addTabViewItem:monitor];
    NSTabViewItem *tuning=[[NSTabViewItem alloc]initWithIdentifier:@"tuning"];tuning.view=self.tuningController.view;[self.pages addTabViewItem:tuning];
    NSStackView *footer=stack(@[tools,self.message],NSUserInterfaceLayoutOrientationVertical,8);
    [tools.widthAnchor constraintEqualToAnchor:footer.widthAnchor].active=YES;[self.message.widthAnchor constraintEqualToAnchor:footer.widthAnchor].active=YES;
    for(NSView *v in @[header,self.pages,footer]){[content addSubview:v];v.translatesAutoresizingMaskIntoConstraints=NO;}
    [NSLayoutConstraint activateConstraints:@[[header.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],[header.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],[header.topAnchor constraintEqualToAnchor:content.topAnchor constant:24],
        [footer.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:24],[footer.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-24],[footer.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-20],
        [self.pages.leadingAnchor constraintEqualToAnchor:content.leadingAnchor],[self.pages.trailingAnchor constraintEqualToAnchor:content.trailingAnchor],[self.pages.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:4],[self.pages.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-12]]];
}
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    (void)note;[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSMenu *menu=[NSMenu new];NSMenuItem *appItem=[NSMenuItem new];[menu addItem:appItem];NSMenu *appMenu=[NSMenu new];
    [appMenu addItemWithTitle:@"退出 ROG Control" action:@selector(terminate:) keyEquivalent:@"q"];appItem.submenu=appMenu;NSApp.mainMenu=menu;
    [self buildInterface];[self.window center];[self.window makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
    [self prepareSession];[self render:ROGRead(@"status",nil) live:NO];[self updateControls];
    self.timer=[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {(void)app;return YES;}
- (void)applicationWillTerminate:(NSNotification *)note {(void)note;[self.timer invalidate];}
- (void)updateControls {
    BOOL interactiveBusy=self.busy&&!self.backgroundRead;
    enable(self.authorizeButton,!interactiveBusy&&!self.connected);title(self.authorizeButton,self.connected?@"已连接":@"授权一次…");
    if(self.authorizeButton.hidden!=self.connected)self.authorizeButton.hidden=self.connected;
    enable(self.refreshButton,self.connected&&!interactiveBusy);enable(self.automatic,self.connected);
    enable(self.modes,self.connected&&!interactiveBusy&&self.onAC&&self.actualMode>=0);
    NSInteger segment=self.modes.selectedSegment;NSInteger wanted=segment==0?2:segment==1?0:segment==2?1:-1;
    enable(self.applyButton,self.modes.enabled&&wanted>=0&&wanted!=self.actualMode);
    if(interactiveBusy!=self.progressOn){self.progressOn=interactiveBusy;if(interactiveBusy)[self.progress startAnimation:nil];else[self.progress stopAnimation:nil];}
    [self.tuningController setConnected:self.connected busy:interactiveBusy onAC:self.onAC bridgeVersion:self.lastResponse[@"BridgeVersion"]];
}
- (void)render:(NSDictionary *)response live:(BOOL)live {
    self.lastResponse=response;
    NSDictionary *snapshot=response[@"Snapshot"],*fields=snapshot[@"FirmwareFields"];
    BOOL compatible=[response[@"BridgeVersion"] isEqual:@"1.3.0"]||[response[@"BridgeVersion"] isEqual:@"1.4.0"]||[response[@"BridgeVersion"] isEqual:@"1.5.0"];
    BOOL valid=compatible&&[snapshot[@"ModelVerified"] boolValue]&&[snapshot[@"EC0Found"] boolValue]&&[snapshot[@"IOReturn"] unsignedIntValue]==0&&[fields[@"FANM"][@"IOReturn"] unsignedIntValue]==0&&[fields[@"FANM"][@"Value"] isKindOfClass:NSNumber.class];
    self.actualMode=valid?[fields[@"FANM"][@"Value"] integerValue]:-1;
    if(self.actualMode<0||(self.actualMode>2&&self.actualMode!=4))self.actualMode=-1;
    self.onAC=valid&&[fields[@"ACIN"][@"IOReturn"] unsignedIntValue]==0&&[fields[@"ACIN"][@"Value"] integerValue]==1;
    updateText(self.current,[NSString stringWithFormat:@"当前模式  %@",modeName(self.actualMode)]);updateText(self.supply,valid?(self.onAC?@"已接通电源":@"电池供电"):@"状态未确认");
    if(!self.hasPending){NSInteger selection=self.actualMode==2?0:self.actualMode==0?1:self.actualMode==1?2:-1;if(self.modes.selectedSegment!=selection)self.modes.selectedSegment=selection;}
    NSArray *keys=@[@"CPU",@"GPU",@"Mid"];
    for(NSUInteger i=0;i<3;i++){
        NSDictionary *fan=snapshot[@"Fans"][keys[i]];id rpm=fan[@"RawRPM"];
        BOOL good=valid&&[fan[@"Valid"] boolValue]&&[fan[@"IOReturn"] unsignedIntValue]==0&&[rpm isKindOfClass:NSNumber.class]&&[rpm integerValue]>=0&&[rpm integerValue]<=12000;
        updateText(self.fanValues[i],good?[rpm stringValue]:@"—");
    }
    if(response[@"error"]){updateText(self.message,response[@"error"]);updateColor(self.message,NSColor.systemOrangeColor);self.message.hidden=NO;}
    else self.message.hidden=YES;
    NSDictionary *sensors=response[@"Sensors"];
    for(NSString *device in @[@"CPU",@"GPU"])for(NSString *key in @[@"temperature",@"frequency",@"power",@"memoryUsed",@"memoryTemperature",@"memoryFrequency",@"utilization"]){
        NSDictionary *metric=sensors[device][key];NSTextField *field=self.sensorValues[[NSString stringWithFormat:@"%@.%@",device,key]];
        BOOL available=[metric[@"available"] boolValue]&&[metric[@"value"] isKindOfClass:NSNumber.class];
        if(available){double value=[metric[@"value"] doubleValue];NSString *unit=metric[@"unit"];if(([key isEqual:@"frequency"]||[key isEqual:@"memoryFrequency"])&&value>=1000){value/=1000;unit=@"GHz";}
            NSString *text=[NSString stringWithFormat:@"%.1f %@",value,unit];
            if([key isEqual:@"memoryUsed"]){NSDictionary *total=sensors[device][@"memoryTotal"];if([total[@"available"] boolValue])text=[NSString stringWithFormat:@"%.1f / %.1f GiB",value,[total[@"value"] doubleValue]];}
            updateText(field,text);updateColor(field,NSColor.labelColor);updateTooltip(field,metric[@"source"]);}
        else{updateText(field,@"不可用");updateColor(field,NSColor.tertiaryLabelColor);updateTooltip(field,[device isEqual:@"GPU"]?sensors[@"GPUStatus"]:@"当前传感器没有提供有效读数。");}
    }
    if(!live&&!self.connected){
        for(NSTextField *field in self.fanValues)updateText(field,@"—");
        for(NSTextField *field in self.sensorValues.allValues)updateText(field,@"待刷新");
        updateText(self.current,[NSString stringWithFormat:@"上次模式  %@",modeName(self.actualMode)]);
    }
    [self.tuningController renderResponse:response];[self updateControls];
}
- (void)selectSection:(id)sender {
    (void)sender;NSInteger index=self.sections.selectedSegment;
    if(index<0||index>1)return;
    [self.window makeFirstResponder:nil];[self.pages selectTabViewItemAtIndex:index];
}
- (void)selectMode:(id)sender {(void)sender;self.hasPending=YES;[self updateControls];}
- (void)automaticChanged:(id)sender {(void)sender;if(self.automatic.state==NSControlStateValueOn)[self refresh:nil];}
- (void)tick:(NSTimer *)timer {
    (void)timer;
    if(!self.connected&&!self.busy&&!self.reconnectSuppressed&&[NSFileManager.defaultManager fileExistsAtPath:self.socketPath]&&[fileHash(HelperPath) isEqual:NSBundle.mainBundle.infoDictionary[@"ROGHelperSHA256"]]){
        self.connected=YES;self.message.hidden=YES;[self updateControls];[self refresh:nil];
    }
    else if(self.connected&&self.window.visible&&!self.window.miniaturized&&self.automatic.state==NSControlStateValueOn)[self perform:@{@"command":@"refresh"} background:YES];
}
- (void)refresh:(id)sender {(void)sender;if(!self.connected)return;[self perform:@{@"command":@"refresh"}];}
- (void)apply:(id)sender {
    (void)sender;if(!self.applyButton.enabled)return;
    NSInteger index=self.modes.selectedSegment;[self perform:@{@"command":@"mode",@"mode":@(index==0?2:index==1?0:1)}];
}
- (void)perform:(NSDictionary *)command {[self perform:command background:NO];}
- (void)perform:(NSDictionary *)command background:(BOOL)background {
    if(self.busy){
        if(!background&&self.backgroundRead){self.deferredCommand=command;self.backgroundRead=NO;[self updateControls];}
        return;
    }
    self.busy=YES;self.backgroundRead=background;if(!background)[self updateControls];NSString *path=self.socketPath;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSDictionary *response=request(path,command);
        dispatch_async(dispatch_get_main_queue(),^{
            NSDictionary *deferred=self.deferredCommand;self.deferredCommand=nil;
            self.busy=NO;self.backgroundRead=NO;
            BOOL switched=[command[@"command"] isEqual:@"mode"]&&response[@"CommandIOReturn"]&&[response[@"CommandIOReturn"] unsignedIntValue]==0&&[response[@"ModeMatched"] boolValue]&&[response[@"Snapshot"][@"FirmwareFields"][@"FANM"][@"Value"] isEqual:command[@"mode"]];
            BOOL tuned=([command[@"command"] isEqual:@"tuningApply"]||[command[@"command"] isEqual:@"tuningRestore"])&&response[@"CommandIOReturn"]&&[response[@"CommandIOReturn"] unsignedIntValue]==0;
            if(switched||tuned)self.hasPending=NO;
            [self render:response live:YES];
            if(switched){updateText(self.message,[NSString stringWithFormat:@"已读回确认：%@ 档。风扇会随温度逐步调整。",modeName([command[@"mode"] integerValue])]);updateColor(self.message,NSColor.secondaryLabelColor);}
            else if([command[@"command"] isEqual:@"mode"]&&!response[@"error"]){updateText(self.message,@"未能确认切换，请刷新后重试。");updateColor(self.message,NSColor.systemOrangeColor);}
            if(!response[@"CommandIOReturn"]){self.connected=NO;self.reconnectSuppressed=YES;[self updateControls];}
            if(deferred&&self.connected)[self perform:deferred background:NO];
        });
    });
}
- (void)authorize:(id)sender {
    (void)sender;if(self.busy||self.connected)return;
    NSString *app=NSBundle.mainBundle.bundlePath;
    NSString *installer=[app stringByAppendingPathComponent:@"Contents/Resources/ROGControlHelper"];
    NSString *(^quote)(NSString*)=^NSString*(NSString *v){return [NSString stringWithFormat:@"'%@'",[v stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];};
    NSString *command=[NSString stringWithFormat:@"%@ --install %u %@",quote(installer),getuid(),quote(app)];
    NSString *escaped=[[command stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"] stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    NSString *script=[NSString stringWithFormat:@"do shell script \"%@\" with administrator privileges",escaped];
    self.busy=YES;self.message.hidden=NO;updateText(self.message,@"等待系统授权…");[self updateControls];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSTask *task=[NSTask new];task.executableURL=[NSURL fileURLWithPath:@"/usr/bin/osascript"];task.arguments=@[@"-e",script];NSPipe *pipe=NSPipe.pipe;task.standardOutput=pipe;task.standardError=pipe;
        BOOL launched=[task launchAndReturnError:NULL];if(launched)[task waitUntilExit];BOOL success=launched&&task.terminationStatus==0;
        dispatch_async(dispatch_get_main_queue(),^{self.busy=NO;self.reconnectSuppressed=!success;self.message.hidden=success;updateText(self.message,success?@"":@"未完成安装，可以重试授权。");[self updateControls];[self tick:nil];});
    });
}
- (void)prepareSession {
    self.socketPath=[NSString stringWithFormat:@"/var/run/rogctrl-%u.sock",getuid()];
}
@end
int main(int argc,const char **argv) { @autoreleasepool {
    if(argc==2&&(!strcmp(argv[1],"--read-sensors")||!strcmp(argv[1],"--sample-sensors"))){
        BOOL refresh=!strcmp(argv[1],"--sample-sensors");
        if(refresh&&geteuid()!=0){fprintf(stderr,"Sensor sampling requires administrator privileges.\n");return 2;}
        NSData *data=[NSJSONSerialization dataWithJSONObject:ROGHardwareSensors(refresh) options:NSJSONWritingPrettyPrinted error:NULL];fwrite(data.bytes,1,data.length,stdout);fputc('\n',stdout);return 0;
    }
    if(argc==2&&!strcmp(argv[1],"--test-requests")){
        NSArray *bad=@[@{@"command":@"mode",@"mode":@(-1)},@{@"command":@"mode",@"mode":@3},@{@"command":@"mode",@"mode":@YES},@{@"command":@"mode",@"mode":@1.5},@{@"command":@"mode",@"mode":@"1"},@{@"command":@"refresh",@"extra":@1},@{@"command":@"shell"},@[]];
        for(id r in bad)if(ROGValidRequest(r))return 1;
        for(int mode=0;mode<=2;mode++)if(!ROGValidRequest(@{@"command":@"mode",@"mode":@(mode)}))return 1;
        if(!ROGValidRequest(@{@"command":@"refresh"})||!ROGValidRequest(@{@"command":@"status"}))return 1;
        puts("PASS: bridge rejects arbitrary commands, extra keys, bool/string/fraction/out-of-range modes; accepts only supported requests.");return 0;
    }
    NSApplication *app=NSApplication.sharedApplication;static ROGApp *delegate;delegate=[ROGApp new];app.delegate=delegate;[app run];return 0;
} }
