#import "Awake.h"
#import <os/log.h>

#define PREFS CFSTR("com.atreb92.crappytouch")
#define PREFS_CHANGED "com.atreb92.crappytouch.prefs" // posted by the Settings switch

// SpringBoard private API, iOS 16
@protocol CTInvalidatable
- (void)invalidate;
@end

@interface SBIdleTimerGlobalCoordinator : NSObject
+ (instancetype)sharedInstance;
- (id<CTInvalidatable>)acquireIdleTimerDisableAssertionForReason:(NSString *)reason;
@end

static NSInteger connected;           // main queue only
static id<CTInvalidatable> assertion; // main queue only

static BOOL SwitchOn(void) {
    CFPreferencesAppSynchronize(PREFS); // Settings wrote it from another process
    return CFPreferencesGetAppBooleanValue(CFSTR("keepAwake"), PREFS, NULL);
}

// Main queue.
static void Update(void) {
    BOOL want = connected > 0 && SwitchOn();
    if (want == (assertion != nil)) return;
    if (want) {
        Class c = NSClassFromString(@"SBIdleTimerGlobalCoordinator");
        SBIdleTimerGlobalCoordinator *coord = [c respondsToSelector:@selector(sharedInstance)] ? [c sharedInstance] : nil;
        if ([coord respondsToSelector:@selector(acquireIdleTimerDisableAssertionForReason:)])
            assertion = [coord acquireIdleTimerDisableAssertionForReason:@"crappytouch"];
    } else {
        [assertion invalidate];
        assertion = nil;
    }
    os_log(OS_LOG_DEFAULT, "crappytouch: keep awake %{public}s", assertion ? "on" : "off");
}

static void PrefsChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *obj, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{ Update(); });
}

void CTAwakeConnected(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PrefsChanged,
                                        CFSTR(PREFS_CHANGED), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    });
    dispatch_async(dispatch_get_main_queue(), ^{ connected++; Update(); });
}

void CTAwakeDisconnected(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ connected--; Update(); });
}
