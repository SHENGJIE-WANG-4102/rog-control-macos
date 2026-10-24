#import "TuningController.h"
#import "Bridge.h"
#import "TuningPreset.h"
#import "TuningCurveView.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include "../Shared/TuningLimits.h"
#include "../Shared/CurvePolicy.h"
#include <math.h>

static NSTextField *text(NSString *s,CGFloat size,BOOL bold){NSTextField *v=[NSTextField labelWithString:s];v.font=bold?[NSFont systemFontOfSize:size weight:NSFontWeightSemibold]:[NSFont systemFontOfSize:size];return v;}
static NSStackView *row(NSArray *v,NSUserInterfaceLayoutOrientation o,CGFloat gap){NSStackView *s=[NSStackView stackViewWithViews:v];s.orientation=o;s.spacing=gap;s.alignment=o==NSUserInterfaceLayoutOrientationVertical?NSLayoutAttributeLeading:NSLayoutAttributeCenterY;return s;}
static NSNumber *number(NSString *s,NSUInteger maximum){if(!s.length||s.length>3||[s rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location!=NSNotFound)return nil;NSUInteger n=s.integerValue;return n<=maximum?@(n):nil;}
static void setText(NSTextField *f,NSString *s){if(![f.stringValue isEqual:s])f.stringValue=s;}
static void message(NSTextField *f,NSString *s){setText(f,s);if(f.hidden!=!s.length)f.hidden=!s.length;}
static void enabled(NSControl *v,BOOL value){if(v.enabled!=value)v.enabled=value;}

@interface ROGTuningDocument : NSView
@end
@implementation ROGTuningDocument
- (BOOL)isFlipped{return YES;}
@end

@interface ROGTuningController () <NSTextFieldDelegate>
@property NSMutableArray<NSMutableArray<NSNumber*>*> *curves;
@property NSArray<NSArray<NSNumber*>*> *quietCurves;
@property NSArray<NSTextField*> *temperatures,*percentages;
@property NSSegmentedControl *fans;
@property NSTextField *status,*readback,*pl1,*pl2,*validation;
@property ROGTuningCurveView *preview;
@property NSSlider *pl1Slider,*pl2Slider;
@property NSButton *loadButton,*applyButton,*restoreButton,*importButton,*exportButton;
@property BOOL loaded,connected,interactiveBusy,onAC,ready,restorePossible;
@property NSInteger fan;
@property NSString *bridge;
- (NSDictionary *)draftRequest:(NSString **)problem;
- (void)importRequest:(NSDictionary *)request;
@end
@implementation ROGTuningController
- (instancetype)init {
    if(!(self=[super initWithNibName:nil bundle:nil]))return nil;
    self.view=[[NSView alloc]initWithFrame:NSMakeRect(0,0,760,580)];
    self.loadButton=[NSButton buttonWithTitle:@"读取原厂曲线" target:self action:@selector(load:)];
    self.restoreButton=[NSButton buttonWithTitle:@"恢复原厂策略" target:self action:@selector(restore:)];
    self.applyButton=[NSButton buttonWithTitle:@"应用曲线与功耗" target:self action:@selector(apply:)];
    self.importButton=[NSButton buttonWithTitle:@"载入方案…" target:self action:@selector(importPreset:)];
    self.exportButton=[NSButton buttonWithTitle:@"保存方案…" target:self action:@selector(exportPreset:)];
    for(NSButton *b in @[self.loadButton,self.restoreButton,self.applyButton,self.importButton,self.exportButton])b.bezelStyle=NSBezelStyleRounded;
    self.fans=[NSSegmentedControl segmentedControlWithLabels:@[@"CPU",@"GPU",@"第三风扇"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(selectFan:)];self.fans.selectedSegment=0;self.fan=0;
    NSMutableArray *cells=[NSMutableArray arrayWithObject:@[text(@"点",12,YES),text(@"温度 °C",12,YES),text(@"百分比 %",12,YES)]];
    NSMutableArray *temps=[NSMutableArray array],*speeds=[NSMutableArray array];
    for(unsigned i=0;i<8;i++){
        NSTextField *t=[NSTextField textFieldWithString:@""],*p=[NSTextField textFieldWithString:@""];t.alignment=p.alignment=NSTextAlignmentRight;
        t.delegate=p.delegate=self;
        [t.widthAnchor constraintEqualToConstant:64].active=YES;[p.widthAnchor constraintEqualToConstant:64].active=YES;
        [temps addObject:t];[speeds addObject:p];[cells addObject:@[text([NSString stringWithFormat:@"%u",i+1],12,NO),t,p]];
    }
    self.temperatures=temps;self.percentages=speeds;NSGridView *grid=[NSGridView gridViewWithViews:cells];grid.rowSpacing=8;grid.columnSpacing=20;
    self.preview=[[ROGTuningCurveView alloc]initWithFrame:NSZeroRect];
    __weak ROGTuningController *weakSelf=self;
    self.preview.changed=^(NSArray<NSNumber *> *curve){
        ROGTuningController *owner=weakSelf;if(!owner)return;
        owner.curves[owner.fan]=[curve mutableCopy];[owner showFan];
    };
    [self.preview.widthAnchor constraintEqualToConstant:320].active=YES;[self.preview.heightAnchor constraintEqualToConstant:190].active=YES;
    NSStackView *left=row(@[text(@"八点风扇曲线",16,YES),self.fans,grid],NSUserInterfaceLayoutOrientationVertical,14);
    self.pl1=[NSTextField textFieldWithString:@"80"];self.pl2=[NSTextField textFieldWithString:@"100"];
    self.pl1.delegate=self;self.pl2.delegate=self;
    self.pl1Slider=[NSSlider sliderWithValue:80 minValue:ROG_MIN_POWER_W maxValue:ROG_MAX_POWER_W target:self action:@selector(slide:)];
    self.pl2Slider=[NSSlider sliderWithValue:100 minValue:ROG_MIN_POWER_W maxValue:ROG_MAX_POWER_W target:self action:@selector(slide:)];self.pl1Slider.tag=1;self.pl2Slider.tag=2;
    for(NSTextField *f in @[self.pl1,self.pl2]){f.alignment=NSTextAlignmentRight;[f.widthAnchor constraintEqualToConstant:60].active=YES;}
    for(NSSlider *s in @[self.pl1Slider,self.pl2Slider])[s.widthAnchor constraintEqualToConstant:230].active=YES;
    self.readback=text(@"",12,NO);self.readback.hidden=YES;self.readback.maximumNumberOfLines=2;self.readback.lineBreakMode=NSLineBreakByWordWrapping;
    NSTextField *limit=text(@"5–175 W · PL1 ≤ PL2",11,NO);limit.textColor=NSColor.secondaryLabelColor;
    NSStackView *right=row(@[self.preview,text(@"CPU 功耗目标",16,YES),row(@[text(@"PL1 · 持续",12,YES),self.pl1,text(@"W",12,NO)],NSUserInterfaceLayoutOrientationHorizontal,8),self.pl1Slider,row(@[text(@"PL2 · 短时",12,YES),self.pl2,text(@"W",12,NO)],NSUserInterfaceLayoutOrientationHorizontal,8),self.pl2Slider,limit,self.readback],NSUserInterfaceLayoutOrientationVertical,12);
    [self.readback.widthAnchor constraintEqualToConstant:270].active=YES;
    NSStackView *body=row(@[left,[NSView new],right],NSUserInterfaceLayoutOrientationHorizontal,22);body.alignment=NSLayoutAttributeTop;
    self.status=text(@"",12,NO);self.status.hidden=YES;self.status.lineBreakMode=NSLineBreakByWordWrapping;self.status.maximumNumberOfLines=2;self.status.textColor=NSColor.secondaryLabelColor;
    self.validation=text(@"",12,NO);self.validation.hidden=YES;self.validation.lineBreakMode=NSLineBreakByWordWrapping;self.validation.maximumNumberOfLines=2;
    NSStackView *presets=row(@[self.loadButton,self.importButton,self.exportButton],NSUserInterfaceLayoutOrientationHorizontal,10);
    NSStackView *buttons=row(@[[NSView new],self.restoreButton,self.applyButton],NSUserInterfaceLayoutOrientationHorizontal,10);
    NSStackView *root=row(@[presets,body,self.validation,buttons,self.status],NSUserInterfaceLayoutOrientationVertical,16);
    NSScrollView *scroll=[NSScrollView new];scroll.hasVerticalScroller=YES;scroll.autohidesScrollers=YES;scroll.drawsBackground=NO;
    [self.view addSubview:scroll];scroll.translatesAutoresizingMaskIntoConstraints=NO;
    [NSLayoutConstraint activateConstraints:@[[scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]]];
    NSView *document=[[ROGTuningDocument alloc]initWithFrame:NSMakeRect(0,0,760,580)];document.translatesAutoresizingMaskIntoConstraints=NO;scroll.documentView=document;
    [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor].active=YES;
    [document.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor].active=YES;[document.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor].active=YES;
    [document addSubview:root];root.translatesAutoresizingMaskIntoConstraints=NO;
    [NSLayoutConstraint activateConstraints:@[[root.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:24],[root.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-24],[root.topAnchor constraintEqualToAnchor:document.topAnchor constant:24],[root.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-24]]];
    for(NSView *v in @[body,presets,self.validation,buttons,self.status])[v.widthAnchor constraintEqualToAnchor:root.widthAnchor].active=YES;
    [self updateControls];return self;
}
- (void)setConnected:(BOOL)connected busy:(BOOL)busy onAC:(BOOL)onAC bridgeVersion:(NSString *)version {
    BOOL newlySupported=![self.bridge isEqual:@"1.5.0"]&&[version isEqual:@"1.5.0"];
    self.connected=connected;self.interactiveBusy=busy;self.onAC=onAC;self.bridge=version;
    if(newlySupported&&!self.loaded)message(self.status,@"");
    [self updateControls];
}
- (void)updateControls {
    BOOL supported=[self.bridge isEqual:@"1.5.0"],usable=self.connected&&!self.interactiveBusy&&self.onAC&&supported;
    NSString *problem=nil;NSDictionary *draft=[self draftRequest:&problem];
    enabled(self.loadButton,usable);enabled(self.applyButton,usable&&self.loaded&&self.ready&&draft!=nil);enabled(self.restoreButton,usable&&self.restorePossible);
    enabled(self.importButton,usable&&self.loaded);enabled(self.exportButton,self.loaded&&!self.interactiveBusy&&draft!=nil);
    message(self.validation,self.loaded?(problem?:@""):@"");
    NSColor *validationColor=problem?NSColor.systemOrangeColor:NSColor.secondaryLabelColor;
    if(![self.validation.textColor isEqual:validationColor])self.validation.textColor=validationColor;
    enabled(self.fans,usable&&self.loaded);
    self.preview.editable=usable&&self.loaded;
    for(NSControl *v in [self.temperatures arrayByAddingObjectsFromArray:self.percentages])enabled(v,usable&&self.loaded);
    for(NSControl *v in @[self.pl1,self.pl2,self.pl1Slider,self.pl2Slider])enabled(v,usable&&self.loaded);
    if(self.bridge&&!supported)message(self.status,@"需要桥接驱动 1.5.0。");
    [self updatePreview];
}
- (NSDictionary *)draftRequest:(NSString **)problem {
    if(!self.loaded||self.curves.count!=3)return nil;
    NSMutableArray *curves=[NSMutableArray array];for(NSArray *c in self.curves)[curves addObject:[c mutableCopy]];
    NSArray *names=@[@"CPU",@"GPU",@"第三风扇"];
    for(unsigned i=0;i<8;i++){
        NSNumber *t=number(self.temperatures[i].stringValue,100),*p=number(self.percentages[i].stringValue,100);
        if(!t||!p||t.intValue<20){if(problem)*problem=[NSString stringWithFormat:@"%@：第 %u 点温度须为 20–100°C，风速须为 0–100%% 的整数。",names[self.fan],i+1];return nil;}
        curves[self.fan][i]=t;curves[self.fan][i+8]=p;
    }
    for(unsigned fan=0;fan<3;fan++){
        NSArray *c=curves[fan];
        for(unsigned i=1;i<8;i++){
            if([c[i] intValue]<=[c[i-1] intValue]){if(problem)*problem=[NSString stringWithFormat:@"%@：第 %u 点温度须高于前一点。",names[fan],i+1];return nil;}
            if([c[i+8] intValue]<[c[i+7] intValue]){if(problem)*problem=[NSString stringWithFormat:@"%@：第 %u 点风速不能低于前一点。",names[fan],i+1];return nil;}
        }
        if(self.quietCurves.count!=3){if(problem)*problem=@"尚未读取安静预设。";return nil;}
        uint8_t values[16],quiet[16];for(unsigned i=0;i<16;i++){values[i]=[c[i] unsignedIntValue];quiet[i]=[self.quietCurves[fan][i] unsignedIntValue];}
        if(!ROGCurveAboveQuiet(values,quiet)){if(problem)*problem=[NSString stringWithFormat:@"%@：曲线不能低于安静预设。",names[fan]];return nil;}
    }
    NSNumber *pl1=number(self.pl1.stringValue,ROG_MAX_POWER_W),*pl2=number(self.pl2.stringValue,ROG_MAX_POWER_W);
    if(!pl1||!pl2||pl1.intValue<ROG_MIN_POWER_W||pl2.intValue<ROG_MIN_POWER_W||pl1.intValue>pl2.intValue){if(problem)*problem=@"功耗须满足 5 ≤ PL1 ≤ PL2 ≤ 175W。";return nil;}
    NSDictionary *request=@{@"command":@"tuningApply",@"curves":curves,@"pl1":pl1,@"pl2":pl2};
    return ROGValidRequest(request)?request:nil;
}
- (void)updatePreview {
    NSMutableArray *curve=self.loaded?[self.curves[self.fan] mutableCopy]:nil;
    for(unsigned i=0;curve&&i<8;i++){
        NSNumber *t=number(self.temperatures[i].stringValue,100),*p=number(self.percentages[i].stringValue,100);
        if(!t||!p){curve=nil;break;}curve[i]=t;curve[i+8]=p;
    }
    self.preview.curve=curve;
    self.preview.minimumCurve=self.loaded&&self.quietCurves.count==3?self.quietCurves[self.fan]:nil;
}
- (BOOL)saveVisible {
    if(!self.loaded)return NO;
    NSMutableArray *curve=[self.curves[self.fan] mutableCopy];
    for(unsigned i=0;i<8;i++){
        NSNumber *t=number(self.temperatures[i].stringValue,100),*p=number(self.percentages[i].stringValue,100);
        if(!t||!p){message(self.status,@"温度和百分比须为 0–100 的整数。");return NO;}
        curve[i]=t;curve[i+8]=p;
    }self.curves[self.fan]=curve;return YES;
}
- (void)showFan {
    if(!self.loaded)return;
    for(unsigned i=0;i<8;i++){setText(self.temperatures[i],[self.curves[self.fan][i] stringValue]);setText(self.percentages[i],[self.curves[self.fan][i+8] stringValue]);}
    [self updateControls];
}
- (void)selectFan:(id)sender {(void)sender;if(![self saveVisible]){self.fans.selectedSegment=self.fan;return;}self.fan=self.fans.selectedSegment;[self showFan];}
- (void)slide:(NSSlider *)slider {NSInteger w=lround(slider.doubleValue);slider.integerValue=w;setText(slider.tag==1?self.pl1:self.pl2,[NSString stringWithFormat:@"%ld",(long)w]);[self updateControls];}
- (void)controlTextDidChange:(NSNotification *)note {
    NSTextField *field=note.object;NSNumber *w=number(field.stringValue,ROG_MAX_POWER_W);
    if(w&&w.integerValue>=ROG_MIN_POWER_W){if(field==self.pl1)self.pl1Slider.integerValue=w.integerValue;else if(field==self.pl2)self.pl2Slider.integerValue=w.integerValue;}
    [self updateControls];
}
- (void)controlTextDidEndEditing:(NSNotification *)note {
    if(!self.loaded||!self.preview.editable)return;
    NSUInteger index=[self.temperatures indexOfObjectIdenticalTo:note.object];
    if(index==NSNotFound)index=[self.percentages indexOfObjectIdenticalTo:note.object];
    if(index==NSNotFound)return;
    NSNumber *t=number(self.temperatures[index].stringValue,100),*p=number(self.percentages[index].stringValue,100);
    if(!t||!p)return;
    NSRect plot=NSMakeRect(36,24,self.preview.bounds.size.width-53,self.preview.bounds.size.height-36);
    [self.preview movePointAtIndex:(NSInteger)index toLocation:NSMakePoint(plot.origin.x+plot.size.width*(t.doubleValue-20)/80,plot.origin.y+plot.size.height*p.doubleValue/100)];
}
- (void)load:(id)sender {(void)sender;if(!self.loadButton.enabled)return;message(self.status,@"读取中…");if(self.submit)self.submit(@{@"command":@"tuningRead"});}
- (void)restore:(id)sender {(void)sender;if(!self.restoreButton.enabled)return;if(self.submit)self.submit(@{@"command":@"tuningRestore"});}
- (void)apply:(id)sender {
    (void)sender;if(!self.applyButton.enabled)return;
    NSString *problem=nil;NSDictionary *request=[self draftRequest:&problem];
    if(!request){message(self.status,problem?:@"请修正方案内容。");[self updateControls];return;}
    if(![self saveVisible])return;
    if(self.submit)self.submit(request);
}
- (void)importRequest:(NSDictionary *)request {
    self.curves=[NSMutableArray array];for(NSArray *c in request[@"curves"])[self.curves addObject:[c mutableCopy]];
    self.pl1Slider.integerValue=[request[@"pl1"] integerValue];self.pl2Slider.integerValue=[request[@"pl2"] integerValue];
    setText(self.pl1,[request[@"pl1"] stringValue]);setText(self.pl2,[request[@"pl2"] stringValue]);[self showFan];
    message(self.status,@"方案已载入，尚未应用。");
}
- (void)importPreset:(id)sender {
    (void)sender;if(!self.importButton.enabled)return;
    NSOpenPanel *panel=[NSOpenPanel openPanel];panel.allowedContentTypes=@[UTTypeJSON];panel.allowsMultipleSelection=NO;panel.canChooseDirectories=NO;panel.title=@"载入调校方案";
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result){
        if(result!=NSModalResponseOK)return;
        NSError *error=nil;NSNumber *size=nil;
        if(![panel.URL getResourceValue:&size forKey:NSURLFileSizeKey error:&error]||size.unsignedLongLongValue>4096){message(self.status,error.localizedDescription?:@"方案文件超过 4 KB。");return;}
        NSData *data=[NSData dataWithContentsOfURL:panel.URL options:0 error:&error];NSDictionary *request=data?ROGDecodeTuningPreset(data,&error):nil;
        if(!request){message(self.status,error.localizedDescription?:@"无法读取方案。");return;}
        if(!self.importButton.enabled){message(self.status,@"连接或电源状态已变化，请重新载入。");return;}
        [self importRequest:request];
    }];
}
- (void)exportPreset:(id)sender {
    (void)sender;if(!self.exportButton.enabled)return;
    NSError *error=nil;NSData *data=ROGEncodeTuningPreset([self draftRequest:nil],&error);
    if(!data){message(self.status,error.localizedDescription?:@"请修正方案内容。");return;}
    NSSavePanel *panel=[NSSavePanel savePanel];panel.allowedContentTypes=@[UTTypeJSON];panel.nameFieldStringValue=@"G815LW-tuning.json";panel.title=@"保存调校方案";
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result){
        if(result!=NSModalResponseOK)return;
        NSError *writeError=nil;if(![data writeToURL:panel.URL options:NSDataWritingAtomic error:&writeError])message(self.status,writeError.localizedDescription?:@"无法保存方案。");
        else message(self.status,@"方案已保存。");
    }];
}
- (void)renderResponse:(NSDictionary *)response {
    NSDictionary *t=response[@"Tuning"];NSString *command=response[@"command"];
    if(t){self.ready=[t[@"Ready"] boolValue];self.restorePossible=self.ready||[t[@"Active"] boolValue]||[t[@"RestoreAttempted"] boolValue];
        if([t[@"PowerReadback"] boolValue])message(self.readback,[NSString stringWithFormat:@"目标回读：PL1 %@W ／ PL2 %@W",t[@"PL1"],t[@"PL2"]]);
        else message(self.readback,@"");}
    if([command isEqual:@"tuningRead"]&&!response[@"error"]&&[response[@"CommandIOReturn"] isKindOfClass:NSNumber.class]&&[response[@"CommandIOReturn"] unsignedIntValue]==0&&self.ready){
        id curves=t[@"FactoryCurves"],quiet=t[@"QuietCurves"];BOOL valid=[curves isKindOfClass:NSArray.class]&&[curves count]==3&&[quiet isKindOfClass:NSArray.class]&&[quiet count]==3;
        if(valid)for(id c in [curves arrayByAddingObjectsFromArray:quiet]){
            if(![c isKindOfClass:NSArray.class]||[c count]!=16){valid=NO;break;}
            for(id n in c)if(![n isKindOfClass:NSNumber.class]||CFGetTypeID((__bridge CFTypeRef)n)==CFBooleanGetTypeID()||!isfinite([n doubleValue])||[n doubleValue]!=floor([n doubleValue])||[n doubleValue]<0||[n doubleValue]>100){valid=NO;break;}
        }
        if(valid)for(NSArray *c in quiet){uint8_t bytes[16];for(unsigned i=0;i<16;i++)bytes[i]=[c[i] unsignedIntValue];if(!ROGCurveOrdered(bytes,0))valid=NO;}
        if(valid){self.quietCurves=quiet;self.curves=[NSMutableArray array];for(NSArray *c in curves)[self.curves addObject:[c mutableCopy]];self.loaded=YES;[self showFan];
            unsigned a=[t[@"PL1"] unsignedIntValue],b=[t[@"PL2"] unsignedIntValue];if(a<5||b<a||b>175){a=80;b=100;}
            self.pl1Slider.integerValue=a;self.pl2Slider.integerValue=b;setText(self.pl1,[NSString stringWithFormat:@"%u",a]);setText(self.pl2,[NSString stringWithFormat:@"%u",b]);
            message(self.status,@"");}
        else {self.ready=NO;message(self.status,@"原厂曲线数据无效，请重新读取。");}
    }else if([command hasPrefix:@"tuning"]){
        if(response[@"error"]){NSString *recovery=[t[@"RestoreAttempted"] boolValue]?([t[@"RestoreConfirmed"] boolValue]?@" 已恢复原厂。":@" 恢复未确认。"):@"";message(self.status,[NSString stringWithFormat:@"%@%@",response[@"error"],recovery]);}
        else if([command isEqual:@"tuningApply"]&&[t[@"PowerReadback"] boolValue]&&[t[@"CurveAcknowledged"] boolValue])message(self.status,@"曲线已响应，功耗目标已确认。");
        else if([command isEqual:@"tuningRestore"]&&[t[@"RestoreConfirmed"] boolValue])message(self.status,@"已恢复原厂。");
    }
    [self updateControls];
}
@end
