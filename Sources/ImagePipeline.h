#import <CoreImage/CoreImage.h>

// 縮小後に輝度の輪郭を補正する。入力画像は変更しない。
FOUNDATION_EXPORT CIImage *USFilteredImage(CIImage *image, CGSize outputSize, NSInteger filter, double sharpness);
