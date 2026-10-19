// scrcrappy-agent: loaded into SpringBoard only (see scrcrappyagent.plist).
#import <UIKit/UIKit.h>
#import <os/log.h>
#import "src/Server.h"
#import "src/Touch.h"

%ctor {
    os_log(OS_LOG_DEFAULT, "scrcrappy-agent loaded");
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                    object:nil queue:nil usingBlock:^(NSNotification *n) {
        SATouchStart();
        SAServerStart();
    }];
}
