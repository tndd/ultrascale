#import "DisplayEngine.h"
static BOOL captureAllowed, accessibilityAllowed;
static int requests;
static bool USFakeCapture(void) { return captureAllowed; }
static Boolean USFakeAccessibility(void) { return accessibilityAllowed; }
static bool __attribute__((unused)) USFakeRequestCapture(void) { requests++; return false; }
static Boolean __attribute__((unused)) USFakeRequestAccessibility(CFDictionaryRef options) { (void)options; requests++; return false; }
#define CGPreflightScreenCaptureAccess USFakeCapture
#define AXIsProcessTrusted USFakeAccessibility
#define CGRequestScreenCaptureAccess USFakeRequestCapture
#define AXIsProcessTrustedWithOptions USFakeRequestAccessibility
#import "../Sources/DisplayEngine.m"
int main(void) { @autoreleasepool {
    BOOL pass = YES;
    for (int state=0;state<4;state++) {
        captureAllowed = (state&1)!=0; accessibilityAllowed = (state&2)!=0; requests=0;
        NSError *error=nil;
        BOOL allowed = USCheckFilterPermissions(&error);
        pass &= allowed==(captureAllowed&&accessibilityAllowed) && requests==0;
        if (!allowed) pass &= error!=nil && (!captureAllowed || [error.localizedDescription containsString:@"アクセシビリティ"]) &&
            (!accessibilityAllowed || [error.localizedDescription containsString:@"画面収録"]);
    }
    printf("%s: 許可4状態の判定でダイアログを自動要求しない\n",pass?"PASS":"FAIL");
    return pass?0:1;
}}
