#import "DisplayEngine.h"
#import "FramePresenter.h"
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
// 適用操作では状態の確認だけを行う。許可要求で既存表示や操作を中断しない。
static BOOL USCheckFilterPermissions(NSError **error) {
    BOOL capture = CGPreflightScreenCaptureAccess(), accessibility = AXIsProcessTrusted();
    if (!capture || !accessibility) {
        NSString *missing = !capture && !accessibility ? @"画面収録・アクセシビリティ" : (!capture ? @"画面収録" : @"アクセシビリティ");
        return USFail(error, [NSString stringWithFormat:@"画質調整の%@が未許可です。通常表示は継続します。許可を変更する場合はシステム設定でUltraScaleを確認してください。", missing]);
    }
    return YES;
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

// 画質調整用の仮想画面へウインドウを移す。対象モニタ内のウインドウだけを扱う。
static NSArray<NSDictionary *> *USWindowsInRect(CGRect displayBounds) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
        AXUIElementRef application = AXUIElementCreateApplication(app.processIdentifier);
        CFTypeRef value = NULL;
        if (AXUIElementCopyAttributeValue(application, kAXWindowsAttribute, &value) == kAXErrorSuccess && value) {
            NSArray *windows = CFBridgingRelease(value);
            for (id element in windows) {
                CFTypeRef position = NULL, size = NULL;
                AXUIElementRef window = (__bridge AXUIElementRef)element;
                if (AXUIElementCopyAttributeValue(window, kAXPositionAttribute, &position) == kAXErrorSuccess &&
                    AXUIElementCopyAttributeValue(window, kAXSizeAttribute, &size) == kAXErrorSuccess && position && size) {
                    CGPoint point; CGSize dimensions;
                    if (CFGetTypeID(position) == AXValueGetTypeID() && CFGetTypeID(size) == AXValueGetTypeID() &&
                        AXValueGetValue(position, kAXValueCGPointType, &point) && AXValueGetValue(size, kAXValueCGSizeType, &dimensions)) {
                        CGRect frame = (CGRect){point, dimensions};
                        if (CGRectContainsPoint(displayBounds, CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame))))
                            [result addObject:@{@"window":element, @"rect":[NSValue valueWithRect:NSRectFromCGRect(frame)]}];
                    }
                }
                if (position) CFRelease(position); if (size) CFRelease(size);
            }
        }
        CFRelease(application);
    }
    return result;
}
static void USMoveWindows(NSArray<NSDictionary *> *windows, CGRect from, CGRect to) {
    if (from.size.width <= 0 || from.size.height <= 0) return;
    for (NSDictionary *item in windows) {
        CGRect frame = NSRectToCGRect([item[@"rect"] rectValue]);
        CGPoint point = CGPointMake(to.origin.x + (frame.origin.x - from.origin.x) * to.size.width / from.size.width,
            to.origin.y + (frame.origin.y - from.origin.y) * to.size.height / from.size.height);
        point.x = MAX(to.origin.x, MIN(CGRectGetMaxX(to) - MIN(frame.size.width, to.size.width), point.x));
        point.y = MAX(to.origin.y + 24, MIN(CGRectGetMaxY(to) - MIN(frame.size.height, to.size.height), point.y));
        AXValueRef position = AXValueCreate(kAXValueCGPointType, &point);
        AXUIElementSetAttributeValue((__bridge AXUIElementRef)item[@"window"], kAXPositionAttribute, position);
        CFRelease(position);
    }
}

@implementation USDisplay
@end

