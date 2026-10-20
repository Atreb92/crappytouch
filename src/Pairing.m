#import "Pairing.h"
#import "Auth.h"
#import <CommonCrypto/CommonDigest.h>
#import <UIKit/UIKit.h>
#import <os/log.h>
#import <stdatomic.h>

#define TIMEOUT_S 30

static atomic_bool pending; // one alert at a time: no alert spam from a local app

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
@end

static NSString *PairingCode(NSData *secret) {
    uint8_t d[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(secret.bytes, (CC_LONG)secret.length, d);
    return [NSString stringWithFormat:@"%06u", ((uint32_t)d[0] << 16 | d[1] << 8 | d[2]) % 1000000];
}

// Fails closed: if SpringBoard's lock manager isn't there, treat the phone as locked.
BOOL CTPhoneLocked(void) {
    Class mgr = NSClassFromString(@"SBLockScreenManager");
    if (![mgr respondsToSelector:@selector(sharedInstance)]) return YES;
    SBLockScreenManager *m = [mgr sharedInstance];
    return ![m respondsToSelector:@selector(isUILocked)] || [m isUILocked];
}

// Main thread. A window of our own, above SpringBoard's, on the main screen's scene.
static UIWindow *AlertWindow(void) {
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class] && ((UIWindowScene *)s).screen == UIScreen.mainScreen)
            scene = (UIWindowScene *)s;
    UIWindow *w = scene ? [[UIWindow alloc] initWithWindowScene:scene]
                        : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    w.windowLevel = UIWindowLevelAlert + 1;
    w.rootViewController = [UIViewController new];
    w.rootViewController.view.backgroundColor = UIColor.clearColor;
    w.hidden = NO;
    return w;
}

NSString *CTPair(NSString *name, NSData *secret) {
    if (atomic_exchange(&pending, true)) return @"busy";

    // decided / allowed / window are only touched on the main queue, so a tap racing the timeout is safe
    __block BOOL decided = NO, allowed = NO, allowedFinal = NO, locked = NO;
    __block UIWindow *window = nil;
    dispatch_semaphore_t answered = dispatch_semaphore_create(0);
    NSString *code = PairingCode(secret);
    dispatch_sync(dispatch_get_main_queue(), ^{
        if ((locked = CTPhoneLocked())) return;
        window = AlertWindow();
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:[NSString stringWithFormat:@"Allow “%@” to control this iPhone?", name]
                             message:[NSString stringWithFormat:@"Code %@\nAllow only if the computer shows the same code.", code]
                      preferredStyle:UIAlertControllerStyleAlert];
        void (^answer)(BOOL) = ^(BOOL allow) {
            if (decided) return;
            decided = YES;
            allowed = allow;
            dispatch_semaphore_signal(answered);
        };
        [alert addAction:[UIAlertAction actionWithTitle:@"Deny" style:UIAlertActionStyleCancel
                                                handler:^(UIAlertAction *a) { answer(NO); }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Allow" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) { answer(YES); }]];
        [window.rootViewController presentViewController:alert animated:YES completion:nil];
    });
    if (!locked) dispatch_semaphore_wait(answered, dispatch_time(DISPATCH_TIME_NOW, TIMEOUT_S * NSEC_PER_SEC));
    dispatch_sync(dispatch_get_main_queue(), ^{
        decided = YES; // a tap after the timeout counts as nothing
        allowedFinal = allowed;
        [window.rootViewController dismissViewControllerAnimated:NO completion:nil];
        window.hidden = YES;
        window = nil;
    });

    NSString *error = locked ? @"locked" : !allowedFinal ? @"denied" : CTAuthAddHost(name, secret) ? nil : @"can't save host";
    os_log(OS_LOG_DEFAULT, "crappytouch: pair %{public}@: %{public}@", name, error ?: @"allowed");
    atomic_store(&pending, false);
    return error;
}
