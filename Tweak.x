// scrcrappy-agent: loaded into SpringBoard only (see scrcrappyagent.plist).
#import <UIKit/UIKit.h>
#import <os/log.h>

%ctor {
    os_log(OS_LOG_DEFAULT, "scrcrappy-agent loaded");
}
