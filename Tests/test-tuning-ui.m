// Offscreen AppKit unit test: submission is captured, never sent to firmware.
#import "TuningController.m"
#include <assert.h>
static void changed(ROGTuningController *c,NSTextField *field) {
    [c controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:field]];
}
int main(void){@autoreleasepool{
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSUInteger windowCount=NSApp.windows.count;
    ROGTuningController *c=[ROGTuningController new];__block NSDictionary *sent=nil;
    assert(NSApp.windows.count==windowCount); // An embeddable page never creates a window.
    NSWindow *host=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,760,580) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];host.releasedWhenClosed=NO;host.contentView=c.view;
    c.submit=^(NSDictionary *request){sent=request;};
    [c setConnected:YES busy:NO onAC:YES bridgeVersion:@"1.5.0"];
    assert(c.loadButton.enabled&&!c.applyButton.enabled);
    assert(![c.status.stringValue containsString:@"需要桥接驱动"]);
    NSArray *curve=@[@30,@40,@50,@60,@70,@80,@90,@100,@0,@10,@20,@30,@50,@70,@90,@100];
    NSArray *quiet=@[@20,@30,@40,@50,@60,@70,@80,@100,@0,@0,@0,@0,@0,@0,@0,@0];
    NSDictionary *t=@{@"Ready":@YES,@"Active":@NO,@"FactoryCurves":@[curve,curve,curve],@"QuietCurves":@[quiet,quiet,quiet],@"PL1":@0,@"PL2":@0};
    [c renderResponse:@{@"command":@"tuningRead",@"CommandIOReturn":@0,@"Tuning":t}];
    assert(c.loaded&&c.applyButton.enabled&&c.curves.count==3);
    assert(c.status.hidden&&c.validation.hidden&&c.readback.hidden);
    assert(c.importButton.enabled&&c.exportButton.enabled&&[c.preview.curve isEqual:curve]);
    [c.view layoutSubtreeIfNeeded];NSRect plot=NSMakeRect(36,24,c.preview.bounds.size.width-53,c.preview.bounds.size.height-36);
    assert([c.preview movePointAtIndex:3 toLocation:NSMakePoint(plot.origin.x+plot.size.width*((65.0-20)/80),plot.origin.y+plot.size.height*0.35)]);
    assert([c.temperatures[3].stringValue intValue]==65&&[c.percentages[3].stringValue intValue]==35&&!sent);
    c.percentages[3].stringValue=@"80";changed(c,c.percentages[3]);
    [c controlTextDidEndEditing:[NSNotification notificationWithName:NSControlTextDidEndEditingNotification object:c.percentages[3]]];
    assert([c.percentages[4].stringValue intValue]==80&&[c.percentages[5].stringValue intValue]==80&&!sent);
    [c renderResponse:@{@"command":@"tuningRead",@"CommandIOReturn":@0,@"Tuning":t}];
    c.temperatures[0].stringValue=@"35";c.pl1.stringValue=@"175";c.pl2.stringValue=@"175";
    [c controlTextDidChange:[NSNotification notificationWithName:NSControlTextDidChangeNotification object:c.pl1]];
    assert(c.pl1Slider.integerValue==175);
    [c renderResponse:@{@"command":@"refresh",@"CommandIOReturn":@0,@"Tuning":t}];
    assert([c.temperatures[0].stringValue isEqual:@"35"]&&[c.pl1.stringValue isEqual:@"175"]);
    assert([host makeFirstResponder:c.pl1]);id focus=host.firstResponder;
    [c renderResponse:@{@"command":@"refresh",@"CommandIOReturn":@0,@"Tuning":t}];assert(host.firstResponder==focus);
    [host makeFirstResponder:nil];
    [c apply:nil];assert(sent&&[sent[@"pl1"] intValue]==175&&[sent[@"curves"][0][0] intValue]==35&&ROGValidRequest(sent));
    c.fans.selectedSegment=1;[c selectFan:nil];assert(c.fan==1&&[c.temperatures[0].stringValue isEqual:@"30"]&&[c.curves[0][0] intValue]==35);
    for(NSString *bad in @[@"176",@"1.5",@"",@"-1",@"999"]){sent=nil;c.pl1.stringValue=bad;changed(c,c.pl1);[c apply:nil];assert(!sent&&!c.applyButton.enabled&&!c.exportButton.enabled);}
    c.pl1.stringValue=@"100";c.pl2.stringValue=@"80";changed(c,c.pl2);sent=nil;[c apply:nil];assert(!sent&&!c.applyButton.enabled);
    c.pl1.stringValue=@"80";c.pl2.stringValue=@"100";c.percentages[7].stringValue=@"89";changed(c,c.percentages[7]);[c apply:nil];assert(!sent&&!c.applyButton.enabled&&[c.validation.stringValue containsString:@"GPU"]);
    c.percentages[7].stringValue=@"100";changed(c,c.percentages[7]);assert(c.applyButton.enabled&&[c.preview.curve[15] intValue]==100);
    c.temperatures[1].stringValue=@"30";changed(c,c.temperatures[1]);assert(!c.applyButton.enabled&&[c.validation.stringValue containsString:@"第 2 点"]);
    c.temperatures[1].stringValue=@"40";changed(c,c.temperatures[1]);assert(c.applyButton.enabled);
    NSError *error=nil;NSDictionary *draft=[c draftRequest:nil];NSData *encoded=ROGEncodeTuningPreset(draft,&error);
    assert(encoded&&encoded.length<=4096&&!error);
    NSDictionary *decoded=ROGDecodeTuningPreset(encoded,&error);assert([draft isEqual:decoded]);
    [c importRequest:decoded];assert(!sent&&c.ready&&c.loaded&&c.applyButton.enabled&&[c.status.stringValue containsString:@"尚未应用"]);
    assert([c.preview.curve isEqual:decoded[@"curves"][c.fan]]);
    NSMutableDictionary *document=[[NSJSONSerialization JSONObjectWithData:encoded options:NSJSONReadingMutableContainers error:nil] mutableCopy];
    for(NSString *key in @[@"format",@"version",@"model",@"curves",@"pl1",@"pl2"]){
        NSMutableDictionary *bad=[document mutableCopy];[bad removeObjectForKey:key];
        assert(!ROGDecodeTuningPreset([NSJSONSerialization dataWithJSONObject:bad options:0 error:nil],&error));
    }
    for(NSDictionary *change in @[@{@"version":@YES},@{@"version":@2},@{@"model":@"G815LR"},@{@"format":@"other"},@{@"pl2":@176},@{@"pl1":@YES},@{@"pl1":@(-1)},@{@"pl2":@5},@{@"endpoint":@1},@{@"curves":@[curve,curve]}]){
        NSMutableDictionary *bad=[document mutableCopy];[bad addEntriesFromDictionary:change];
        assert(!ROGDecodeTuningPreset([NSJSONSerialization dataWithJSONObject:bad options:0 error:nil],&error));
    }
    assert(!ROGDecodeTuningPreset([NSMutableData dataWithLength:4097],&error));
    assert(!ROGDecodeTuningPreset([@"[1,2]" dataUsingEncoding:NSUTF8StringEncoding],&error));
    assert(!ROGDecodeTuningPreset([@"{bad json}" dataUsingEncoding:NSUTF8StringEncoding],&error));
    assert(!ROGEncodeTuningPreset(@{@"command":@"tuningRead"},&error));
    [c setConnected:YES busy:YES onAC:YES bridgeVersion:@"1.5.0"];[c apply:nil];assert(!sent&&!c.applyButton.enabled&&!c.importButton.enabled&&!c.exportButton.enabled);
    [c setConnected:YES busy:NO onAC:NO bridgeVersion:@"1.5.0"];assert(!c.loadButton.enabled&&!c.applyButton.enabled&&!c.restoreButton.enabled);
    [c setConnected:YES busy:NO onAC:YES bridgeVersion:@"1.3.0"];assert(!c.loadButton.enabled&&!c.applyButton.enabled);
    ROGTuningController *fresh=[ROGTuningController new];[fresh setConnected:YES busy:NO onAC:YES bridgeVersion:@"1.3.0"];
    assert([fresh.status.stringValue containsString:@"需要桥接驱动"]);
    [fresh setConnected:YES busy:NO onAC:YES bridgeVersion:@"1.5.0"];assert(fresh.loadButton.enabled&&![fresh.status.stringValue containsString:@"需要桥接驱动"]);
    ROGTuningController *malformed=[ROGTuningController new];[malformed setConnected:YES busy:NO onAC:YES bridgeVersion:@"1.5.0"];
    [malformed renderResponse:@{@"command":@"tuningRead",@"Tuning":t}];assert(!malformed.loaded&&!malformed.applyButton.enabled);
    NSMutableArray *badCurve=[curve mutableCopy];badCurve[0]=@"30";NSMutableDictionary *badTable=[t mutableCopy];badTable[@"FactoryCurves"]=@[badCurve,curve,curve];
    [malformed renderResponse:@{@"command":@"tuningRead",@"CommandIOReturn":@0,@"Tuning":badTable}];assert(!malformed.loaded&&!malformed.ready);
    // Factory endpoints below 100% are valid when the complete curve stays
    // above the temperature-interpolated quiet preset.
    NSArray *stock=@[@40,@54,@58,@62,@66,@70,@74,@80,@9,@13,@20,@28,@34,@44,@61,@75];
    NSDictionary *factory=@{@"Ready":@YES,@"Active":@NO,@"FactoryCurves":@[stock,stock,stock],@"QuietCurves":@[quiet,quiet,quiet],@"PL1":@0,@"PL2":@0};
    [c setConnected:YES busy:NO onAC:YES bridgeVersion:@"1.5.0"];
    [c renderResponse:@{@"command":@"tuningRead",@"CommandIOReturn":@0,@"Tuning":factory}];assert(c.applyButton.enabled&&[c.percentages[7].stringValue intValue]==75&&c.validation.hidden);
    [c.view layoutSubtreeIfNeeded];NSScrollView *scroll=(NSScrollView *)c.view.subviews.firstObject;
    assert(scroll.documentView.frame.size.height>0&&scroll.documentView.frame.size.width==scroll.contentView.bounds.size.width);
    NSBitmapImageRep *image=[c.view bitmapImageRepForCachingDisplayInRect:c.view.bounds];
    [c.view cacheDisplayInRect:c.view.bounds toBitmapImageRep:image];
    NSString *snapshot=[NSString stringWithUTF8String:getenv("ROG_TUNING_SNAPSHOT")?:""];
    if(snapshot.length)[[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:snapshot atomically:YES];
    [c setConnected:NO busy:NO onAC:YES bridgeVersion:@"1.5.0"];assert(!c.loadButton.enabled&&!c.applyButton.enabled);
    [host close];puts("PASS: embedded editor creates no window; drafts, validation/preview, preset roundtrip/rejection, import without submission, malformed factory responses, stock curve editing, focus/layout and connection/power guards; no firmware connection");
}return 0;}
