#import "DisplayEngine.h"

static int USExitCode = 0;
// 実クリックの検証中もAppKitへイベントを渡す。NSRunLoopの待機だけでは
// マウスイベントが未処理のまま残り、正常な入力まで失敗と判定してしまう。
static void USRunApplicationFor(NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (deadline.timeIntervalSinceNow > 0) {
        NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
            untilDate:[NSDate dateWithTimeIntervalSinceNow:MIN(0.02, deadline.timeIntervalSinceNow)]
            inMode:NSDefaultRunLoopMode dequeue:YES];
        if (event) [NSApp sendEvent:event];
        [NSApp updateWindows];
    }
}
// AppKitが捕捉した例外も診断できるようにし、テストでは成功扱いにしない。
@interface USApplication : NSApplication
@end
@implementation USApplication
- (void)reportException:(NSException *)exception {
    fprintf(stderr, "UltraScale: %s: %s\n", exception.name.UTF8String, exception.reason.UTF8String);
    fflush(stderr);
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--ui-test"] || [NSProcessInfo.processInfo.arguments containsObject:@"--stream-test"]) exit(1);
    [super reportException:exception];
}
@end
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

@interface USFilterPattern : NSView
@end
@implementation USFilterPattern
- (void)drawRect:(NSRect)rect {
    (void)rect; [NSColor.whiteColor setFill]; NSRectFill(self.bounds);
    [NSColor.systemOrangeColor setFill]; NSRectFill(NSMakeRect(0,self.bounds.size.height-60,self.bounds.size.width,60));
    [NSColor.systemBlueColor setFill]; NSRectFill(NSMakeRect(0,0,self.bounds.size.width,60));
    [@"上 / TOP — 日本語の細い文字 AaBb 0123456789" drawAtPoint:NSMakePoint(24,self.bounds.size.height-40)
        withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:20],NSForegroundColorAttributeName:NSColor.blackColor}];
    [@"下 / BOTTOM — カーソルとクリックも確認" drawAtPoint:NSMakePoint(24,20)
        withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:20],NSForegroundColorAttributeName:NSColor.whiteColor}];
    for (int x=24;x<800;x+=4) { [NSColor.blackColor setFill]; NSRectFill(NSMakeRect(x,220,1,140)); }
}
@end

