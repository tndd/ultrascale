#import "FramePresenter.h"
#import <MetalKit/MetalKit.h>
#import <ImageIO/ImageIO.h>
int main(void) { @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return 1;
    // 上段は赤・緑・青、下段は白・黒・灰色。色と上下方向の両方を確認する。
    const unsigned char bgra[] = {0,0,255,255, 0,255,0,255, 255,0,0,255,
        255,255,255,255, 0,0,0,255, 128,128,128,255};
    MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:3 height:2 mipmapped:NO];
    desc.storageMode = MTLStorageModeShared;
    id<MTLTexture> texture = [device newTextureWithDescriptor:desc];
    [texture replaceRegion:MTLRegionMake2D(0,0,3,2) mipmapLevel:0 withBytes:bgra bytesPerRow:12];
    USFramePresenter *presenter = [USFramePresenter new];
    [presenter setValue:texture forKey:@"lastTexture"];
    [presenter setValue:[[MTKView alloc] initWithFrame:NSMakeRect(0,0,3,2) device:device] forKey:@"view"];
    [presenter setValue:[device newCommandQueue] forKey:@"commandQueue"];
    NSError *error = nil;
    BOOL pass = [presenter writeSnapshotTo:@"build/snapshot-test.png" error:&error];
    CGImageSourceRef input = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:@"build/snapshot-test.png"], NULL);
    CGImageRef image = input ? CGImageSourceCreateImageAtIndex(input, 0, NULL) : NULL;
    pass &= image && CGImageGetWidth(image) == 3 && CGImageGetHeight(image) == 2;
    unsigned char output[24] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef canvas = CGBitmapContextCreate(output,3,2,8,12,space,kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    if (image) CGContextDrawImage(canvas,CGRectMake(0,0,3,2),image);
    for (int y=0; y<2; y++) for (int x=0; x<3; x++) {
        int i = (y*3+x)*4;
        pass &= abs(output[i]-bgra[i+2])<2 && abs(output[i+1]-bgra[i+1])<2 && abs(output[i+2]-bgra[i])<2 && output[i+3]==255;
    }
    CGContextRelease(canvas); CGColorSpaceRelease(space);
    if (image) CGImageRelease(image); if (input) CFRelease(input);
    printf("%s: 表示用BGRAテクスチャのPNG保存（色・不透明度・上下方向）\n",pass?"PASS":"FAIL");
    if (error) fprintf(stderr,"%s\n",error.localizedDescription.UTF8String);
    return pass?0:1;
}}
