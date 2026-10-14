#import <Cocoa/Cocoa.h>

// 承認された1254px原画の白いタイルの内側をなぞる。内部の絵は描き直さない。
static NSPoint point(CGFloat x, CGFloat y) { return NSMakePoint(x, 1254 - y); }
static NSBezierPath *silhouette(void) {
    NSBezierPath *path = [NSBezierPath bezierPath];
    [path moveToPoint:point(420, 188)];
    [path lineToPoint:point(830, 188)];
    [path curveToPoint:point(1066, 412) controlPoint1:point(990, 188) controlPoint2:point(1066, 260)];
    [path lineToPoint:point(1066, 812)];
    [path curveToPoint:point(836, 1038) controlPoint1:point(1066, 970) controlPoint2:point(990, 1038)];
    [path lineToPoint:point(416, 1038)];
    [path curveToPoint:point(188, 812) controlPoint1:point(260, 1038) controlPoint2:point(188, 970)];
    [path lineToPoint:point(188, 414)];
    [path curveToPoint:point(420, 188) controlPoint1:point(188, 259) controlPoint2:point(265, 188)];
    [path closePath];
    return path;
}
int main(void) {
    @autoreleasepool {
        for (NSString *color in @[@"Blue", @"Green"]) {
            NSString *source = [NSString stringWithFormat:@"Assets/Icons/Original%@.png", color];
            NSImage *image = [[NSImage alloc] initWithContentsOfFile:source];
            NSBitmapImageRep *original = [[NSBitmapImageRep alloc] initWithData:[NSData dataWithContentsOfFile:source]];
            if (!image || original.pixelsWide != 1254 || original.pixelsHigh != 1254) {
                fprintf(stderr, "原画は1254×1254のPNGが必要です: %s\n", source.UTF8String); return 1;
            }
            image.size = NSMakeSize(1254, 1254);
            NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                pixelsWide:1024 pixelsHigh:1024 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
            [NSGraphicsContext saveGraphicsState];
            NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
            NSGraphicsContext.currentContext.imageInterpolation = NSImageInterpolationHigh;
            [[NSColor clearColor] setFill];
            NSRectFillUsingOperation(NSMakeRect(0, 0, 1024, 1024), NSCompositingOperationClear);
            CGFloat scale = 896.0 / 878.0;
            NSAffineTransform *transform = [NSAffineTransform transform];
            [transform translateXBy:512 - 627 * scale yBy:512 - 641 * scale];
            [transform scaleBy:scale]; [transform concat];
            [silhouette() addClip];
            [image drawInRect:NSMakeRect(0, 0, 1254, 1254)];
            [NSGraphicsContext restoreGraphicsState];
            NSString *output = [NSString stringWithFormat:@"Assets/Icons/Icon%@.png", color];
            NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            if (!png || ![png writeToFile:output atomically:YES]) return 1;
            if ([bitmap colorAtX:0 y:0].alphaComponent != 0 || [bitmap colorAtX:512 y:512].alphaComponent < 0.99) return 1;
            printf("%s: 1024×1024、外周透過、中央不透明\n", output.UTF8String);
        }
    }
    return 0;
}