@interface USApp : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property(strong) NSWindow *window;
@property(strong) USDisplayEngine *engine;
@property(strong) NSPopUpButton *displayPicker;
@property(strong) NSSlider *slider;
@property(strong) NSTextField *percentLabel, *resolutionLabel, *statusLabel, *undoLabel;
@property(strong) USPreview *preview;
@property(strong) NSButton *applyButton, *rollbackButton;
@property(strong) NSButton *menuBarIconCheckbox, *qualityCheckbox;
@property(strong) NSPopUpButton *filterPicker;
@property(strong) NSSlider *sharpnessSlider;
@property(strong) NSTextField *sharpnessLabel;
@property BOOL previousUseFilters, testClickReceived;
@property(strong) NSStatusItem *statusItem;
@property(strong) NSMenu *iconMenu;
@property(copy) NSString *iconName;
@property(strong) NSTimer *timer;
@property(copy) NSArray<USDisplay *> *displays;
@property BOOL busy, undoAvailable, uiTest;
@property NSTimeInterval deadline;
@property CGDirectDisplayID previousTarget;
@property NSInteger previousPercent;
- (void)show:(id)sender;
- (void)refresh;
- (void)scaleChanged:(id)sender;
- (void)apply:(id)sender;
- (void)restore:(id)sender;
- (void)rollback:(id)sender;
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
    BOOL streamTest = [NSProcessInfo.processInfo.arguments containsObject:@"--stream-test"];
    self.uiTest = streamTest || [NSProcessInfo.processInfo.arguments containsObject:@"--ui-test"];
    if (self.uiTest && !streamTest) [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"showMenuBarIcon":@YES}];
    [self createMenu];
    NSString *savedIcon = [NSUserDefaults.standardUserDefaults stringForKey:@"iconName"];
    [self useIconNamed:self.uiTest ? @"IconBlue" : (savedIcon ?: @"IconGreen")];
    [self createWindow];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(displaysChanged:)
        name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(willSleep:)
        name:NSWorkspaceWillSleepNotification object:nil];
    self.timer = [NSTimer timerWithTimeInterval:0.5 target:self selector:@selector(tick) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self refresh]; [self show:nil];
    // 同期的な待機中もメインキューへ届く仮想画面・映像の完了通知を処理する。
    // メインキューのブロック内から開始すると、そのキューを待つ処理が進まない。
    if (self.uiTest) [self performSelector:streamTest ? @selector(runStreamTest) : @selector(runUITest)
        withObject:nil afterDelay:0.5];
}
- (void)createMenu {
    NSMenu *menu = [NSMenu new];
    NSMenuItem *app = [NSMenuItem new]; [menu addItem:app];
    app.submenu = [NSMenu new];
    self.iconMenu = [NSMenu new];
    NSMenuItem *iconChoice = [app.submenu addItemWithTitle:@"Dockアイコン" action:NULL keyEquivalent:@""];
    iconChoice.submenu = self.iconMenu;
    for (NSArray *choice in @[@[@"青（標準）", @"IconBlue"], @[@"緑（予備）", @"IconGreen"]]) {
        NSMenuItem *item = [self.iconMenu addItemWithTitle:choice[0] action:@selector(changeIcon:) keyEquivalent:@""];
        item.target = self; item.representedObject = choice[1];
    }
    [app.submenu addItem:NSMenuItem.separatorItem];
    [app.submenu addItemWithTitle:@"UltraScaleを終了" action:@selector(terminate:) keyEquivalent:@"q"];
    NSMenuItem *window = [NSMenuItem new]; [menu addItem:window];
    window.title = @"ウインドウ"; window.submenu = [NSMenu new];
    NSMenuItem *show = [window.submenu addItemWithTitle:@"UltraScaleを表示" action:@selector(show:) keyEquivalent:@"0"];
    show.target = self;
    NSApp.mainMenu = menu;
    [self setMenuBarIconVisible:self.uiTest || [NSUserDefaults.standardUserDefaults boolForKey:@"showMenuBarIcon"]];
}
- (void)setMenuBarIconVisible:(BOOL)visible {
    if (!visible) {
        if (self.statusItem) [NSStatusBar.systemStatusBar removeStatusItem:self.statusItem];
        self.statusItem = nil;
        return;
    }
    if (self.statusItem) return;
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
- (void)menuBarIconChanged:(NSButton *)sender {
    BOOL visible = sender.state == NSControlStateValueOn;
    [self setMenuBarIconVisible:visible];
    if (!self.uiTest) [NSUserDefaults.standardUserDefaults setBool:visible forKey:@"showMenuBarIcon"];
}
- (BOOL)useIconNamed:(NSString *)name {
    if (![@[@"IconBlue", @"IconGreen"] containsObject:name]) name = @"IconBlue";
    NSString *path = [NSBundle.mainBundle pathForResource:name ofType:@"icns"];
    NSImage *icon = path ? [[NSImage alloc] initWithContentsOfFile:path] : nil;
    if (!icon) return NO;
    NSApp.applicationIconImage = icon;
    self.iconName = name;
    for (NSMenuItem *item in self.iconMenu.itemArray)
        item.state = [item.representedObject isEqual:name] ? NSControlStateValueOn : NSControlStateValueOff;
    return YES;
}
- (void)changeIcon:(NSMenuItem *)sender {
    if ([self useIconNamed:sender.representedObject] && !self.uiTest)
        [NSUserDefaults.standardUserDefaults setObject:self.iconName forKey:@"iconName"];
}
- (void)createWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 846)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"UltraScale"; self.window.delegate = self;
    self.window.releasedWhenClosed = NO;
    self.window.contentView = [[USBackground alloc] initWithFrame:NSMakeRect(0, 0, 620, 846)];
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
    self.undoLabel = USLabel(view, @"", NSMakeRect(28, 91, 370, 34), 12, NO);
    self.undoLabel.textColor = NSColor.systemOrangeColor;
    self.rollbackButton = USButton(view, @"変更前の表示に戻す", NSMakeRect(25, 48, 215, 34), self, @selector(rollback:));
    self.applyButton = USButton(view, @"HiDPIを適用", NSMakeRect(426, 48, 169, 34), self, @selector(apply:));
    self.applyButton.bezelColor = NSColor.controlAccentColor;
    NSTextField *footnote = USLabel(view, @"1%刻み・60 Hz / 適用時に画面が切り替わります。終了すると元の表示へ戻ります。", NSMakeRect(28, 15, 564, 25), 10, NO);
    footnote.textColor = NSColor.secondaryLabelColor;
    for (NSView *item in view.subviews) {
        NSRect frame = item.frame; frame.origin.y += 196; item.frame = frame;
    }
    self.menuBarIconCheckbox = [NSButton checkboxWithTitle:@"メニューバーにアイコンを表示"
        target:self action:@selector(menuBarIconChanged:)];
    self.menuBarIconCheckbox.frame = NSMakeRect(28, 15, 300, 24);
    self.menuBarIconCheckbox.state = self.statusItem ? NSControlStateValueOn : NSControlStateValueOff;
    [view addSubview:self.menuBarIconCheckbox];
    self.qualityCheckbox = [NSButton checkboxWithTitle:@"画質調整モード（試験）" target:self action:@selector(qualityChanged:)];
    self.qualityCheckbox.frame = NSMakeRect(28, 165, 500, 24);
    self.qualityCheckbox.state = !self.uiTest && [NSUserDefaults.standardUserDefaults boolForKey:@"useFilters"] ? NSControlStateValueOn : NSControlStateValueOff;
    [view addSubview:self.qualityCheckbox];
    USLabel(view, @"縮小フィルタ", NSMakeRect(28, 123, 95, 24), 12, NO);
    self.filterPicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(120, 119, 180, 30) pullsDown:NO];
    [self.filterPicker addItemsWithTitles:@[@"バイリニア", @"バイキュービック", @"Lanczos"]];
    self.filterPicker.target = self; self.filterPicker.action = @selector(qualityChanged:);
    self.filterPicker.accessibilityLabel = @"縮小フィルタ";
    NSInteger filter = [NSUserDefaults.standardUserDefaults objectForKey:@"filter"] && !self.uiTest ? [NSUserDefaults.standardUserDefaults integerForKey:@"filter"] : 2;
    [self.filterPicker selectItemAtIndex:MAX(0, MIN(2, filter))]; [view addSubview:self.filterPicker];
    self.sharpnessLabel = USLabel(view, @"シャープネス 25%", NSMakeRect(325, 151, 260, 22), 12, NO);
    double sharpness = [NSUserDefaults.standardUserDefaults objectForKey:@"sharpness"] && !self.uiTest ? [NSUserDefaults.standardUserDefaults doubleForKey:@"sharpness"] : 25;
    self.sharpnessSlider = [NSSlider sliderWithValue:MAX(0, MIN(100, sharpness)) minValue:0 maxValue:100 target:self action:@selector(qualityChanged:)];
    self.sharpnessSlider.frame = NSMakeRect(323, 121, 270, 26); self.sharpnessSlider.continuous = YES;
    self.sharpnessSlider.accessibilityLabel = @"シャープネス、0から100パーセント"; [view addSubview:self.sharpnessSlider];
    NSTextField *hint = USLabel(view, @"画面収録とアクセシビリティの許可が必要です。モード変更は「HiDPIを適用」。画質調整中のフィルタと強度は即座に反映します。", NSMakeRect(28, 65, 564, 45), 11, NO);
    hint.textColor = NSColor.secondaryLabelColor;
    [self qualityChanged:nil];
    [self scaleChanged:nil];
}
- (void)qualityChanged:(id)sender {
    (void)sender;
    self.engine.useFilters = self.qualityCheckbox.state == NSControlStateValueOn;
    self.engine.filter = self.filterPicker.indexOfSelectedItem;
    self.engine.sharpness = self.sharpnessSlider.doubleValue / 100.0;
    self.sharpnessLabel.stringValue = [NSString stringWithFormat:@"シャープネス %.0f%%", self.sharpnessSlider.doubleValue];
    self.filterPicker.enabled = self.engine.useFilters && !self.busy;
    self.sharpnessSlider.enabled = self.engine.useFilters && !self.busy;
    if (!self.uiTest) {
        [NSUserDefaults.standardUserDefaults setBool:self.engine.useFilters forKey:@"useFilters"];
        [NSUserDefaults.standardUserDefaults setInteger:self.engine.filter forKey:@"filter"];
        [NSUserDefaults.standardUserDefaults setDouble:self.sharpnessSlider.doubleValue forKey:@"sharpness"];
    }
}
- (void)show:(id)sender {
    (void)sender;
    if (self.engine.activeUsesFilters) {
        NSScreen *destination = nil;
        for (NSScreen *screen in NSScreen.screens) {
            unsigned int identifier = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
            if (CGDisplayIsBuiltin(identifier)) { destination = screen; break; }
            if (identifier == self.engine.virtualID) destination = screen;
        }
        if (destination) {
            NSRect frame = self.window.frame, available = destination.visibleFrame;
            frame.origin = NSMakePoint(NSMidX(available) - frame.size.width / 2, NSMidY(available) - frame.size.height / 2);
            [self.window setFrame:frame display:NO];
        }
    }
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
    if (!self.engine.active && !self.undoAvailable) self.statusLabel.stringValue =
        self.displays.count ? @"対象モニタと倍率を選んで適用してください。適用後15秒間は変更を取り消せます。" :
        @"3440 × 1440の外部モニタを接続してください。\n接続前でも倍率と見かけの解像度を確認できます。";
}
- (void)updateControls {
    NSInteger index = self.displayPicker.indexOfSelectedItem;
    BOOL supported = index >= 0 && index < (NSInteger)self.displays.count && self.displays[index].supported;
    self.applyButton.enabled = supported && !self.busy;
    self.rollbackButton.enabled = self.undoAvailable && !self.busy;
    self.qualityCheckbox.enabled = !self.busy;
    self.filterPicker.enabled = self.engine.useFilters && !self.busy;
    self.sharpnessSlider.enabled = self.engine.useFilters && !self.busy;
    self.slider.enabled = !self.busy;
    self.displayPicker.enabled = self.displays.count > 0 && !self.busy;
}
- (void)apply:(id)sender {
    (void)sender;
    if (!self.applyButton.enabled) return;
    CGDirectDisplayID previousTarget = self.engine.active ? self.engine.target : 0;
    NSInteger previousPercent = self.engine.active ? self.engine.percent : 0;
    BOOL previousUseFilters = self.engine.activeUsesFilters;
    self.busy = YES; [self updateControls];
    self.statusLabel.stringValue = @"HiDPIモードを準備しています…";
    NSError *error = nil;
    BOOL ok = [self.engine applyTo:[self.displayPicker.selectedItem.representedObject unsignedIntValue]
        percent:self.slider.integerValue error:&error];
    if (ok) {
        self.busy = NO;
        self.previousTarget = previousTarget; self.previousPercent = previousPercent; self.previousUseFilters = previousUseFilters;
        self.undoAvailable = YES; self.deadline = NSProcessInfo.processInfo.systemUptime + 15;
        [self updateAppliedStatus];
        [self show:nil]; [self tick];
    } else {
        NSString *failure = error.localizedDescription ?: @"適用できませんでした。";
        // 試験機能が失敗しても、通常のHiDPIを使える状態に戻す。
        if (!self.engine.active && self.engine.useFilters) {
            self.engine.useFilters = NO;
            NSError *recoveryError = nil;
            BOOL recovered = [self.engine applyTo:previousTarget ?: [self.displayPicker.selectedItem.representedObject unsignedIntValue]
                percent:previousPercent ?: self.slider.integerValue error:&recoveryError];
            if (!recovered) failure = [failure stringByAppendingFormat:@"\n通常HiDPIの復旧にも失敗: %@", recoveryError.localizedDescription];
        }
        self.qualityCheckbox.state = self.engine.activeUsesFilters ? NSControlStateValueOn : NSControlStateValueOff;
        [self qualityChanged:nil];
        if (!self.engine.active) { self.undoAvailable = NO; self.undoLabel.stringValue = @""; }
        if (self.engine.active) { self.slider.integerValue = self.engine.percent; [self scaleChanged:nil]; }
        self.busy = NO;
        [self refresh];
        self.statusLabel.stringValue = self.engine.active ? [failure stringByAppendingFormat:@"\n%@ %ld%% は動作中です。", self.engine.activeUsesFilters ? @"画質調整" : @"通常HiDPI", self.engine.percent] : failure;
    }
    [self updateControls];
}
- (void)updateAppliedStatus {
    self.statusLabel.stringValue = [NSString stringWithFormat:@"HiDPI  %ld%%%@ を適用中です。\nウインドウを閉じても動作を続けます。DockやLaunchpadから再表示できます。", self.engine.percent, self.engine.activeUsesFilters ? @"（画質調整）" : @""];
}
- (void)rollback:(id)sender {
    (void)sender;
    if (!self.undoAvailable || self.busy) return;
    if (NSProcessInfo.processInfo.systemUptime >= self.deadline) { [self tick]; return; }
    self.busy = YES; self.undoAvailable = NO; [self updateControls];
    NSError *error = nil;
    if (self.previousPercent > 0) self.engine.useFilters = self.previousUseFilters;
    BOOL ok = self.previousPercent > 0 ?
        [self.engine applyTo:self.previousTarget percent:self.previousPercent error:&error] :
        [self.engine restore:&error];
    self.busy = NO; self.undoLabel.stringValue = @"";
    if (ok && self.previousPercent > 0) {
        self.slider.integerValue = self.previousPercent; [self scaleChanged:nil];
        self.qualityCheckbox.state = self.previousUseFilters ? NSControlStateValueOn : NSControlStateValueOff;
        [self qualityChanged:nil];
    }
    [self refresh];
    if (ok && self.engine.active) [self updateAppliedStatus];
    else self.statusLabel.stringValue = ok ? @"変更を取り消し、変更前の通常表示に戻しました。" : error.localizedDescription;
    self.previousTarget = 0; self.previousPercent = 0;
}
- (void)restore:(id)sender {
    (void)sender;
    if (self.busy) return;
    self.busy = YES; self.undoAvailable = NO;
    self.previousTarget = 0; self.previousPercent = 0;
    NSError *error = nil;
    BOOL ok = [self.engine restore:&error];
    self.busy = NO; self.undoLabel.stringValue = @"";
    [self refresh];
    self.statusLabel.stringValue = ok ? @"HiDPIを解除し、元の通常表示に戻しました。" : error.localizedDescription;
}
- (void)tick {
    if (self.busy) return;
    if (self.engine.active && !self.engine.isHealthy) {
        [self restore:nil]; return;
    }
    if (self.undoAvailable) {
        NSInteger remaining = (NSInteger)ceil(self.deadline - NSProcessInfo.processInfo.systemUptime);
        if (remaining <= 0) {
            self.undoAvailable = NO; self.previousTarget = 0; self.previousPercent = 0;
            self.undoLabel.stringValue = @""; [self updateControls]; return;
        }
        self.undoLabel.stringValue = [NSString stringWithFormat:@"変更を取り消せます（あと%ld秒）", remaining];
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
- (void)testPatternClicked:(NSButton *)sender { self.testClickReceived = YES; sender.title = @"クリックを確認"; }
- (void)runStreamTest {
    NSArray *args = NSProcessInfo.processInfo.arguments;
    NSUInteger index = [args indexOfObject:@"--stream-test"];
    NSString *directory = args.count > index+1 ? args[index+1] : nil;
    BOOL browserComparison = [args containsObject:@"--browser"];
    if (browserComparison) { self.slider.integerValue = 120; [self scaleChanged:nil]; }
    NSError *error = nil; BOOL pass = directory != nil;
    NSWindow *sample = nil;
    self.qualityCheckbox.state = NSControlStateValueOn; [self qualityChanged:nil];
    self.busy = YES;
    pass &= [self.engine applyTo:[self.displayPicker.selectedItem.representedObject unsignedIntValue]
        percent:self.slider.integerValue error:&error];
    self.busy = NO;
    pass &= self.engine.activeUsesFilters && self.engine.isHealthy;
    if (pass) {
        NSScreen *source = nil;
        for (NSScreen *screen in NSScreen.screens) if ([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == self.engine.virtualID) source = screen;
        if (!source) pass = NO;
        else {
            if (!browserComparison) {
            NSRect frame = NSMakeRect(source.frame.origin.x + 200, source.frame.origin.y + 220, 900, 500);
            sample = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
            sample.releasedWhenClosed = NO; sample.title = @"UltraScale 画質と入力の実機検証";
            [sample setFrame:NSMakeRect(frame.origin.x,frame.origin.y,900,528) display:NO];
            sample.contentView = [[USFilterPattern alloc] initWithFrame:NSMakeRect(0,0,900,500)];
            NSButton *button = USButton(sample.contentView,@"クリックを試す",NSMakeRect(25,100,240,40),self,@selector(testPatternClicked:));
            [sample makeKeyAndOrderFront:nil];
            USRunApplicationFor(1);
            CGEventRef original = CGEventCreate(NULL); CGPoint originalPoint = CGEventGetLocation(original); CFRelease(original);
            NSPoint location = [sample convertPointToScreen:NSMakePoint(NSMidX(button.frame),NSMidY(button.frame))];
            CGFloat mainTop = 0;
            for (NSScreen *screen in NSScreen.screens) if ([screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue] == CGMainDisplayID()) mainTop = NSMaxY(screen.frame);
            CGPoint point = CGPointMake(location.x,mainTop-location.y);
            CGWarpMouseCursorPosition(point);
            for (NSNumber *type in @[@(kCGEventLeftMouseDown),@(kCGEventLeftMouseUp)]) {
                CGEventRef event = CGEventCreateMouseEvent(NULL,type.unsignedIntValue,point,kCGMouseButtonLeft); CGEventPost(kCGHIDEventTap,event); CFRelease(event);
            }
            USRunApplicationFor(0.5);
            CGWarpMouseCursorPosition(originalPoint); pass &= self.testClickReceived;
            } else USRunApplicationFor(2);
            [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
            for (NSInteger filter=0;filter<3;filter++) {
                self.engine.filter = filter; self.engine.sharpness = 0;
                USRunApplicationFor(0.3);
                pass &= [self.engine writeFilteredSnapshotTo:[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"stream-%ld.png",filter]] error:&error];
                pass &= self.engine.isHealthy;
            }
            self.engine.filter = 2; self.engine.sharpness = 0.25;
            USRunApplicationFor(0.3);
            pass &= [self.engine writeFilteredSnapshotTo:[directory stringByAppendingPathComponent:@"stream-sharp25.png"] error:&error];
            USRunApplicationFor(16);
            BOOL presented = NO;
            NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID));
            for (NSDictionary *window in windows) {
                CGRect bounds = CGRectZero;
                if ([window[(__bridge NSString *)kCGWindowOwnerPID] intValue] == NSProcessInfo.processInfo.processIdentifier &&
                    CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)window[(__bridge NSString *)kCGWindowBounds], &bounds) &&
                    CGRectEqualToRect(bounds, CGDisplayBounds(self.engine.target))) presented = YES;
            }
            pass &= self.engine.capturedFrames > 0 && self.engine.isHealthy && presented;
            printf("実機ストリーム: frames=%lu input=%s presentation=%s\n",(unsigned long)self.engine.capturedFrames,browserComparison ? "未検証（ブラウザ比較）" : (self.testClickReceived ? "PASS" : "FAIL"),presented ? "PASS" : "FAIL");
        }
    }
    if (error) fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);
    [sample close]; pass &= [self.engine restore:&error];
    printf("実機ストリーム検証: %s\n",pass ? "PASS" : "FAIL");
    USExitCode = pass ? 0 : 1; fflush(stdout); exit(USExitCode);
}
- (void)runUITest {
    // 通常のアプリと同じウインドウ・コントロールを動かす。画面設定は変更しない。
    BOOL pass = YES;
    pass &= self.statusItem != nil && self.menuBarIconCheckbox.state == NSControlStateValueOn;
    [self.menuBarIconCheckbox performClick:nil];
    pass &= self.statusItem == nil && self.menuBarIconCheckbox.state == NSControlStateValueOff;
    [self.window performClose:nil];
    [self applicationShouldHandleReopen:NSApp hasVisibleWindows:NO];
    pass &= self.window.visible && self.statusItem == nil;
    [self.menuBarIconCheckbox performClick:nil];
    pass &= self.statusItem != nil && self.menuBarIconCheckbox.state == NSControlStateValueOn;
    pass &= [self.iconName isEqual:@"IconBlue"];
    [self.iconMenu performActionForItemAtIndex:1];
    pass &= [self.iconName isEqual:@"IconGreen"] && [self.iconMenu itemAtIndex:1].state == NSControlStateValueOn;
    [self.iconMenu performActionForItemAtIndex:0];
    pass &= [self.iconName isEqual:@"IconBlue"] && [self.iconMenu itemAtIndex:0].state == NSControlStateValueOn;
    pass &= [self useIconNamed:@"invalid"] && [self.iconName isEqual:@"IconBlue"];
    for (NSNumber *number in @[@100, @125, @137, @200]) {
        self.slider.integerValue = number.integerValue;
        [self.slider sendAction:self.slider.action to:self.slider.target];
        pass &= [self.percentLabel.stringValue isEqual:[NSString stringWithFormat:@"%@%%", number]];
    }
    [self.qualityCheckbox performClick:nil];
    pass &= self.engine.useFilters && self.filterPicker.enabled && self.sharpnessSlider.enabled;
    [self.filterPicker selectItemAtIndex:1]; [self.filterPicker sendAction:self.filterPicker.action to:self.filterPicker.target];
    self.sharpnessSlider.doubleValue = 75; [self.sharpnessSlider sendAction:self.sharpnessSlider.action to:self.sharpnessSlider.target];
    pass &= self.engine.filter == 1 && fabs(self.engine.sharpness - 0.75) < 0.0001;
    [self.qualityCheckbox performClick:nil];
    pass &= !self.engine.useFilters && !self.filterPicker.enabled && !self.sharpnessSlider.enabled;
    [self.filterPicker selectItemAtIndex:2]; self.sharpnessSlider.doubleValue = 25; [self qualityChanged:nil];
    pass &= !self.engine.active && !self.rollbackButton.enabled;
    if (!self.displays.count) pass &= !self.applyButton.enabled;
    NSString *statusBeforeExpiration = self.statusLabel.stringValue;
    self.undoAvailable = YES; self.deadline = NSProcessInfo.processInfo.systemUptime - 1;
    [self tick];
    pass &= !self.undoAvailable && !self.engine.active && !self.rollbackButton.enabled;
    pass &= [self.statusLabel.stringValue isEqual:statusBeforeExpiration];
    self.undoAvailable = YES; self.deadline = NSProcessInfo.processInfo.systemUptime + 15;
    [self updateControls]; [self.rollbackButton performClick:nil];
    pass &= !self.undoAvailable && !self.rollbackButton.enabled && !self.engine.active;
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
    printf("UI: 倍率操作、未接続時の制御、アイコン切り替え、メニューバーの表示切り替え・再表示、取り消し操作・期限切れ、フィルタ・シャープネス操作、ウインドウ描画 %s\n", pass ? "PASS" : "FAIL");
    USExitCode = pass ? 0 : 1;
    fflush(stdout); exit(USExitCode);
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *application = USApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        USApp *delegate = [USApp new]; application.delegate = delegate;
        [application run];
    }
    return USExitCode;
}
