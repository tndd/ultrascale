#import "DisplayEngine.h"
#import <math.h>

// 非公開APIは動的に解決し、利用できないOSでは設定を変更せず終了する。
@interface USVirtualDescriptor : NSObject
@property(strong) dispatch_queue_t queue;
@property(copy) NSString *name;
@property CGSize sizeInMillimeters;
@property unsigned int maxPixelsWide, maxPixelsHigh, vendorID, productID, serialNum;
@property CGPoint redPrimary, greenPrimary, bluePrimary, whitePoint;
@end
@interface USVirtualMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)rate;
@end
@interface USVirtualSettings : NSObject
@property(strong) NSArray *modes;
@property unsigned int hiDPI;
@end
@interface USVirtual : NSObject
@property(readonly) unsigned int displayID;
- (instancetype)initWithDescriptor:(id)descriptor;
- (BOOL)applySettings:(id)settings;
@end

static const uint32_t USVendor = 0x554C;
static NSError *USError(NSString *message) {
    return [NSError errorWithDomain:@"UltraScale" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL USFail(NSError **error, NSString *message) {
    if (error) *error = USError(message);
    return NO;
}
USSize USLogicalSize(NSInteger percent) {
    double scale = MAX(100, MIN(200, percent)) / 100.0;
    return (USSize){(size_t)llround(3440 / scale), (size_t)llround(1440 / scale)};
}
BOOL USIsHiDPI(CGDisplayModeRef mode, USSize size) {
    return mode && CGDisplayModeGetWidth(mode) == size.width && CGDisplayModeGetHeight(mode) == size.height &&
        CGDisplayModeGetPixelWidth(mode) == 2 * size.width && CGDisplayModeGetPixelHeight(mode) == 2 * size.height;
}
NSArray<NSNumber *> *USOnlineDisplays(void) {
    CGDirectDisplayID ids[64]; uint32_t count = 0;
    if (CGGetOnlineDisplayList(64, ids, &count) != kCGErrorSuccess) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (uint32_t i = 0; i < count; ++i) [result addObject:@(ids[i])];
    return result;
}
CGDirectDisplayID USVirtualID(id display) { return [(USVirtual *)display displayID]; }
id USCreateVirtual(USSize logical, BOOL hidpi, NSString *name, NSError **error) {
    Class descriptorClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");
    if (!descriptorClass || !displayClass || !modeClass || !settingsClass) {
        USFail(error, @"このmacOSでは仮想HiDPIディスプレイAPIを利用できません。"); return nil;
    }
    @try {
        USVirtualDescriptor *descriptor = [[descriptorClass alloc] init];
        descriptor.name = name;
        descriptor.queue = dispatch_get_main_queue();
        descriptor.vendorID = USVendor;
        descriptor.productID = 0x1440;
        descriptor.serialNum = arc4random_uniform(UINT32_MAX - 1) + 1;
        descriptor.sizeInMillimeters = CGSizeMake(800, 335);
        descriptor.maxPixelsWide = (unsigned int)logical.width * (hidpi ? 2 : 1);
        descriptor.maxPixelsHigh = (unsigned int)logical.height * (hidpi ? 2 : 1);
        descriptor.redPrimary = CGPointMake(0.64, 0.33);
        descriptor.greenPrimary = CGPointMake(0.30, 0.60);
        descriptor.bluePrimary = CGPointMake(0.15, 0.06);
        descriptor.whitePoint = CGPointMake(0.3127, 0.3290);
        USVirtual *display = [[displayClass alloc] initWithDescriptor:descriptor];
        if (!display) { USFail(error, @"仮想ディスプレイを作成できませんでした。"); return nil; }
        USVirtualSettings *settings = [[settingsClass alloc] init];
        settings.hiDPI = hidpi ? 1 : 0;
        // hiDPI=1ではモードに論理解像度、上限には2倍の描画ピクセル数を渡す。
        USVirtualMode *mode = [[modeClass alloc] initWithWidth:(unsigned int)logical.width
            height:(unsigned int)logical.height refreshRate:60.0];
        settings.modes = @[mode];
        if (![display applySettings:settings]) {
            USFail(error, @"指定した解像度の仮想ディスプレイを有効にできませんでした。"); return nil;
        }
        return display;
    } @catch (NSException *exception) {
        USFail(error, [@"仮想ディスプレイAPIが対応していません: " stringByAppendingString:exception.reason ?: @""]);
        return nil;
    }
}
BOOL USWaitForMode(CGDirectDisplayID display, USSize logical, BOOL hidpi) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:4];
    BOOL attempted = NO;
    do {
        CGDisplayModeRef current = CGDisplayCopyDisplayMode(display);
        BOOL matches = hidpi ? USIsHiDPI(current, logical) :
            (current && CGDisplayModeGetWidth(current) == logical.width && CGDisplayModeGetHeight(current) == logical.height);
        if (current) CFRelease(current);
        if (matches) return YES;
        if (!attempted) {
            NSArray *modes = CFBridgingRelease(CGDisplayCopyAllDisplayModes(display,
                (__bridge CFDictionaryRef)@{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes:@YES}));
            for (id value in modes) {
                CGDisplayModeRef mode = (__bridge CGDisplayModeRef)value;
                if (hidpi && USIsHiDPI(mode, logical)) {
                    CGDisplaySetDisplayMode(display, mode, NULL); attempted = YES; break;
                }
            }
        }
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    } while (deadline.timeIntervalSinceNow > 0);
    return NO;
}

