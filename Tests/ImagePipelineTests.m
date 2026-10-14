#import "ImagePipeline.h"
#import <Metal/Metal.h>
#import <Cocoa/Cocoa.h>
static int failures = 0;
static void check(BOOL ok, NSString *name) { printf("%s: %s\n", ok ? "PASS" : "FAIL", name.UTF8String); if (!ok) failures++; }
int main(void) { @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    check(device != nil, @"画質調整用Metalデバイス");
    if (!device) return 1;
    CIContext *context = [CIContext contextWithMTLDevice:device];
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    NSMutableData *input = [NSMutableData dataWithLength:256 * 128 * 4];
    unsigned char *pixels = input.mutableBytes;
    for (int y = 0; y < 128; ++y) for (int x = 0; x < 256; ++x) {
        int index = (y * 256 + x) * 4;
        unsigned char color = (x > 47 && x < 114 && y > 17 && y < 80) || (x > 140 && x % 3 == 0) ? 32 : 224;
        pixels[index] = pixels[index+1] = pixels[index+2] = color; pixels[index+3] = 255;
    }
    CIImage *source = [[CIImage alloc] initWithBitmapData:input bytesPerRow:256*4 size:CGSizeMake(256,128) format:kCIFormatRGBA8 colorSpace:space];
    NSMutableArray<NSData *> *results = [NSMutableArray array];
    for (NSInteger filter = 0; filter < 3; ++filter) {
        CIImage *output = USFilteredImage(source, CGSizeMake(160,80), filter, 0);
        check(CGRectEqualToRect(output.extent, CGRectMake(0,0,160,80)), [NSString stringWithFormat:@"フィルタ%ldの出力寸法", filter]);
        NSMutableData *data = [NSMutableData dataWithLength:160*80*4];
        [context render:output toBitmap:data.mutableBytes rowBytes:160*4 bounds:output.extent format:kCIFormatRGBA8 colorSpace:space];
        [results addObject:data];
        CGImageRef image = [context createCGImage:output fromRect:output.extent];
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:image];
        [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[NSString stringWithFormat:@"build/filter-%ld.png", filter] atomically:YES];
        CGImageRelease(image);
    }
    check(![results[0] isEqual:results[1]] && ![results[1] isEqual:results[2]], @"3種類の縮小フィルタが異なる画素を出力する");
    CIImage *sharp = USFilteredImage(source, CGSizeMake(160,80), 2, 0.75);
    NSMutableData *sharpData = [NSMutableData dataWithLength:160*80*4];
    [context render:sharp toBitmap:sharpData.mutableBytes rowBytes:160*4 bounds:sharp.extent format:kCIFormatRGBA8 colorSpace:space];
    check(![sharpData isEqual:results[2]], @"シャープネスが実際の画素を変化させる");
    CIImage *flat = [[CIImage imageWithColor:[CIColor colorWithRed:0.5 green:0.5 blue:0.5 alpha:1]] imageByCroppingToRect:CGRectMake(0,0,256,128)];
    CIImage *flatSharp = USFilteredImage(flat, CGSizeMake(160,80), 2, 1);
    [context render:flatSharp toBitmap:sharpData.mutableBytes rowBytes:160*4 bounds:flatSharp.extent format:kCIFormatRGBA8 colorSpace:space];
    const unsigned char *bytes = sharpData.bytes; BOOL uniform = YES;
    for (NSUInteger i=0; i<sharpData.length; i+=4) uniform &= abs(bytes[i]-128)<=2 && bytes[i+3]==255;
    if (!uniform) printf("gray first=%u,%u,%u alpha=%u center=%u alpha=%u\n", bytes[0],bytes[1],bytes[2],bytes[3],bytes[(40*160+80)*4],bytes[(40*160+80)*4+3]);
    check(uniform, @"均一な灰色と不透明度をシャープネス最大でも維持する");
    check(CGRectEqualToRect(source.extent,CGRectMake(0,0,256,128)), @"入力画像の寸法を維持する");
    CGColorSpaceRelease(space);
    printf("画像処理: %d件の失敗\n",failures);
    return failures ? 1 : 0;
} }
