#import "DisplayEngine.h"

static int USExitCode = 0;
@interface USBackground : NSView
@end
@implementation USBackground
- (void)drawRect:(NSRect)rect { [NSColor.windowBackgroundColor setFill]; NSRectFill(rect); }
@end

@interface USPreview : NSView
@property NSInteger percent;
@end
@implementation USPreview
- (BOOL)isFlipped { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect screen = NSInsetRect(self.bounds, 2, 2);
    [[NSColor colorWithSRGBRed:0.09 green:0.17 blue:0.25 alpha:1] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:screen xRadius:12 yRadius:12] fill];
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(screen, 10, 10) xRadius:6 yRadius:6] addClip];
    CGFloat scale = self.percent / 100.0;
    NSRect card = NSMakeRect(25, 22, 230 * scale, 110 * scale);
    [NSColor.whiteColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:card xRadius:6 yRadius:6] fill];
    [@"読みやすい、大きさへ。" drawAtPoint:NSMakePoint(38, 37)
        withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:14 * scale weight:NSFontWeightSemibold],
            NSForegroundColorAttributeName:[NSColor colorWithWhite:0.15 alpha:1]}];
    [@"文字とUIの大きさのイメージ" drawAtPoint:NSMakePoint(38, 43 + 20 * scale)
        withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:10 * scale],
            NSForegroundColorAttributeName:[NSColor colorWithWhite:0.4 alpha:1]}];
    for (int row = 0; row < 2; row++) {
        [[NSColor colorWithWhite:0.88 alpha:1] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(38, 46 + (43 + row * 13) * scale, (row ? 125 : 165) * scale, 4 * scale) xRadius:2 yRadius:2] fill];
    }
    [NSGraphicsContext restoreGraphicsState];
}
@end

@interface USApp : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(strong) NSWindow *window;
@property(strong) USDisplayEngine *engine;
@property(strong) NSPopUpButton *displayPicker;
@property(strong) NSSlider *slider;
@property(strong) NSTextField *percentLabel, *resolutionLabel, *statusLabel, *confirmationLabel;
@property(strong) USPreview *preview;
@property(strong) NSButton *applyButton, *restoreButton, *keepButton;
@property(strong) NSStatusItem *statusItem;
@property(strong) NSTimer *timer;
@property(copy) NSArray<USDisplay *> *displays;
@property BOOL busy, pending, uiTest;
@property NSTimeInterval deadline;
- (void)show:(id)sender;
- (void)refresh;
- (void)scaleChanged:(id)sender;
- (void)apply:(id)sender;
- (void)restore:(id)sender;
- (void)keep:(id)sender;
- (void)tick;
@end

static NSTextField *USLabel(NSView *parent, NSString *text, NSRect frame, CGFloat size, BOOL bold) {
    NSTextField *label = [NSTextField wrappingLabelWithString:text];
    label.frame = frame;
    label.font = [NSFont systemFontOfSize:size weight:bold ? NSFontWeightSemibold : NSFontWeightRegular];
    [parent addSubview:label];
    return label;
}
static NSButton *USButton(NSView *parent, NSString *title, NSRect frame, id target, SEL action) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.bezelStyle = NSBezelStyleRounded; button.frame = frame;
    [parent addSubview:button]; return button;
}

