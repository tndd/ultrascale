#import <Cocoa/Cocoa.h>
#import "ImagePipeline.h"
static NSBitmapImageRep *bitmap(NSInteger width, NSInteger height) {
    return [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
}
static NSBitmapImageRep *pattern(double scale) {
    NSBitmapImageRep *b=bitmap(lround(640*scale),lround(144*scale));
    [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:b]];
    NSAffineTransform *transform=[NSAffineTransform transform]; [transform scaleBy:scale]; [transform concat];
    [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(0,0,640,144));
    NSArray *texts=@[@"日本語の細い文字：美しい画面を手に入れる",@"AaBb 0123456789  Il1 | {} () <>  @  #  &",@"青い文字と細線：画面の解像感を比較する"];
    for(NSInteger i=0;i<3;i++) [texts[i] drawAtPoint:NSMakePoint(16,116-i*27) withAttributes:@{NSFontAttributeName:[NSFont systemFontOfSize:i==1 ? 12:13],NSForegroundColorAttributeName:i==2 ? [NSColor colorWithSRGBRed:0 green:0.2 blue:0.8 alpha:1]:NSColor.blackColor}];
    [NSColor.blackColor setFill]; NSRectFill(NSMakeRect(16,10,140,20));
    for(int x=190;x<600;x+=4)NSRectFill(NSMakeRect(x,10,1,26));
    [NSGraphicsContext restoreGraphicsState];return b;
}
int main(int argc,const char **argv){@autoreleasepool{
    if(argc!=2){fprintf(stderr,"出力PNGのパスを指定してください。\n");return 2;}
    NSBitmapImageRep *source=pattern(2), *native=pattern(1.25), *canvas=bitmap(1640,708);
    CIImage *input=[[CIImage alloc] initWithCGImage:source.CGImage];
    CIContext *context=[CIContext contextWithOptions:@{kCIContextCacheIntermediates:@NO}];
    NSArray *names=@[@"参考：同じ大きさを直接描画",@"バイリニア / 強度 0",@"バイキュービック / 強度 0",@"Lanczos / 強度 0",@"Lanczos / 強度 25",@"Lanczos / 強度 75"];
    [NSGraphicsContext saveGraphicsState];[NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:canvas]];
    [[NSColor colorWithWhite:0.9 alpha:1] setFill];NSRectFill(NSMakeRect(0,0,1640,708));
    for(NSInteger i=0;i<6;i++){
        CGImageRef image=i==0 ? CGImageRetain(native.CGImage):[context createCGImage:USFilteredImage(input,CGSizeMake(800,180),i<4 ? i-1:2,i==4 ? 0.25:(i==5 ? 0.75:0)) fromRect:CGRectMake(0,0,800,180)];
        if(!image)return 1;
        double x=10+(i%2)*820, y=708-((i/2)+1)*236;
        [names[i] drawAtPoint:NSMakePoint(x,y+201) withAttributes:@{NSFontAttributeName:[NSFont boldSystemFontOfSize:15],NSForegroundColorAttributeName:NSColor.blackColor}];
        CGContextDrawImage(NSGraphicsContext.currentContext.CGContext,CGRectMake(x,y+10,800,180),image);CGImageRelease(image);
    }
    [NSGraphicsContext restoreGraphicsState];
    BOOL saved=[[canvas representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES];
    printf("同じ論理寸法を2倍描画し125%%相当へ縮小した比較: %s\n",saved ? "保存成功":"保存失敗");return saved ? 0:1;
}}