@implementation USDisplay
@end

@implementation USDisplayEngine {
    id _virtualDisplay;
    CGDisplayModeRef _originalMode;
    NSDictionary<NSNumber *, NSValue *> *_origins;
}
- (BOOL)active { return _virtualDisplay != nil; }
- (CGDirectDisplayID)virtualID { return USVirtualID(_virtualDisplay); }
- (NSArray<USDisplay *> *)displays {
    NSMutableArray *result = [NSMutableArray array];
    for (NSNumber *number in USOnlineDisplays()) {
        CGDirectDisplayID display = number.unsignedIntValue;
        if (CGDisplayIsBuiltin(display) || CGDisplayVendorNumber(display) == USVendor) continue;
        USDisplay *item = [USDisplay new]; item.identifier = display;
        item.name = [NSString stringWithFormat:@"外部ディスプレイ %u", display];
        for (NSScreen *screen in NSScreen.screens) {
            if ([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == display) item.name = screen.localizedName;
        }
        NSArray *modes = CFBridgingRelease(CGDisplayCopyAllDisplayModes(display, NULL));
        for (id value in modes) {
            CGDisplayModeRef mode = (__bridge CGDisplayModeRef)value;
            if (CGDisplayModeGetPixelWidth(mode) == 3440 && CGDisplayModeGetPixelHeight(mode) == 1440) item.supported = YES;
        }
        if (display == _target && self.active) item.supported = YES;
        [result addObject:item];
    }
    return result;
}
- (BOOL)applyTo:(CGDirectDisplayID)target percent:(NSInteger)percent error:(NSError **)error {
    if (percent < 100 || percent > 200) return USFail(error, @"倍率は100〜200%を指定してください。");
    if (CGDisplayIsBuiltin(target) || ![USOnlineDisplays() containsObject:@(target)])
        return USFail(error, @"接続されている外部ディスプレイを選んでください。");
    BOOL supported = NO;
    for (USDisplay *display in self.displays) if (display.identifier == target && display.supported) supported = YES;
    if (!supported) return USFail(error, @"3440 × 1440に対応する外部ディスプレイが必要です。");
    if (self.active && ![self restore:error]) return NO;
    for (NSNumber *number in USOnlineDisplays()) {
        if (CGDisplayMirrorsDisplay(target) || CGDisplayMirrorsDisplay(number.unsignedIntValue) == target)
            return USFail(error, @"既存のミラーリングをシステム設定で解除してから適用してください。");
    }
    _target = target; _percent = percent;
    _originalMode = CGDisplayCopyDisplayMode(target);
    if (!_originalMode) { _target = 0; return USFail(error, @"元の表示モードを取得できませんでした。"); }
    NSMutableDictionary *origins = [NSMutableDictionary dictionary];
    for (NSNumber *number in USOnlineDisplays()) {
        if (!CGDisplayMirrorsDisplay(number.unsignedIntValue))
            origins[number] = [NSValue valueWithPoint:NSPointFromCGPoint(CGDisplayBounds(number.unsignedIntValue).origin)];
    }
    _origins = origins;
    USSize size = USLogicalSize(percent);
    _virtualDisplay = USCreateVirtual(size, YES, @"UltraScale HiDPI", error);
    if (!_virtualDisplay || !USWaitForMode(self.virtualID, size, YES)) {
        if (!error || !*error) USFail(error, @"指定した2倍描画モードを確認できませんでした。元の表示へ戻します。");
        [self restore:NULL]; return NO;
    }
    CGDisplayConfigRef config = NULL;
    CGError status = CGBeginDisplayConfiguration(&config);
    if (status == kCGErrorSuccess) status = CGConfigureDisplayMirrorOfDisplay(config, target, self.virtualID);
    if (status == kCGErrorSuccess) {
        NSPoint origin = [_origins[@(target)] pointValue];
        status = CGConfigureDisplayOrigin(config, self.virtualID, (int32_t)origin.x, (int32_t)origin.y);
    }
    if (status == kCGErrorSuccess) status = CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly);
    else if (config) CGCancelDisplayConfiguration(config);
    if (status != kCGErrorSuccess || ![self isHealthy]) {
        USFail(error, [NSString stringWithFormat:@"HiDPIミラー表示を確認できませんでした（%d）。元の表示へ戻します。", status]);
        [self restore:NULL]; return NO;
    }
    return YES;
}
- (BOOL)isHealthy {
    if (!self.active || !CGDisplayIsOnline(_target) || CGDisplayMirrorsDisplay(_target) != self.virtualID) return NO;
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(self.virtualID);
    BOOL healthy = USIsHiDPI(mode, USLogicalSize(_percent));
    if (mode) CFRelease(mode);
    return healthy;
}
- (BOOL)restore:(NSError **)error {
    if (!_originalMode && !_virtualDisplay) return YES;
    CGError status = kCGErrorSuccess;
    if ([USOnlineDisplays() containsObject:@(_target)]) {
        CGDisplayConfigRef config = NULL;
        status = CGBeginDisplayConfiguration(&config);
        if (status == kCGErrorSuccess) status = CGConfigureDisplayMirrorOfDisplay(config, _target, kCGNullDirectDisplay);
        if (status == kCGErrorSuccess && _originalMode) status = CGConfigureDisplayWithDisplayMode(config, _target, _originalMode, NULL);
        for (NSNumber *number in _origins) {
            if (status != kCGErrorSuccess) break;
            if ([USOnlineDisplays() containsObject:number]) {
                NSPoint origin = [_origins[number] pointValue];
                status = CGConfigureDisplayOrigin(config, number.unsignedIntValue, (int32_t)origin.x, (int32_t)origin.y);
            }
        }
        if (status == kCGErrorSuccess) status = CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly);
        else if (config) CGCancelDisplayConfiguration(config);
    }
    CGDirectDisplayID removedDisplay = self.virtualID;
    _virtualDisplay = nil;
    if (![USOnlineDisplays() containsObject:@(_target)]) status = kCGErrorSuccess;
    // 仮想画面の解放直後は古いモードが返ることがある。次の適用がそれを保存しないよう待つ。
    if (status == kCGErrorSuccess && _originalMode && [USOnlineDisplays() containsObject:@(_target)]) {
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:4];
        BOOL restored = NO;
        do {
            CGDisplayModeRef current = CGDisplayCopyDisplayMode(_target);
            restored = current && !CGDisplayMirrorsDisplay(_target) &&
                CGDisplayModeGetWidth(current) == CGDisplayModeGetWidth(_originalMode) &&
                CGDisplayModeGetHeight(current) == CGDisplayModeGetHeight(_originalMode) &&
                CGDisplayModeGetPixelWidth(current) == CGDisplayModeGetPixelWidth(_originalMode) &&
                CGDisplayModeGetPixelHeight(current) == CGDisplayModeGetPixelHeight(_originalMode);
            if (current) CFRelease(current);
            BOOL ownDisplayRemains = removedDisplay && [USOnlineDisplays() containsObject:@(removedDisplay)];
            if (restored && !ownDisplayRemains) break;
            restored = NO;
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        } while (deadline.timeIntervalSinceNow > 0);
        if (!restored) status = kCGErrorFailure;
    }
    if (_originalMode) CFRelease(_originalMode);
    _originalMode = NULL; _origins = nil; _target = 0; _percent = 0;
    if (status != kCGErrorSuccess) return USFail(error, [NSString stringWithFormat:@"仮想画面は終了しましたが、元の配置の復元に失敗しました（%d）。システム設定のディスプレイを確認してください。", status]);
    return YES;
}
- (void)dealloc {
    if (_originalMode) CFRelease(_originalMode);
}
@end
