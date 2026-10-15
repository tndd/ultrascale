#import <Cocoa/Cocoa.h>
#import <dlfcn.h>
#import <objc/message.h>
// 自プロセスのフィルタ生成・設定・解放だけを調べる。画面への適用や権限要求はしない。
// 古いCGSPrivate.hの宣言と現行SkyLightの逆アセンブルを照合した。現行ハンドルは32bit。
// https://github.com/nocturneapp/nocturne/blob/master/CGSPrivate.h
int main(void) {@autoreleasepool {
    [NSApplication sharedApplication];
    void *lib=dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",RTLD_LAZY);
    if(!lib){puts("{\"symbols_available\":false}");return 2;}
    int (*connection)(void)=dlsym(lib,"SLSMainConnectionID");
    int (*create)(int,CFStringRef,uint32_t *)=dlsym(lib,"SLSNewCIFilterByName");
    int (*set)(int,uint32_t,CFDictionaryRef)=dlsym(lib,"SLSSetCIFilterValuesFromDictionary");
    int (*releaseFilter)(int,uint32_t)=dlsym(lib,"SLSReleaseCIFilter");
    if(!connection||!create||!set||!releaseFilter){puts("{\"symbols_available\":false,\"pixel_effect\":\"未検証\"}");return 2;}
    // WindowServerへの接続が遅延作成されるため、非表示の自ウインドウで接続を確立する。
    NSWindow *window=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,64,64) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed=NO;
    int cid=connection();NSMutableArray *rows=[NSMutableArray array];
    NSArray *names=@[@"CIColorControls",@"CISharpenLuminance",@"CIUnsharpMask",@"UltraScaleInvalidFilterControl"];
    NSArray *values=@[@{@"inputContrast":@1.1},@{@"inputSharpness":@0.25},@{@"inputRadius":@1,@"inputIntensity":@0.25},@{}];
    for(NSUInteger i=0;i<names.count;i++) {
        uint32_t handle=0;int created=create(cid,(__bridge CFStringRef)names[i],&handle);
        NSNumber *configured=nil,*released=nil;
        if(!created && handle){configured=@(set(cid,handle,(__bridge CFDictionaryRef)values[i]));released=@(releaseFilter(cid,handle));}
        [rows addObject:@{@"filter":names[i],@"create_result":@(created),@"handle_nonzero":@(handle!=0),@"set_result":configured?:NSNull.null,@"release_result":released?:NSNull.null,@"pixel_effect":@"未検証"}];
    }
    // 別経路のCore Animationフィルタを列挙・生成する。画素への適用可能性とは分ける。
    Class filterClass=NSClassFromString(@"CAFilter");SEL typesSelector=NSSelectorFromString(@"filterTypes");
    id types=[filterClass respondsToSelector:typesSelector] ? ((id(*)(id,SEL))objc_msgSend)(filterClass,typesSelector):@[];
    NSMutableArray *caFilters=[NSMutableArray array];SEL make=NSSelectorFromString(@"filterWithType:"),keys=NSSelectorFromString(@"inputKeys");
    if([filterClass respondsToSelector:make])for(NSString *type in @[@"lanczosResize",@"luminanceCurveMap",@"colorMatrix",@"gaussianBlur"]) {
        id filter=((id(*)(id,SEL,id))objc_msgSend)(filterClass,make,type);
        id inputs=[filter respondsToSelector:keys] ? ((id(*)(id,SEL))objc_msgSend)(filter,keys):@[];
        [caFilters addObject:@{@"type":type,@"created":@(filter!=nil),@"input_keys":inputs?:@[],@"pixel_effect":@"未検証"}];
    }
    NSDictionary *report=@{@"os":NSProcessInfo.processInfo.operatingSystemVersionString,@"connection":@(cid),@"window":@(window.windowNumber),@"symbols_available":@YES,@"pixel_effect":@"未検証",@"filters":rows,@"core_animation_filter_types":types?:@[],@"core_animation_filters":caFilters};
    NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];
    fwrite(json.bytes,1,json.length,stdout);puts("");[window close];return 0;
}}
