#import "ImagePipeline.h"
CIImage *USFilteredImage(CIImage *image, CGSize size, NSInteger filter, double sharpness) {
    CGRect extent = image.extent;
    if (extent.size.width <= 0 || extent.size.height <= 0 || size.width <= 0 || size.height <= 0) return nil;
    image = [image imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x, -extent.origin.y)];
    double sx = size.width / extent.size.width, sy = size.height / extent.size.height;
    image = [image imageByClampingToExtent];
    if (filter == 1 || filter == 2) {
        NSString *name = filter == 1 ? @"CIBicubicScaleTransform" : @"CILanczosScaleTransform";
        image = [image imageByApplyingFilter:name withInputParameters:@{@"inputScale":@(sy), @"inputAspectRatio":@(sx / sy)}];
    } else image = [image imageByApplyingTransform:CGAffineTransformMakeScale(sx, sy)];
    CGRect output = CGRectMake(0, 0, size.width, size.height);
    image = [image imageByCroppingToRect:output];
    if (sharpness > 0) image = [[image imageByClampingToExtent] imageByApplyingFilter:@"CISharpenLuminance"
        withInputParameters:@{@"inputSharpness":@(MAX(0, MIN(1, sharpness)))}];
    return [image imageByCroppingToRect:output];
}