@implementation USDisplayEngine {
    id _virtualDisplay;
    USFramePresenter *_presenter;
    CGRect _sourceBounds, _targetBounds;
    CGDisplayModeRef _originalMode;
    NSDictionary<NSNumber *, NSValue *> *_origins;
}
@synthesize filter = _filter, sharpness = _sharpness;
- (BOOL)activeUsesFilters { return _presenter != nil; }
- (NSUInteger)capturedFrames { return _presenter.frameCount; }
- (void)setFilter:(NSInteger)value { _filter = MAX(0, MIN(2, value)); _presenter.filter = _filter; }
- (void)setSharpness:(double)value { _sharpness = MAX(0, MIN(1, value)); _presenter.sharpness = _sharpness; }
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
    if (self.useFilters && !USCheckFilterPermissions(error)) return NO;
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
    _targetBounds = CGDisplayBounds(target);
    NSArray *windowsToMove = self.useFilters ? USWindowsInRect(_targetBounds) : nil;
    USSize size = USLogicalSize(percent);
    _virtualDisplay = USCreateVirtual(size, YES, @"UltraScale HiDPI", error);
    if (!_virtualDisplay || !USWaitForMode(self.virtualID, size, YES)) {
        if (!error || !*error) USFail(error, @"指定した2倍描画モードを確認できませんでした。元の表示へ戻します。");
        [self restore:NULL]; return NO;
    }
    CGDisplayConfigRef config = NULL;
    CGError status = CGBeginDisplayConfiguration(&config);
    if (self.useFilters && status == kCGErrorSuccess) {
        CGDisplayModeRef native = NULL;
        NSArray *modes = CFBridgingRelease(CGDisplayCopyAllDisplayModes(target, NULL));
        for (id value in modes) {
            CGDisplayModeRef mode = (__bridge CGDisplayModeRef)value;
            if (CGDisplayModeGetWidth(mode) == 3440 && CGDisplayModeGetHeight(mode) == 1440 &&
                CGDisplayModeGetPixelWidth(mode) == 3440 && CGDisplayModeGetRefreshRate(mode) <= 60.1) { native = mode; break; }
        }
        if (!native) status = kCGErrorFailure;
        else status = CGConfigureDisplayWithDisplayMode(config, target, native, NULL);
        CGPoint sourceOrigin = [_origins[@(target)] pointValue];
        // 仮想画面を元のモニタの位置へ置き、実モニタは描画専用の離れた位置へ退避する。
        // 入力は仮想デスクトップへ通常どおり届き、取得したカーソルを映像と一緒に表示する。
        CGRect targetBounds = CGDisplayBounds(target);
        for (NSNumber *number in _origins) {
            if (number.unsignedIntValue == target) continue;
            CGRect other = CGDisplayBounds(number.unsignedIntValue);
            if (fabs(CGRectGetMaxY(targetBounds) - CGRectGetMinY(other)) < 1) sourceOrigin.y = CGRectGetMaxY(targetBounds) - size.height;
            if (fabs(CGRectGetMaxX(targetBounds) - CGRectGetMinX(other)) < 1) sourceOrigin.x = CGRectGetMaxX(targetBounds) - size.width;
        }
        if (status == kCGErrorSuccess) status = CGConfigureDisplayOrigin(config, target, 16000, 0);
        if (status == kCGErrorSuccess) status = CGConfigureDisplayOrigin(config, self.virtualID, (int32_t)sourceOrigin.x, (int32_t)sourceOrigin.y);
    } else {
        if (status == kCGErrorSuccess) status = CGConfigureDisplayMirrorOfDisplay(config, target, self.virtualID);
        if (status == kCGErrorSuccess) {
            NSPoint origin = [_origins[@(target)] pointValue];
            status = CGConfigureDisplayOrigin(config, self.virtualID, (int32_t)origin.x, (int32_t)origin.y);
        }
    }
    if (status == kCGErrorSuccess) status = CGCompleteDisplayConfiguration(config, kCGConfigureForAppOnly);
    else if (config) CGCancelDisplayConfiguration(config);
    if (status == kCGErrorSuccess && self.useFilters) {
        _sourceBounds = CGDisplayBounds(self.virtualID);
        USMoveWindows(windowsToMove, _targetBounds, _sourceBounds);
        _presenter = [USFramePresenter new]; _presenter.filter = self.filter; _presenter.sharpness = self.sharpness;
        if (![_presenter startSource:self.virtualID target:target error:error]) status = kCGErrorFailure;
    }
    if (status != kCGErrorSuccess || ![self isHealthy]) {
        if (!error || !*error) USFail(error, [NSString stringWithFormat:@"HiDPI表示を確認できませんでした（%d）。元の表示へ戻します。", status]);
        [self restore:NULL]; return NO;
    }
    return YES;
}
- (BOOL)writeFilteredSnapshotTo:(NSString *)path error:(NSError **)error {
    if (!_presenter) return USFail(error, @"画質調整モードではありません。");
    return [_presenter writeSnapshotTo:path error:error];
}
- (BOOL)isHealthy {
    if (!self.active || !CGDisplayIsOnline(_target)) return NO;
    if (_presenter ? !_presenter.healthy : CGDisplayMirrorsDisplay(_target) != self.virtualID) return NO;
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(self.virtualID);
    BOOL healthy = USIsHiDPI(mode, USLogicalSize(_percent));
    if (mode) CFRelease(mode);
    return healthy;
}
- (BOOL)restore:(NSError **)error {
    BOOL filtered = _presenter != nil;
    NSArray *windowsToReturn = filtered ? USWindowsInRect(_sourceBounds) : nil;
    [_presenter stop]; _presenter = nil;
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
    if (filtered && status == kCGErrorSuccess && CGDisplayIsOnline(_target)) USMoveWindows(windowsToReturn, _sourceBounds, _targetBounds);
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
