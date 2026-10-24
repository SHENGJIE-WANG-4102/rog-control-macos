#import <Cocoa/Cocoa.h>
@interface ROGTuningController : NSViewController
@property(copy) void (^submit)(NSDictionary *request);
- (void)setConnected:(BOOL)connected busy:(BOOL)busy onAC:(BOOL)onAC bridgeVersion:(NSString *)version;
- (void)renderResponse:(NSDictionary *)response;
@end
