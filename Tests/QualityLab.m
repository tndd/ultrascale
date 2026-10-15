#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <CommonCrypto/CommonDigest.h>
#import "ImagePipeline.h"

// 画素の変化・測定系の感度を判定する。可読性や実パネルの改善を自動合格にしない。
static int failures;
static NSMutableArray *checks;
static void check(BOOL ok, NSString *name) {
    [checks addObject:@{@"name":name,@"passed":@(ok)}];
    printf("%s: %s\n",ok ? "PASS":"FAIL",name.UTF8String); if(!ok) failures++;
}
static NSString *digest(NSData *data) {
    unsigned char hash[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes,(CC_LONG)data.length,hash);
    NSMutableString *s=[NSMutableString string]; for(NSUInteger i=0;i<sizeof(hash);i++)[s appendFormat:@"%02x",hash[i]]; return s;
}
static NSData *rgba(CIContext *context, CIImage *image, CGRect rect) {
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)rect.size.width*(NSUInteger)rect.size.height*4];
    CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    [context render:image toBitmap:data.mutableBytes rowBytes:(NSUInteger)rect.size.width*4 bounds:rect format:kCIFormatRGBA8 colorSpace:space];
    CGColorSpaceRelease(space); return data;
}
static double difference(NSData *a, NSData *b) {
    if(a.length!=b.length)return INFINITY;
    const unsigned char *x=a.bytes,*y=b.bytes; double sum=0;
    for(NSUInteger i=0;i<a.length;i++) if(i%4!=3)sum+=abs(x[i]-y[i]);
    return sum/(a.length*0.75);
}
static double crossing(const unsigned char *p, NSUInteger n, double threshold) {
    for(NSUInteger x=1;x<n;x++)if(p[4*x]>=threshold && p[4*(x-1)]<threshold)
        return x-1+(threshold-p[4*(x-1)])/(p[4*x]-p[4*(x-1)]);
    return NAN;
}
static NSDictionary *edgeMetrics(NSData *data) {
    const unsigned char *p=data.bytes; NSUInteger n=data.length/4; int lo=255,hi=0,fringe=0;
    for(NSUInteger x=0;x<n;x++) {
        lo=MIN(lo,p[4*x]);hi=MAX(hi,p[4*x]);
        fringe=MAX(fringe,MAX(abs(p[4*x]-p[4*x+1]),abs(p[4*x]-p[4*x+2])));
    }
    double width=crossing(p,n,204.8)-crossing(p,n,51.2);
    return @{@"edge_width_px":isfinite(width)?@(width):NSNull.null,
             @"overshoot_8bit":@(MAX(0,MAX(32-lo,hi-224))),@"gray_channel_spread":@(fringe)};
}
static CIImage *solid(double value, CGRect rect) {
    return [[CIImage imageWithColor:[CIColor colorWithRed:value green:value blue:value alpha:1]] imageByCroppingToRect:rect];
}
static NSBitmapImageRep *pattern(CGSize size, double scale) {
    NSBitmapImageRep *b=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:(NSInteger)size.width pixelsHigh:(NSInteger)size.height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    [NSGraphicsContext saveGraphicsState];NSGraphicsContext.currentContext=[NSGraphicsContext graphicsContextWithBitmapImageRep:b];
    NSAffineTransform *t=[NSAffineTransform transform];[t scaleBy:scale];[t concat];
    double h=size.height/scale;
    [NSColor.whiteColor setFill];NSRectFill(NSMakeRect(0,0,size.width/scale,h));
    for(NSInteger row=0;row<5;row++) {
        NSInteger pointSize=9+row*2;
        NSString *text=[NSString stringWithFormat:@"%ld pt  日本語の小さい文字：輪郭・濁点・細線  Il1 O0  0123456789",pointSize];
        [text drawAtPoint:NSMakePoint(20,h-34-row*27) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:pointSize],NSForegroundColorAttributeName:NSColor.blackColor}];
    }
    [[NSColor colorWithSRGBRed:0.07 green:0.09 blue:0.12 alpha:1] setFill];NSRectFill(NSMakeRect(12,h-292,760,130));
    for(NSInteger row=0;row<3;row++) {
        NSString *text=@"小さな文字と余白：美しい画面  AaBb  Il1 | {} () <>";
        NSColor *color=row==2 ? [NSColor colorWithSRGBRed:0.25 green:0.65 blue:1 alpha:1]:NSColor.whiteColor;
        [text drawAtPoint:NSMakePoint(20,h-190-row*30) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:9+row*2],NSForegroundColorAttributeName:color}];
    }
    [NSColor.blackColor setFill];
    for(int x=20;x<700;x+=4)NSRectFill(NSMakeRect(x,h-322,1,16));
    [NSGraphicsContext restoreGraphicsState];return b;
}
static BOOL saveImage(CIContext *context, CIImage *image, CGRect rect, NSString *path) {
    CGColorSpaceRef space=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef cg=[context createCGImage:image fromRect:rect format:kCIFormatRGBA8 colorSpace:space];CGColorSpaceRelease(space);
    if(!cg)return NO;
    NSBitmapImageRep *b=[[NSBitmapImageRep alloc] initWithCGImage:cg];CGImageRelease(cg);
    return [[b representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES];
}
int main(int argc,const char **argv) {@autoreleasepool {
    if(argc<3 || argc>4 || (argc==4 && *argv[3] && strcmp(argv[3],"--inject-noop")!=0)){fprintf(stderr,"出力先、100〜200の倍率、任意で--inject-noopを指定してください。\n");return 2;}
    char *end=NULL; long percent=strtol(argv[2],&end,10);
    if(!end || *end || percent<100 || percent>200)return 2;
    NSString *directory=[NSString stringWithUTF8String:argv[1]];
    BOOL injectNoop=argc>3 && strcmp(argv[3],"--inject-noop")==0;
    checks=[NSMutableArray array];NSError *error=nil;
    if(![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]){fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);return 2;}
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();if(!device)return 2;
    CIContext *context=[CIContext contextWithMTLDevice:device options:@{kCIContextCacheIntermediates:@NO}];
    CGSize sourceSize=CGSizeMake(2*lround(344000.0/percent),2*lround(144000.0/percent));
    CGSize target=CGSizeMake(3440,1440);CGRect output=(CGRect){CGPointZero,target};
    NSBitmapImageRep *fixture=pattern(sourceSize,2);
    CIImage *source=[[CIImage alloc] initWithCGImage:fixture.CGImage];
    NSData *fixturePNG=[fixture representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    check([fixturePNG writeToFile:[directory stringByAppendingPathComponent:@"source.png"] atomically:YES],@"入力画像を保存");
    CGRect sourceRect=(CGRect){CGPointZero,sourceSize};
    CIImage *edge=[solid(224/255.0,CGRectMake(sourceSize.width/2,0,sourceSize.width/2,sourceSize.height)) imageByCompositingOverImage:solid(32/255.0,sourceRect)];
    CGRect edgeRect=CGRectMake(1688,100,64,1);
    CGRect crop=CGRectMake(0,1440-ceil(330*percent/100.0),ceil(800*percent/100.0),ceil(330*percent/100.0));
    NSArray *variants=@[@{@"id":@"linear",@"name":@"バイリニア",@"filter":@0,@"sharp":@0},
      @{@"id":@"cubic",@"name":@"バイキュービック",@"filter":@1,@"sharp":@0},
      @{@"id":@"lanczos",@"name":@"Lanczos",@"filter":@2,@"sharp":@0},
      @{@"id":@"sharp25",@"name":@"Lanczos + 強度25",@"filter":@2,@"sharp":@0.25},
      @{@"id":@"sharp75",@"name":@"Lanczos + 強度75",@"filter":@2,@"sharp":@0.75}];
    NSMutableArray *rows=[NSMutableArray array];NSMutableDictionary *pixels=[NSMutableDictionary dictionary];
    for(NSDictionary *v in variants) {@autoreleasepool {
        NSString *identifier=v[@"id"];NSInteger filter=[v[@"filter"] integerValue];double sharp=[v[@"sharp"] doubleValue];
        CIImage *processed=USFilteredImage(source,target,filter,injectNoop?0:sharp);
        NSData *data=rgba(context,processed,crop);pixels[identifier]=data;
        BOOL opaque=YES;const unsigned char *bytes=data.bytes;
        for(NSUInteger i=3;i<data.length;i+=4)opaque&=bytes[i]==255;
        check(CGRectEqualToRect(processed.extent,output)&&opaque,[NSString stringWithFormat:@"%@: 出力寸法・比較範囲の不透明度",identifier]);
        check(saveImage(context,processed,output,[directory stringByAppendingPathComponent:[identifier stringByAppendingString:@"-full.png"]]) && saveImage(context,processed,crop,[directory stringByAppendingPathComponent:[identifier stringByAppendingString:@".png"]]),[identifier stringByAppendingString:@": 画素を保存"]);
        double widthSum=0;NSInteger maxHalo=0,maxFringe=0;BOOL measured=YES;
        for(NSInteger phase=0;phase<4;phase++) {
            double split=sourceSize.width/2+phase*0.5;
            CIImage *phaseEdge=[solid(224/255.0,CGRectMake(split,0,sourceSize.width-split,sourceSize.height)) imageByCompositingOverImage:solid(32/255.0,sourceRect)];
            NSDictionary *m=edgeMetrics(rgba(context,USFilteredImage(phaseEdge,target,filter,injectNoop?0:sharp),edgeRect));
            measured&=m[@"edge_width_px"]!=NSNull.null;
            if(m[@"edge_width_px"]!=NSNull.null)widthSum+=[m[@"edge_width_px"] doubleValue];
            maxHalo=MAX(maxHalo,[m[@"overshoot_8bit"] integerValue]);maxFringe=MAX(maxFringe,[m[@"gray_channel_spread"] integerValue]);
        }
        check(measured,[identifier stringByAppendingString:@": 4位置の輪郭を測定"]);
        NSMutableDictionary *row=[v mutableCopy];[row addEntriesFromDictionary:@{@"edge_width_px":measured?@(widthSum/4):NSNull.null,@"overshoot_8bit":@(maxHalo),@"gray_channel_spread":@(maxFringe)}];
        row[@"pixel_sha256"]=digest(data);row[@"difference_from_linear"]=@(difference(data,pixels[@"linear"]));
        row[@"quality_verdict"]=@"未判定";[rows addObject:row];
    }}
    if(CGSizeEqualToSize(sourceSize,target))
        check(difference(pixels[@"linear"],pixels[@"cubic"])<0.01 && difference(pixels[@"cubic"],pixels[@"lanczos"])<0.01,@"200%の1:1出力では縮小フィルタによる差がない");
    else check(difference(pixels[@"linear"],pixels[@"cubic"])>0.01 && difference(pixels[@"cubic"],pixels[@"lanczos"])>0.01,@"縮小方式の切り替えが画素に反映される");
    check(difference(pixels[@"lanczos"],pixels[@"sharp25"])>0.01 && difference(pixels[@"sharp25"],pixels[@"sharp75"])>0.01,@"シャープネスの変更が画素に反映される（無効化を検出）");
    CIImage *base=USFilteredImage(edge,target,0,0);
    NSDictionary *normal=edgeMetrics(rgba(context,base,edgeRect));
    NSDictionary *blur=edgeMetrics(rgba(context,[[base imageByClampingToExtent] imageByApplyingFilter:@"CIGaussianBlur" withInputParameters:@{@"inputRadius":@2}],edgeRect));
    check([blur[@"edge_width_px"] doubleValue]>[normal[@"edge_width_px"] doubleValue]+1,@"測定系: 故意に加えたぼけを検出");
    NSMutableData *halo=[rgba(context,base,edgeRect) mutableCopy];unsigned char *hp=halo.mutableBytes;hp[16*4]=hp[16*4+1]=hp[16*4+2]=0;
    check([edgeMetrics(halo)[@"overshoot_8bit"] intValue]>=32,@"測定系: 故意に加えた縁取りを検出");
    check(difference(pixels[@"linear"],pixels[@"linear"])==0,@"測定系: 同一画像を変化ありと誤判定しない");
    NSDictionary *report=@{@"schema":@1,@"percent":@(percent),@"source_width":@(sourceSize.width),@"source_height":@(sourceSize.height),@"output_width":@3440,@"output_height":@1440,
      @"os":NSProcessInfo.processInfo.operatingSystemVersionString,@"gpu":device.name,@"input_sha256":digest(fixturePNG),@"pipeline_source_sha256":digest([NSData dataWithContentsOfFile:@"Sources/ImagePipeline.m"]),@"edge_phases":@4,@"crop":@{@"x":@(crop.origin.x),@"y":@(crop.origin.y),@"width":@(crop.size.width),@"height":@(crop.size.height)},
      @"checks":checks,@"processing_passed":@(failures==0),@"quality_verdict":@"未判定",@"compositor":@"未検証",@"physical_display":@"未検証",@"variants":rows};
    NSData *json=[NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error];
    NSString *jsonText=[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    NSString *html=[NSString stringWithContentsOfFile:@"scripts/quality-report.html" encoding:NSUTF8StringEncoding error:&error];
    html=[html stringByReplacingOccurrencesOfString:@"__REPORT_JSON__" withString:jsonText?:@"null"];
    BOOL saved=json && html && [json writeToFile:[directory stringByAppendingPathComponent:@"report.json"] atomically:YES] && [html writeToFile:[directory stringByAppendingPathComponent:@"index.html"] atomically:YES encoding:NSUTF8StringEncoding error:&error];
    if(!saved){fprintf(stderr,"レポート保存失敗: %s\n",error.localizedDescription.UTF8String);return 2;}
    printf("処理検証: %s / 見やすさ: 未判定 / 合成・物理出力: 未検証\n%s/index.html\n",failures?"FAIL":"PASS",directory.UTF8String);
    return failures?1:0;
}}
