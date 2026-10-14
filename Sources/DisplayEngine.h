#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

typedef struct { size_t width, height; } USSize;
FOUNDATION_EXPORT USSize USLogicalSize(NSInteger percent);
FOUNDATION_EXPORT BOOL USIsHiDPI(CGDisplayModeRef mode, USSize size);
FOUNDATION_EXPORT NSArray<NSNumber *> *USOnlineDisplays(void);
FOUNDATION_EXPORT id USCreateVirtual(USSize logical, BOOL hidpi, NSString *name, NSError **error);
FOUNDATION_EXPORT CGDirectDisplayID USVirtualID(id display);
FOUNDATION_EXPORT BOOL USWaitForMode(CGDirectDisplayID display, USSize logical, BOOL hidpi);

@interface USDisplay : NSObject
@property CGDirectDisplayID identifier;
@property(copy) NSString *name;
@property BOOL supported;
@end

@interface USDisplayEngine : NSObject
@property(readonly) CGDirectDisplayID target;
@property(readonly) CGDirectDisplayID virtualID;
@property(readonly) NSInteger percent;
@property(readonly) BOOL active;
- (NSArray<USDisplay *> *)displays;
- (BOOL)applyTo:(CGDirectDisplayID)target percent:(NSInteger)percent error:(NSError **)error;
- (BOOL)restore:(NSError **)error;
- (BOOL)isHealthy;
@end
