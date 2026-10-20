#import "Screen.h"
#import <UIKit/UIKit.h>

UIImage *_UICreateScreenUIImage(void) NS_RETURNS_RETAINED; // private UIKit: the display, status bar included

@interface UIApplication (SpringBoard)
- (UIInterfaceOrientation)activeInterfaceOrientation; // SpringBoard: the frontmost app's
@end

NSDictionary *CTScreenInfo(void) {
    __block NSDictionary *info;
    dispatch_sync(dispatch_get_main_queue(), ^{
        UIScreen *screen = UIScreen.mainScreen;
        CGSize size = screen.fixedCoordinateSpace.bounds.size; // portrait, like touch coordinates
        UIApplication *app = UIApplication.sharedApplication;
        UIInterfaceOrientation o = [app respondsToSelector:@selector(activeInterfaceOrientation)]
                                       ? app.activeInterfaceOrientation : UIInterfaceOrientationPortrait;
        info = @{@"width": @(size.width), @"height": @(size.height), @"scale": @(screen.scale),
                 @"orientation": @(o ?: UIInterfaceOrientationPortrait)}; // 0 = unknown
    });
    return info;
}

NSData *CTScreenshotPNG(void) {
    __block UIImage *image;
    dispatch_sync(dispatch_get_main_queue(), ^{ image = _UICreateScreenUIImage(); });
    return image ? UIImagePNGRepresentation(image) : nil; // encoding off the main thread
}
