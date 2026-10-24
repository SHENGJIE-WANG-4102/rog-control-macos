#define main ROGControlUnusedMain
#import "App.m"
#undef main
#include <assert.h>

int main(void){@autoreleasepool{
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    NSUInteger before=NSApp.windows.count;ROGApp *app=[ROGApp new];[app buildInterface];
    assert(NSApp.windows.count==before+1&&app.pages.numberOfTabViewItems==2);
    assert([app.pages indexOfTabViewItem:app.pages.selectedTabViewItem]==0);
    app.sections.selectedSegment=1;[app selectSection:nil];assert(app.tuningController.view.window==app.window&&NSApp.windows.count==before+1);
    __block unsigned submissions=0;app.tuningController.submit=^(NSDictionary *request){(void)request;submissions++;};
    NSArray *curve=@[@30,@40,@50,@60,@70,@80,@90,@100,@0,@10,@20,@30,@50,@70,@90,@100];
    NSArray *quiet=@[@20,@30,@40,@50,@60,@70,@80,@100,@0,@0,@0,@0,@0,@0,@0,@0];
    NSDictionary *t=@{@"Ready":@YES,@"Active":@NO,@"FactoryCurves":@[curve,curve,curve],@"QuietCurves":@[quiet,quiet,quiet],@"PL1":@0,@"PL2":@0};
    [app.tuningController setConnected:YES busy:NO onAC:YES bridgeVersion:@"1.5.0"];
    [app.tuningController renderResponse:@{@"command":@"tuningRead",@"CommandIOReturn":@0,@"Tuning":t}];
    NSArray *temperatures=[app.tuningController valueForKey:@"temperatures"];NSTextField *first=temperatures[0];first.stringValue=@"35";
    NSTabViewItem *tuningPage=app.pages.selectedTabViewItem;
    for(unsigned n=0;n<10;n++){app.sections.selectedSegment=0;[app selectSection:nil];app.sections.selectedSegment=1;[app selectSection:nil];}
    assert(app.pages.selectedTabViewItem==tuningPage&&app.tuningController.view.window==app.window&&[first.stringValue isEqual:@"35"]&&submissions==0&&NSApp.windows.count==before+1);
    [app.window.contentView layoutSubtreeIfNeeded];assert(app.pages.frame.size.height>300);
    [app.window setContentSize:NSMakeSize(720,560)];[app.window.contentView layoutSubtreeIfNeeded];assert(app.pages.frame.size.height>300);
    [app.window close];puts("PASS: one application window, two embedded pages, repeated tab switches preserve drafts and send no requests, minimum window layout");
}return 0;}
