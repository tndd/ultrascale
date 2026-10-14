#import <Cocoa/Cocoa.h>
@interface USFramePresenter : NSObject
@property(nonatomic) NSInteger filter;
@property(nonatomic) double sharpness;
@property(readonly) BOOL healthy;
@property(readonly) NSUInteger frameCount;
- (BOOL)startSource:(CGDirectDisplayID)source target:(CGDirectDisplayID)target error:(NSError **)error;
- (BOOL)writeSnapshotTo:(NSString *)path error:(NSError **)error;
- (void)stop;
@end
