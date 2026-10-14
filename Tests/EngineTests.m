#import "DisplayEngine.h"
#import <math.h>

// 実モニタがない環境用。列挙だけを差し替え、作成・倍率変更・ミラー・復元は実APIで検証する。
@interface USTestEngine : USDisplayEngine
@property CGDirectDisplayID simulatedTarget;
@end
@implementation USTestEngine
- (NSArray<USDisplay *> *)displays {
    USDisplay *display = [USDisplay new];
    display.identifier = self.simulatedTarget; display.name = @"検証用3440×1440"; display.supported = YES;
    return @[display];
}
@end

static int failures = 0;
static void check(BOOL condition, NSString *name) {
    printf("%s: %s\n", condition ? "PASS" : "FAIL", name.UTF8String);
    if (!condition) failures++;
}
static void settle(void) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.6]];
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        BOOL sizes = YES;
        for (NSInteger percent = 100; percent <= 200; percent++) {
            USSize size = USLogicalSize(percent);
            sizes &= fabs(size.width - 344000.0 / percent) <= 0.5;
            sizes &= fabs(size.height - 144000.0 / percent) <= 0.5;
            sizes &= size.width >= 1720 && size.width <= 3440 && size.height >= 720 && size.height <= 1440;
        }
        check(sizes, @"全101倍率の解像度・丸め誤差・範囲");
        NSArray *before = USOnlineDisplays();
        NSMutableDictionary<NSNumber *, NSValue *> *originalBounds = [NSMutableDictionary dictionary];
        NSMutableDictionary *originalModes = [NSMutableDictionary dictionary];
        for (NSNumber *number in before) {
            originalBounds[number] = [NSValue valueWithRect:NSRectFromCGRect(CGDisplayBounds(number.unsignedIntValue))];
            CGDisplayModeRef mode = CGDisplayCopyDisplayMode(number.unsignedIntValue);
            if (mode) originalModes[number] = CFBridgingRelease(mode);
        }
        USDisplayEngine *engine = [USDisplayEngine new];
        NSError *error = nil;
        check(![engine applyTo:CGMainDisplayID() percent:99 error:&error], @"範囲外倍率を拒否");
        for (NSNumber *number in before) {
            if (CGDisplayIsBuiltin(number.unsignedIntValue))
                check(![engine applyTo:number.unsignedIntValue percent:125 error:&error], @"内蔵画面への適用を拒否");
        }
        check(![engine applyTo:UINT32_MAX percent:125 error:&error], @"未接続画面への適用を拒否");
        check([engine restore:&error] && [engine restore:&error], @"未適用状態の復元は何度実行しても安全");
        if (argc > 1 && strcmp(argv[1], "--virtual") == 0) {
            @autoreleasepool {
                id physical = USCreateVirtual((USSize){3440, 1440}, NO, @"UltraScale 検証用モニタ", &error);
                CGDirectDisplayID target = USVirtualID(physical);
                check(physical && USWaitForMode(target, (USSize){3440,1440}, NO), @"検証用3440×1440画面を作成");
                if (physical) {
                    USTestEngine *testEngine = [USTestEngine new]; testEngine.simulatedTarget = target;
                    for (NSNumber *percent in @[@100, @125, @137, @200]) {
                        error = nil;
                        BOOL ok = [testEngine applyTo:target percent:percent.integerValue error:&error];
                        check(ok && testEngine.isHealthy, [NSString stringWithFormat:@"%@%% の2倍描画とミラー接続", percent]);
                        if (error) fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
                        check([testEngine restore:&error], @"元のモード・配置の復元API");
                        settle();
                        CGDisplayModeRef restored = CGDisplayCopyDisplayMode(target);
                        check(restored && CGDisplayModeGetWidth(restored) == 3440 && CGDisplayModeGetHeight(restored) == 1440 && !CGDisplayMirrorsDisplay(target), @"復元後のモードとミラー解除を再取得して確認");
                        if (restored) CFRelease(restored);
                    }
                    check([testEngine applyTo:target percent:125 error:&error] && [testEngine applyTo:target percent:150 error:&error], @"適用中の倍率変更");
                    check([testEngine restore:&error], @"連続適用後の復元");
                    if (error) fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
                    check([testEngine applyTo:target percent:125 error:&error], @"切断検証前の適用");
                    physical = nil;
                    settle();
                    check(!testEngine.isHealthy, @"ミラー先の消失を検出");
                    error = nil;
                    check([testEngine restore:&error] && !testEngine.active, @"切断後に仮想HiDPI画面を解放");
                    if (error) fprintf(stderr, "%s; target=%u online=%s\n", error.localizedDescription.UTF8String, target, USOnlineDisplays().description.UTF8String);
                }
                physical = nil;
            }
            settle();
            check([[NSSet setWithArray:USOnlineDisplays()] isEqualToSet:[NSSet setWithArray:before]], @"検証用仮想画面がすべて終了");
            BOOL unchanged = YES;
            for (NSNumber *number in before) {
                unchanged &= NSEqualRects(originalBounds[number].rectValue, NSRectFromCGRect(CGDisplayBounds(number.unsignedIntValue)));
                CGDisplayModeRef mode = CGDisplayCopyDisplayMode(number.unsignedIntValue);
                CGDisplayModeRef original = (__bridge CGDisplayModeRef)originalModes[number];
                unchanged &= mode && original && CGDisplayModeGetWidth(mode) == CGDisplayModeGetWidth(original) &&
                    CGDisplayModeGetHeight(mode) == CGDisplayModeGetHeight(original) &&
                    CGDisplayModeGetPixelWidth(mode) == CGDisplayModeGetPixelWidth(original);
                if (mode) CFRelease(mode);
            }
            check(unchanged, @"既存画面の配置・解像度が検証前と一致");
        }
        printf("結果: %d件の失敗\n", failures);
        return failures ? 1 : 0;
    }
}
