// 実画面を変更せず、画質調整が失敗した際の通常HiDPI復旧とUIの表示を検査する。
#define main USAppMain
#import "../Sources/App.m"
#undef main
@interface USRecoveryEngine : USDisplayEngine
@property BOOL running, loseCurrentDisplay, failRecovery, applying;
@property(copy) void (^duringRecovery)(void);
@property NSInteger restores;
@property NSInteger calls, appliedPercent;
@end
@implementation USRecoveryEngine
- (BOOL)active { return self.running; }
- (BOOL)activeUsesFilters { return NO; }
- (BOOL)isHealthy { return self.running && !self.applying; }
- (BOOL)restore:(NSError **)error { (void)error; self.restores++; self.running=NO; return YES; }
- (CGDirectDisplayID)target { return self.running ? 42 : 0; }
- (NSInteger)percent { return self.running ? self.appliedPercent : 0; }
- (NSArray<USDisplay *> *)displays {
    USDisplay *d = [USDisplay new]; d.identifier = 42; d.name = @"復旧試験"; d.supported = YES; return @[d];
}
- (BOOL)applyTo:(CGDirectDisplayID)target percent:(NSInteger)percent error:(NSError **)error {
    (void)target; self.calls++;
    if (self.useFilters || self.failRecovery) {
        if (self.loseCurrentDisplay) self.running = NO;
        if (error) *error = [NSError errorWithDomain:@"試験" code:1 userInfo:@{NSLocalizedDescriptionKey:@"画質調整の失敗を再現"}];
        return NO;
    }
    self.running = YES; self.appliedPercent = percent; self.applying=YES;
    if(self.duringRecovery)self.duringRecovery();
    self.applying=NO; return self.running;
}
@end
static int failures;
static void check(BOOL value, const char *name) { printf("%s: %s\n", value ? "PASS" : "FAIL", name); if(!value)failures++; }
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    for (NSInteger scenario=0;scenario<4;scenario++) {
        USApp *app = [USApp new]; app.uiTest = YES;
        USRecoveryEngine *engine = [USRecoveryEngine new]; app.engine = engine;
        [app createWindow]; [app refresh];
        engine.running = scenario != 0; engine.appliedPercent = 125;
        engine.loseCurrentDisplay = scenario >= 2; engine.failRecovery = scenario == 3;
        app.slider.integerValue = 150;
        app.qualityCheckbox.state = NSControlStateValueOn; [app qualityChanged:nil];
        app.undoAvailable = YES; app.deadline = NSProcessInfo.processInfo.systemUptime+10;
        __weak USApp *weakApp=app; engine.duringRecovery=^{ [weakApp tick]; };
        [app apply:nil];
        check(engine.restores==0, "通常HiDPIへ復旧中の監視処理が表示を解除しない");
        if(scenario==0) check(engine.running && engine.calls==2 && engine.percent==150, "初回の画質調整失敗でも通常HiDPIが動作する");
        if(scenario==1) check(engine.running && engine.calls==1 && engine.percent==125 && app.undoAvailable, "許可不足で既存表示を壊さず取り消し期限を保持する");
        if(scenario==2) check(engine.running && engine.calls==2 && engine.percent==125 && app.slider.integerValue==125, "描画開始失敗で失った変更前の倍率を通常HiDPIで復旧する");
        if(scenario==3) check(!engine.running && !app.undoAvailable && [app.statusLabel.stringValue containsString:@"復旧にも失敗"], "復旧失敗を成功と表示しない");
        check(app.qualityCheckbox.state==NSControlStateValueOff && app.applyButton.enabled, "試験モードの失敗後も通常操作へ戻れる");
        [app.window close];
    }
    return failures ? 1 : 0;
} }