@implementation USApp
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.engine = [USDisplayEngine new];
    self.uiTest = [NSProcessInfo.processInfo.arguments containsObject:@"--ui-test"];
    [self createMenu];
    [self createWindow];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(displaysChanged:)
        name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(willSleep:)
        name:NSWorkspaceWillSleepNotification object:nil];
    self.timer = [NSTimer timerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self refresh]; [self show:nil];
    if (self.uiTest) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2), dispatch_get_main_queue(), ^{ [self runUITest]; });
}
- (void)createMenu {
    NSMenu *menu = [NSMenu new];
    NSMenuItem *app = [NSMenuItem new]; [menu addItem:app];
    app.submenu = [NSMenu new];
    [app.submenu addItemWithTitle:@"UltraScaleを終了" action:@selector(terminate:) keyEquivalent:@"q"];
    NSMenuItem *window = [NSMenuItem new]; [menu addItem:window];
    window.title = @"ウインドウ"; window.submenu = [NSMenu new];
    NSMenuItem *show = [window.submenu addItemWithTitle:@"UltraScaleを表示" action:@selector(show:) keyEquivalent:@"0"];
    show.target = self;
    NSApp.mainMenu = menu;
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.image = [NSImage imageWithSystemSymbolName:@"display" accessibilityDescription:@"UltraScale"];
    NSMenu *status = [NSMenu new];
    for (NSArray *entry in @[@[@"倍率を調整…", NSStringFromSelector(@selector(show:))],
                             @[@"元の表示に戻す", NSStringFromSelector(@selector(restore:))]]) {
        NSMenuItem *item = [status addItemWithTitle:entry[0] action:NSSelectorFromString(entry[1]) keyEquivalent:@""];
        item.target = self;
    }
    [status addItem:NSMenuItem.separatorItem];
    [status addItemWithTitle:@"終了して元の表示に戻す" action:@selector(terminate:) keyEquivalent:@"q"];
    self.statusItem.menu = status;
}
- (void)createWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 650)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"UltraScale"; self.window.delegate = self;
    self.window.releasedWhenClosed = NO;
    self.window.contentView = [[USBackground alloc] initWithFrame:NSMakeRect(0, 0, 620, 650)];
    [self.window center];
    NSView *view = self.window.contentView;
    USLabel(view, @"ちょうどいい、大きさに。", NSMakeRect(28, 589, 560, 34), 25, YES);
    NSTextField *subtitle = USLabel(view, @"3440 × 1440  /  ウルトラワイド向けHiDPI", NSMakeRect(28, 558, 560, 24), 13, NO);
    subtitle.textColor = NSColor.secondaryLabelColor;
    self.displayPicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(25, 508, 570, 30) pullsDown:NO];
    self.displayPicker.target = self; self.displayPicker.action = @selector(selectionChanged:);
    [self.displayPicker setAccessibilityLabel:@"対象の外部モニタ"];
    [view addSubview:self.displayPicker];
    self.percentLabel = USLabel(view, @"125%", NSMakeRect(28, 449, 180, 49), 36, YES);
    self.resolutionLabel = USLabel(view, @"", NSMakeRect(210, 450, 380, 44), 13, NO);
    self.resolutionLabel.alignment = NSTextAlignmentRight;
    self.resolutionLabel.textColor = NSColor.secondaryLabelColor;
    NSInteger saved = [NSUserDefaults.standardUserDefaults integerForKey:@"scale"];
    NSInteger value = (!self.uiTest && saved >= 100 && saved <= 200) ? saved : 125;
    self.slider = [NSSlider sliderWithValue:value minValue:100 maxValue:200 target:self action:@selector(scaleChanged:)];
    self.slider.frame = NSMakeRect(26, 411, 568, 28); self.slider.continuous = YES;
    [self.slider setAccessibilityLabel:@"表示倍率、100から200パーセント"];
    [view addSubview:self.slider];
    USLabel(view, @"100%  広く使う", NSMakeRect(28, 383, 200, 22), 12, NO);
    NSTextField *right = USLabel(view, @"200%  大きく読む", NSMakeRect(390, 383, 202, 22), 12, NO);
    right.alignment = NSTextAlignmentRight;
    self.preview = [[USPreview alloc] initWithFrame:NSMakeRect(28, 197, 564, 172)];
    self.preview.accessibilityLabel = @"文字とUIの大きさのイメージ。実際の画質ではありません。";
    [view addSubview:self.preview];
    self.statusLabel = USLabel(view, @"", NSMakeRect(28, 127, 564, 57), 13, NO);
    self.confirmationLabel = USLabel(view, @"", NSMakeRect(28, 91, 370, 34), 12, NO);
    self.confirmationLabel.textColor = NSColor.systemOrangeColor;
    self.keepButton = USButton(view, @"この設定を使う", NSMakeRect(428, 90, 167, 33), self, @selector(keep:));
    self.keepButton.hidden = YES;
    self.restoreButton = USButton(view, @"元の表示に戻す", NSMakeRect(25, 48, 165, 34), self, @selector(restore:));
    self.applyButton = USButton(view, @"HiDPIを適用", NSMakeRect(426, 48, 169, 34), self, @selector(apply:));
    self.applyButton.bezelColor = NSColor.controlAccentColor;
    NSTextField *footnote = USLabel(view, @"1%刻み・60 Hz / 適用時に画面が切り替わります。終了すると元の表示へ戻ります。", NSMakeRect(28, 15, 564, 25), 10, NO);
    footnote.textColor = NSColor.secondaryLabelColor;
    [self scaleChanged:nil];
}
- (void)show:(id)sender {
    (void)sender;
    [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible {
    (void)app; (void)visible; [self show:nil]; return YES;
}
- (void)selectionChanged:(id)sender { (void)sender; [self updateControls]; }
- (void)scaleChanged:(id)sender {
    (void)sender;
    NSInteger percent = (NSInteger)llround(self.slider.doubleValue);
    self.slider.integerValue = percent;
    USSize size = USLogicalSize(percent);
    self.percentLabel.stringValue = [NSString stringWithFormat:@"%ld%%", percent];
    self.resolutionLabel.stringValue = [NSString stringWithFormat:@"見かけ  %zu × %zu\nHiDPI描画  %zu × %zu", size.width, size.height, size.width * 2, size.height * 2];
    self.preview.percent = percent; self.preview.needsDisplay = YES;
    if (!self.uiTest) [NSUserDefaults.standardUserDefaults setInteger:percent forKey:@"scale"];
}
- (void)refresh {
    if (self.busy) return;
    NSNumber *selected = self.displayPicker.selectedItem.representedObject;
    self.displays = self.engine.displays;
    [self.displayPicker removeAllItems];
    for (USDisplay *display in self.displays) {
        [self.displayPicker addItemWithTitle:[NSString stringWithFormat:@"%@  ·  %@", display.name,
            display.supported ? @"3440 × 1440" : @"対象外の解像度"]];
        self.displayPicker.lastItem.representedObject = @(display.identifier);
        if ([selected isEqual:@(display.identifier)]) [self.displayPicker selectItem:self.displayPicker.lastItem];
    }
    if (self.displays.count == 0) [self.displayPicker addItemWithTitle:@"外部モニタが接続されていません"];
    [self updateControls];
    if (!self.engine.active && !self.pending) self.statusLabel.stringValue =
        self.displays.count ? @"対象モニタと倍率を選んで適用してください。15秒以内に確認しなければ、HiDPIを解除します。" :
        @"3440 × 1440の外部モニタを接続してください。\n接続前でも倍率と見かけの解像度を確認できます。";
}
- (void)updateControls {
    NSInteger index = self.displayPicker.indexOfSelectedItem;
    BOOL supported = index >= 0 && index < (NSInteger)self.displays.count && self.displays[index].supported;
    self.applyButton.enabled = supported && !self.busy && !self.pending;
    self.restoreButton.enabled = self.engine.active && !self.busy;
    self.slider.enabled = !self.busy && !self.pending;
    self.displayPicker.enabled = self.displays.count > 0 && !self.busy && !self.pending;
    self.keepButton.hidden = !self.pending;
}
- (void)apply:(id)sender {
    (void)sender;
    if (!self.applyButton.enabled) return;
    self.busy = YES; [self updateControls];
    self.statusLabel.stringValue = @"HiDPIモードを準備しています…";
    NSError *error = nil;
    BOOL ok = [self.engine applyTo:[self.displayPicker.selectedItem.representedObject unsignedIntValue]
        percent:self.slider.integerValue error:&error];
    self.busy = NO;
    if (ok) {
        self.pending = YES; self.deadline = NSProcessInfo.processInfo.systemUptime + 15;
        self.statusLabel.stringValue = @"文字と画面全体が正しく見えることを確認してください。\n見えない場合は操作せずに待つと、HiDPIを解除します。";
        [self show:nil]; [self tick];
    } else {
        [self refresh]; self.statusLabel.stringValue = error.localizedDescription ?: @"適用できませんでした。";
    }
    [self updateControls];
}
- (void)keep:(id)sender {
    (void)sender;
    if (!self.pending || self.busy) return;
    self.pending = NO; self.confirmationLabel.stringValue = @"";
    self.statusLabel.stringValue = [NSString stringWithFormat:@"HiDPI  %ld%% を適用中です。\nウインドウを閉じても動作を続けます。メニューバーから再表示できます。", self.engine.percent];
    [self updateControls];
}
- (void)restore:(id)sender {
    (void)sender;
    if (self.busy) return;
    self.busy = YES; self.pending = NO;
    NSError *error = nil;
    BOOL ok = [self.engine restore:&error];
    self.busy = NO; self.confirmationLabel.stringValue = @"";
    [self refresh];
    self.statusLabel.stringValue = ok ? @"HiDPIを解除し、元の通常表示に戻しました。" : error.localizedDescription;
}
- (void)tick {
    if (self.busy) return;
    if (self.engine.active && !self.engine.isHealthy) {
        [self restore:nil]; return;
    }
    if (self.pending) {
        NSInteger remaining = (NSInteger)ceil(self.deadline - NSProcessInfo.processInfo.systemUptime);
        if (remaining <= 0) { [self restore:nil]; return; }
        self.confirmationLabel.stringValue = [NSString stringWithFormat:@"あと%ld秒でHiDPIを解除します。", remaining];
    }
}
- (void)displaysChanged:(NSNotification *)notification { (void)notification; [self refresh]; }
- (void)willSleep:(NSNotification *)notification {
    (void)notification;
    if (self.engine.active) [self restore:nil];
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    if (self.busy) return NSTerminateCancel;
    [self.timer invalidate]; [self.engine restore:NULL]; return NSTerminateNow;
}
- (void)runUITest {
    // 通常のアプリと同じウインドウ・コントロールを動かす。画面設定は変更しない。
    BOOL pass = YES;
    for (NSNumber *number in @[@100, @125, @137, @200]) {
        self.slider.integerValue = number.integerValue;
        [self.slider sendAction:self.slider.action to:self.slider.target];
        pass &= [self.percentLabel.stringValue isEqual:[NSString stringWithFormat:@"%@%%", number]];
    }
    pass &= !self.engine.active && !self.restoreButton.enabled;
    if (!self.displays.count) pass &= !self.applyButton.enabled;
    self.pending = YES; self.deadline = NSProcessInfo.processInfo.systemUptime - 1;
    [self tick];
    pass &= !self.pending && !self.engine.active && self.keepButton.hidden;
    self.pending = YES; [self keep:nil];
    pass &= !self.pending && self.keepButton.hidden;
    [self refresh];
    self.slider.integerValue = 125; [self scaleChanged:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    [self.window.contentView layoutSubtreeIfNeeded];
    [self.window.contentView display];
    NSArray *args = NSProcessInfo.processInfo.arguments;
    NSUInteger index = [args indexOfObject:@"--ui-test"];
    NSString *path = args.count > index + 1 ? args[index + 1] : nil;
    if (path) {
        NSView *view = self.window.contentView;
        NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
        [view.effectiveAppearance performAsCurrentDrawingAppearance:^{
            [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
        }];
        pass &= [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
    }
    printf("UI: 倍率操作、未接続時の制御、ウインドウ描画 %s\n", pass ? "PASS" : "FAIL");
    USExitCode = pass ? 0 : 1;
    fflush(stdout); [NSApp terminate:nil];
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        USApp *delegate = [USApp new]; application.delegate = delegate;
        [application run];
    }
    return USExitCode;
}
