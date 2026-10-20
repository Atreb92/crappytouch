// crappytouch: loaded into SpringBoard only (see crappytouch.plist).
#import <UIKit/UIKit.h>
#import <os/log.h>
#import "src/Server.h"
#import "src/Touch.h"

%ctor {
    os_log(OS_LOG_DEFAULT, "crappytouch loaded");
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                    object:nil queue:nil usingBlock:^(NSNotification *n) {
        CTTouchStart();
        CTServerStart();
    }];
}
