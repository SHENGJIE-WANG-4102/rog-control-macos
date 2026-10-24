#import "TuningCurveView.m"
#include <assert.h>
static NSPoint location(ROGTuningCurveView *v,double t,double p){NSRect r=[v plotRect];return NSMakePoint(r.origin.x+r.size.width*(t-20)/80,r.origin.y+r.size.height*p/100);}
static NSEvent *event(ROGTuningCurveView *v,NSEventType type,NSPoint p){return [NSEvent mouseEventWithType:type location:[v convertPoint:p toView:nil] modifierFlags:0 timestamp:0 windowNumber:v.window.windowNumber context:nil eventNumber:1 clickCount:1 pressure:1];}
static BOOL valid(ROGTuningCurveView *v){uint8_t c[16],q[16];for(unsigned i=0;i<16;i++){c[i]=[v.curve[i] unsignedIntValue];q[i]=[v.minimumCurve[i] unsignedIntValue];}return ROGCurveAboveQuiet(c,q);}
int main(void){@autoreleasepool{
    [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
    ROGTuningCurveView *v=[[ROGTuningCurveView alloc]initWithFrame:NSMakeRect(0,0,320,190)];
    NSWindow *host=[[NSWindow alloc]initWithContentRect:v.bounds styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];host.releasedWhenClosed=NO;host.contentView=v;
    NSArray *original=@[@30,@40,@50,@60,@70,@80,@90,@100,@0,@10,@20,@30,@50,@70,@90,@100];
    NSArray *zero=@[@20,@30,@40,@50,@60,@70,@80,@100,@0,@0,@0,@0,@0,@0,@0,@0];v.curve=original;v.minimumCurve=zero;
    __block unsigned changes=0;v.changed=^(NSArray *c){assert(c.count==16);changes++;};
    assert([v pointIndexAtLocation:location(v,50,20)]==-1);assert(![v movePointAtIndex:2 toLocation:location(v,55,25)]);
    v.editable=YES;for(NSInteger i=0;i<8;i++)assert([v pointIndexAtLocation:[v pointAtIndex:i]]==i);
    assert([v pointIndexAtLocation:location(v,100,0)]==-1);
    [v mouseDown:event(v,NSEventTypeLeftMouseDown,location(v,100,0))];[v mouseDragged:event(v,NSEventTypeLeftMouseDragged,location(v,50,50))];[v mouseUp:event(v,NSEventTypeLeftMouseUp,location(v,50,50))];assert(changes==0);
    assert([v movePointAtIndex:3 toLocation:location(v,-100,200)]);assert([v.curve[3] intValue]==51&&[v.curve[11] intValue]==100&&valid(v));
    for(unsigned i=4;i<8;i++)assert([v.curve[i+8] intValue]==100); // Raising cascades right.
    for(unsigned i=0;i<3;i++)assert([v.curve[i+8] isEqual:original[i+8]]);
    v.curve=original;assert([v movePointAtIndex:5 toLocation:location(v,80,0)]);
    for(unsigned i=0;i<=5;i++)assert([v.curve[i+8] intValue]==0);assert([v.curve[14] intValue]==90&&valid(v)); // Lowering cascades left.
    v.curve=original;assert([v movePointAtIndex:2 toLocation:location(v,53.49,23.49)]);assert([v.curve[2] intValue]==53&&[v.curve[10] intValue]==23);
    assert([v movePointAtIndex:2 toLocation:location(v,53.51,23.51)]);assert([v.curve[2] intValue]==54&&[v.curve[10] intValue]==24);
    v.curve=original;assert([v movePointAtIndex:0 toLocation:location(v,-100,-100)]);assert([v.curve[0] intValue]==20&&[v.curve[8] intValue]==0);
    v.curve=original;assert([v movePointAtIndex:7 toLocation:location(v,0,0)]);assert([v.curve[7] intValue]==91&&[v.curve[15] intValue]==0&&valid(v)); // No forced 100% endpoint.
    v.curve=original;NSPoint centre=[v pointAtIndex:2],down=NSMakePoint(centre.x+4,centre.y+3),up=NSMakePoint(down.x,down.y+[v plotRect].size.height*0.05);
    [v mouseDown:event(v,NSEventTypeLeftMouseDown,down)];[v mouseDragged:event(v,NSEventTypeLeftMouseDragged,up)];[v mouseUp:event(v,NSEventTypeLeftMouseUp,up)];assert([v.curve[2] intValue]==50&&[v.curve[10] intValue]==25);
    [v mouseDown:event(v,NSEventTypeLeftMouseDown,[v pointAtIndex:2])];v.editable=NO;unsigned before=changes;
    [v mouseDragged:event(v,NSEventTypeLeftMouseDragged,location(v,55,30))];[v mouseUp:event(v,NSEventTypeLeftMouseUp,location(v,55,30))];assert(changes==before);
    NSArray *quiet=@[@20,@30,@40,@50,@60,@70,@80,@100,@0,@5,@10,@20,@30,@40,@55,@65];
    NSArray *high=@[@20,@30,@40,@50,@60,@70,@80,@100,@0,@10,@20,@30,@40,@60,@80,@100];
    v.editable=YES;v.minimumCurve=quiet;v.curve=high;
    assert([v movePointAtIndex:6 toLocation:location(v,80,0)]);assert([v.curve[14] intValue]==55&&[v.curve[13] intValue]==55&&valid(v));
    v.curve=high;assert([v movePointAtIndex:6 toLocation:location(v,85,0)]);assert([v.curve[14] intValue]==58&&valid(v)); // ceil(57.5%) at 85C.
    v.curve=quiet;assert(valid(v));before=changes;NSPoint last=[v pointAtIndex:7];
    [v mouseDown:event(v,NSEventTypeLeftMouseDown,last)];[v mouseUp:event(v,NSEventTypeLeftMouseUp,last)];assert(changes==before&&[v.curve isEqual:quiet]);
    // A low last point would extend flat beyond its temperature; protect the tail.
    assert([v movePointAtIndex:7 toLocation:location(v,81,0)]);assert([v.curve[15] intValue]>=65&&[v.curve[15] intValue]<100&&valid(v));
    // A concave quiet preset can exceed a straight candidate between valid knots.
    NSArray *sharp=@[@20,@30,@40,@50,@60,@70,@80,@100,@0,@0,@0,@80,@90,@95,@99,@100];
    v.minimumCurve=sharp;v.curve=@[@20,@30,@40,@60,@70,@80,@90,@100,@100,@100,@100,@100,@100,@100,@100,@100];
    assert([v movePointAtIndex:2 toLocation:location(v,40,0)]);assert(valid(v)&&[v.curve[10] intValue]>=60);
    v.minimumCurve=quiet;v.curve=high;uint32_t seed=0x815;
    for(unsigned n=0;n<4096;n++){
        seed=seed*1664525+1013904223;NSInteger point=(seed>>16)%8;
        seed=seed*1664525+1013904223;double x=(int)(seed%401)-150;
        seed=seed*1664525+1013904223;double y=(int)(seed%401)-150;
        [v movePointAtIndex:point toLocation:location(v,x,y)];assert(valid(v));
    }
    before=changes;assert(![v movePointAtIndex:-1 toLocation:NSZeroPoint]);assert(![v movePointAtIndex:8 toLocation:NSZeroPoint]);assert(![v movePointAtIndex:0 toLocation:NSMakePoint(NAN,INFINITY)]);assert(changes==before);
    [host close];puts("PASS: 20-100C / 0-100%, 1-unit rounding, point selection, raise/right and lower/left cascades, interpolated quiet floor including intervals/tails, free endpoint, offset dragging and 4096 invariant checks; no hardware calls");
}return 0;}
