#import <Cocoa/Cocoa.h>

@interface ROGTuningCurveView : NSView
@property(nonatomic,copy) NSArray<NSNumber *> *curve;
@property(nonatomic,copy) NSArray<NSNumber *> *minimumCurve;
@property(nonatomic) BOOL editable;
@property(nonatomic,copy) void (^changed)(NSArray<NSNumber *> *curve);
- (NSInteger)pointIndexAtLocation:(NSPoint)location;
- (BOOL)movePointAtIndex:(NSInteger)index toLocation:(NSPoint)location;
@end
