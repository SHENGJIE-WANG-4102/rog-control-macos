#import "TuningCurveView.h"
#include <math.h>
#include "../Shared/CurvePolicy.h"

@implementation ROGTuningCurveView {
    NSInteger _draggedPoint;
    NSPoint _grabOffset;
    BOOL _didDrag;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame])){_draggedPoint=-1;[self setAccessibilityElement:YES];[self setAccessibilityRole:NSAccessibilityImageRole];[self setAccessibilityLabel:@"风扇曲线"];}
    return self;
}
- (void)setCurve:(NSArray<NSNumber *> *)curve {
    if([_curve isEqual:curve]||(!_curve&&!curve))return;
    _curve=[curve copy];self.needsDisplay=YES;
    NSMutableArray *points=[NSMutableArray array];
    if(_curve.count==16)for(unsigned i=0;i<8;i++)[points addObject:[NSString stringWithFormat:@"%@°C：%@%%",_curve[i],_curve[i+8]]];
    [self setAccessibilityValue:points.count?[points componentsJoinedByString:@"，"]:@"等待有效曲线"];
}
- (void)setMinimumCurve:(NSArray<NSNumber *> *)curve {
    if([_minimumCurve isEqual:curve]||(!_minimumCurve&&!curve))return;
    _minimumCurve=[curve copy];self.needsDisplay=YES;
}
- (NSRect)plotRect {return NSMakeRect(36,24,MAX(1,self.bounds.size.width-53),MAX(1,self.bounds.size.height-36));}
- (NSPoint)pointAtIndex:(NSInteger)index {
    NSRect plot=[self plotRect];
    return NSMakePoint(plot.origin.x+plot.size.width*([self.curve[index] doubleValue]-20)/80.0,plot.origin.y+plot.size.height*[self.curve[index+8] doubleValue]/100.0);
}
- (void)setEditable:(BOOL)editable {
    if(_editable==editable)return;_editable=editable;
    if(!editable)_draggedPoint=-1;
    [self.window invalidateCursorRectsForView:self];self.needsDisplay=YES;
}
- (void)resetCursorRects {if(self.editable)[self addCursorRect:[self plotRect] cursor:NSCursor.crosshairCursor];}
- (NSInteger)pointIndexAtLocation:(NSPoint)location {
    if(!self.editable||self.curve.count!=16||self.minimumCurve.count!=16)return -1;
    NSInteger best=-1;double distance=100; // Ten logical pixels, independent of backing scale.
    for(NSInteger i=0;i<8;i++){
        NSPoint p=[self pointAtIndex:i];double squared=(p.x-location.x)*(p.x-location.x)+(p.y-location.y)*(p.y-location.y);
        if(squared<distance){best=i;distance=squared;}
    }return best;
}
- (BOOL)movePointAtIndex:(NSInteger)index toLocation:(NSPoint)location {
    if(!self.editable||self.curve.count!=16||self.minimumCurve.count!=16||index<0||index>7||!isfinite(location.x)||!isfinite(location.y))return NO;
    NSRect plot=[self plotRect];
    // Clamp before rounding so even far outside the plot cannot overflow lround.
    NSInteger temperature=20+lround(fmax(0,fmin(80,(location.x-plot.origin.x)*80/plot.size.width)));
    NSInteger percent=lround(fmax(0,fmin(100,(location.y-plot.origin.y)*100/plot.size.height)));
    NSInteger lowT=index?[self.curve[index-1] integerValue]+1:20,highT=index<7?[self.curve[index+1] integerValue]-1:100;
    if(lowT>highT)return NO;
    temperature=MAX(lowT,MIN(highT,temperature));
    uint8_t values[16],quiet[16];for(unsigned i=0;i<16;i++){values[i]=[self.curve[i] unsignedIntValue];quiet[i]=[self.minimumCurve[i] unsignedIntValue];}
    if(!ROGCurveOrdered(quiet,0))return NO;
    percent=MAX(percent,(NSInteger)ROGCurveFloorAt(quiet,(unsigned)temperature));
    values[index]=(uint8_t)temperature;values[index+8]=(uint8_t)percent;
    for(NSInteger i=index-1;i>=0;i--)if(values[i+8]>percent)values[i+8]=(uint8_t)percent;
    for(NSInteger i=index+1;i<8;i++)if(values[i+8]<percent)values[i+8]=(uint8_t)percent;
    if(!ROGCurveRepairFloor(values,quiet,(unsigned)index))return NO;
    NSMutableArray *curve=[NSMutableArray array];for(unsigned i=0;i<16;i++)[curve addObject:@(values[i])];
    if([self.curve isEqual:curve])return NO;
    self.curve=curve;if(self.changed)self.changed([curve copy]);return YES;
}
- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:nil];
    NSPoint location=[self convertPoint:event.locationInWindow fromView:nil];_draggedPoint=[self pointIndexAtLocation:location];_didDrag=NO;
    if(_draggedPoint>=0){NSPoint center=[self pointAtIndex:_draggedPoint];_grabOffset=NSMakePoint(center.x-location.x,center.y-location.y);self.needsDisplay=YES;}
}
- (void)mouseDragged:(NSEvent *)event {
    if(_draggedPoint<0)return;_didDrag=YES;
    NSPoint p=[self convertPoint:event.locationInWindow fromView:nil];p.x+=_grabOffset.x;p.y+=_grabOffset.y;[self movePointAtIndex:_draggedPoint toLocation:p];
}
- (void)mouseUp:(NSEvent *)event {
    if(_didDrag&&_draggedPoint>=0){NSPoint p=[self convertPoint:event.locationInWindow fromView:nil];p.x+=_grabOffset.x;p.y+=_grabOffset.y;[self movePointAtIndex:_draggedPoint toLocation:p];}
    _draggedPoint=-1;_didDrag=NO;self.needsDisplay=YES;
}
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [NSColor.controlBackgroundColor setFill];[[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:8 yRadius:8] fill];
    NSRect plot=[self plotRect];
    NSDictionary *style=@{NSFontAttributeName:[NSFont systemFontOfSize:9],NSForegroundColorAttributeName:NSColor.secondaryLabelColor};
    NSBezierPath *grid=[NSBezierPath bezierPath];grid.lineWidth=0.5;
    for(unsigned i=0;i<=8;i++){
        CGFloat x=plot.origin.x+plot.size.width*i/8.0;
        [grid moveToPoint:NSMakePoint(x,NSMinY(plot))];[grid lineToPoint:NSMakePoint(x,NSMaxY(plot))];
        NSString *temperature=[NSString stringWithFormat:@"%u°C",20+i*10];
        [temperature drawAtPoint:NSMakePoint(x-[temperature sizeWithAttributes:style].width/2,6) withAttributes:style];
    }
    for(unsigned i=0;i<=10;i++){
        CGFloat y=plot.origin.y+plot.size.height*i/10.0;
        [grid moveToPoint:NSMakePoint(NSMinX(plot),y)];[grid lineToPoint:NSMakePoint(NSMaxX(plot),y)];
        NSString *percent=[NSString stringWithFormat:@"%u%%",i*10];
        [percent drawAtPoint:NSMakePoint(plot.origin.x-[percent sizeWithAttributes:style].width-6,y-5) withAttributes:style];
    }
    [NSColor.separatorColor setStroke];[grid stroke];
    if(self.minimumCurve.count==16){
        uint8_t quiet[16];for(unsigned i=0;i<16;i++)quiet[i]=[self.minimumCurve[i] unsignedIntValue];
        if(ROGCurveOrdered(quiet,0)){
            NSBezierPath *floor=[NSBezierPath bezierPath];floor.lineWidth=1;CGFloat dash[]={3,3};[floor setLineDash:dash count:2 phase:0];
            for(unsigned t=20;t<=100;t++){
                ROGCurveSample sample=ROGCurveSampleAt(quiet,t);NSPoint p=NSMakePoint(plot.origin.x+plot.size.width*(t-20)/80.0,plot.origin.y+plot.size.height*sample.numerator/(sample.denominator*100.0));
                if(t==20)[floor moveToPoint:p];else[floor lineToPoint:p];
            }[NSColor.secondaryLabelColor setStroke];[floor stroke];
        }
    }
    if(self.curve.count!=16)return;
    NSBezierPath *line=[NSBezierPath bezierPath];line.lineWidth=2;line.lineJoinStyle=NSLineJoinStyleRound;
    for(unsigned i=0;i<8;i++){
        NSPoint p=[self pointAtIndex:i];
        if(i)[line lineToPoint:p];else [line moveToPoint:p];
    }
    [NSColor.systemBlueColor setStroke];[line stroke];[NSColor.systemBlueColor setFill];
    for(unsigned i=0;i<8;i++){
        NSPoint p=[self pointAtIndex:i];CGFloat radius=self.editable?4:2.5;
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(p.x-radius,p.y-radius,radius*2,radius*2)] fill];
        if((NSInteger)i==_draggedPoint){NSBezierPath *selection=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(p.x-7,p.y-7,14,14)];selection.lineWidth=1;[selection stroke];}
    }
}
@end
