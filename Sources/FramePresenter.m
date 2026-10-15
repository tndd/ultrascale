#import "FramePresenter.h"
#import "ImagePipeline.h"
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <MetalKit/MetalKit.h>
#import <CoreMedia/CoreMedia.h>
#import <ImageIO/ImageIO.h>

@interface USPresentationWindow : NSWindow
@end
@implementation USPresentationWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

@interface USFramePresenter () <SCStreamOutput, SCStreamDelegate, MTKViewDelegate>
@property(strong) SCStream *stream;
@property(strong) NSWindow *window;
@property(strong) MTKView *view;
@property(strong) CIContext *context;
@property(strong) id<MTLCommandQueue> commandQueue;
@property(strong) CIImage *frame;
@property(strong) NSError *streamError;
@property BOOL drawingScheduled, stopped;
@property(readwrite) NSUInteger frameCount;
@property NSUInteger renderedFrames;
@property(strong) id<MTLTexture> lastTexture;
@end

static BOOL USWait(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    return condition();
}
static BOOL USCaptureFailure(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"UltraScale" code:2 userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
@implementation USFramePresenter
- (BOOL)healthy { return self.stream != nil && !self.streamError && self.frameCount > 0 && !self.stopped && self.window.visible; }
- (BOOL)startSource:(CGDirectDisplayID)source target:(CGDirectDisplayID)target error:(NSError **)error {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return USCaptureFailure(error, @"このMacでMetal描画を利用できません。");
    __block SCShareableContent *content = nil;
    __block NSError *contentError = nil;
    __block BOOL done = NO;
    [SCShareableContent getShareableContentExcludingDesktopWindows:NO onScreenWindowsOnly:NO
        completionHandler:^(SCShareableContent *value, NSError *failure) {
            dispatch_async(dispatch_get_main_queue(), ^{ content = value; contentError = failure; done = YES; });
        }];
    if (!USWait(^BOOL{ return done; }, 8) || !content)
        return USCaptureFailure(error, contentError.localizedDescription ?: @"画面の取得に失敗しました。画面収録の許可を確認してください。");
    SCDisplay *display = nil;
    for (SCDisplay *candidate in content.displays) if (candidate.displayID == source) display = candidate;
    NSScreen *targetScreen = nil;
    for (NSScreen *screen in NSScreen.screens)
        if ([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == target) targetScreen = screen;
    if (!display || !targetScreen) return USCaptureFailure(error, @"描画元または出力先の画面を取得できませんでした。");
    self.stopped = NO; self.streamError = nil; self.frameCount = 0; self.renderedFrames = 0;
    self.context = [CIContext contextWithMTLDevice:device options:@{kCIContextCacheIntermediates:@NO}];
    self.commandQueue = [device newCommandQueue];
    self.view = [[MTKView alloc] initWithFrame:NSMakeRect(0, 0, targetScreen.frame.size.width, targetScreen.frame.size.height) device:device];
    self.view.framebufferOnly = NO; self.view.paused = YES; self.view.enableSetNeedsDisplay = NO;
    self.view.colorPixelFormat = MTLPixelFormatBGRA8Unorm; self.view.delegate = self;
    self.window = [[USPresentationWindow alloc] initWithContentRect:targetScreen.frame
        styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO screen:targetScreen];
    [self.window setFrame:targetScreen.frame display:NO];
    self.window.canHide = NO; self.window.hidesOnDeactivate = NO;
    self.window.releasedWhenClosed = NO; self.window.hasShadow = NO; self.window.opaque = YES;
    self.window.backgroundColor = NSColor.blackColor; self.window.ignoresMouseEvents = YES;
    self.window.level = NSStatusWindowLevel + 1;
    self.window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle;
    self.window.contentView = self.view;
    // 先に黒い画面を出さず、実フレームの取得後に表示する。
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(source);
    if (!mode) { [self stop]; return USCaptureFailure(error, @"描画元の画面がなくなりました。"); }
    SCStreamConfiguration *config = [SCStreamConfiguration new];
    config.width = CGDisplayModeGetPixelWidth(mode); config.height = CGDisplayModeGetPixelHeight(mode);
    CFRelease(mode);
    config.pixelFormat = kCVPixelFormatType_32BGRA; config.minimumFrameInterval = CMTimeMake(1, 60);
    config.queueDepth = 3; config.showsCursor = YES; config.capturesAudio = NO;
    config.captureResolution = SCCaptureResolutionBest;
    SCContentFilter *filter = [[SCContentFilter alloc] initWithDisplay:display excludingWindows:@[]];
    self.stream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:self];
    if (![self.stream addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:dispatch_get_main_queue() error:error]) {
        [self stop]; return NO;
    }
    done = NO;
    [self.stream startCaptureWithCompletionHandler:^(NSError *failure) {
        dispatch_async(dispatch_get_main_queue(), ^{ self.streamError = failure; done = YES; });
    }];
    if (!USWait(^BOOL{ return done && (self.frameCount > 0 || self.streamError); }, 8) || self.streamError || self.frameCount == 0) {
        NSString *message = self.streamError.localizedDescription ?: @"画質調整用の映像を取得できませんでした。通常表示へ戻します。";
        [self stop]; return USCaptureFailure(error, message);
    }
    for (NSScreen *screen in NSScreen.screens)
        if ([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == target) [self.window setFrame:screen.frame display:YES];
    [self.window orderFrontRegardless]; [self.view draw];
    if (!USWait(^BOOL{ return self.renderedFrames > 0 || self.streamError; }, 5) || self.streamError) {
        [self stop]; return USCaptureFailure(error, @"調整した映像の描画に失敗しました。通常表示へ戻します。");
    }
    NSLog(@"画質調整: source=%u target=%u window=%ld visible=%d frame=%@ pixels=%@ captured=%lu rendered=%lu", source, target, (long)self.window.windowNumber, self.window.visible, NSStringFromRect(self.window.frame), NSStringFromSize(self.view.drawableSize), (unsigned long)self.frameCount, (unsigned long)self.renderedFrames);
    return YES;
}
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
    (void)stream;
    if (self.stopped || type != SCStreamOutputTypeScreen || !CMSampleBufferIsValid(sample)) return;
    CVPixelBufferRef buffer = CMSampleBufferGetImageBuffer(sample);
    if (!buffer) return;
    self.frame = [CIImage imageWithCVPixelBuffer:buffer]; self.frameCount++;
    if (self.drawingScheduled) return;
    self.drawingScheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.drawingScheduled = NO;
        if (!self.stopped) [self.view draw];
    });
}
- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error { (void)stream; self.streamError = error; }
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size { (void)view; (void)size; }
- (void)drawInMTKView:(MTKView *)view {
    if (!self.frame || self.stopped) return;
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (!drawable) return;
    CIImage *image = USFilteredImage(self.frame, view.drawableSize, self.filter, self.sharpness);
    if (!image) return;
    id<MTLCommandBuffer> command = [self.commandQueue commandBuffer];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CIRenderDestination *destination = [[CIRenderDestination alloc] initWithMTLTexture:drawable.texture commandBuffer:command];
    destination.colorSpace = space; destination.flipped = YES;
    NSError *error = nil;
    [self.context startTaskToRender:image fromRect:image.extent toDestination:destination atPoint:CGPointZero error:&error];
    CGColorSpaceRelease(space);
    if (error) { self.streamError = error; return; }
    [command addCompletedHandler:^(id<MTLCommandBuffer> finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finished.error) self.streamError = finished.error;
            else self.renderedFrames++;
        });
    }];
    self.lastTexture = drawable.texture;
    [command presentDrawable:drawable]; [command commit];
}
- (void)setFilter:(NSInteger)filter { _filter = MAX(0, MIN(2, filter)); [self.view draw]; }
- (void)setSharpness:(double)sharpness { _sharpness = MAX(0, MIN(1, sharpness)); [self.view draw]; }
// 明示的な実機テストだけが呼ぶ。表示に使ったGPUテクスチャを保存し、向きも検査できるようにする。
- (BOOL)writeSnapshotTo:(NSString *)path error:(NSError **)error {
    id<MTLTexture> source = self.lastTexture;
    if (!source) return USCaptureFailure(error, @"描画済みの画像がありません。");
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:source.pixelFormat
        width:source.width height:source.height mipmapped:NO];
    descriptor.storageMode = MTLStorageModeShared;
    id<MTLTexture> copy = [self.view.device newTextureWithDescriptor:descriptor];
    id<MTLCommandBuffer> command = [self.commandQueue commandBuffer];
    id<MTLBlitCommandEncoder> blit = [command blitCommandEncoder];
    [blit copyFromTexture:source sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0,0,0)
        sourceSize:MTLSizeMake(source.width,source.height,1) toTexture:copy destinationSlice:0 destinationLevel:0 destinationOrigin:MTLOriginMake(0,0,0)];
    [blit endEncoding]; [command commit]; [command waitUntilCompleted];
    if (command.error) { if (error) *error = command.error; return NO; }
    NSMutableData *data = [NSMutableData dataWithLength:source.width * source.height * 4];
    [copy getBytes:data.mutableBytes bytesPerRow:source.width * 4 fromRegion:MTLRegionMake2D(0,0,source.width,source.height) mipmapLevel:0];
    // MetalのBGRAを明示して読み込む。NSBitmapImageRepの並びと混同すると
    // 青・アルファを誤解釈したPNGになり、表示中の画質を検証できない。
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef image = CGImageCreate(source.width, source.height, 8, 32, source.width * 4, space,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst, provider, NULL, NO, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider); CGColorSpaceRelease(space);
    if (!image) return USCaptureFailure(error, @"描画画像のBGRA変換に失敗しました。");
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.png"), 1, NULL);
    if (!destination) { CGImageRelease(image); return USCaptureFailure(error, @"PNGの保存先を開けませんでした。"); }
    CGImageDestinationAddImage(destination, image, NULL);
    BOOL saved = CGImageDestinationFinalize(destination);
    CFRelease(destination); CGImageRelease(image);
    return saved || USCaptureFailure(error, @"PNGの保存に失敗しました。");
}
- (void)stop {
    self.stopped = YES;
    [self.stream stopCaptureWithCompletionHandler:nil]; self.stream = nil;
    [self.window close]; self.window = nil; self.view = nil; self.frame = nil; self.lastTexture = nil;
}
@end
