#import "Clipboard.h"
#import "Keyboard.h"
#import <UIKit/UIKit.h>

#define USAGE_V 0x19
#define MOD_LEFT_CMD 0x08
#define READ_TIMEOUT_S 30

// Not on the main thread: reading another app's copy can block until iOS grants the paste, and a
// blocked SpringBoard main thread is killed by the watchdog after 60 s.
NSString *CTClipboardGet(void) {
    static dispatch_queue_t queue; // one read at a time; a stuck read makes later ones time out too
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("crappytouch.clipboard", DISPATCH_QUEUE_SERIAL); });
    __block NSString *text = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    dispatch_async(queue, ^{
        text = UIPasteboard.generalPasteboard.string ?: @"";
        dispatch_semaphore_signal(done);
    });
    return dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, READ_TIMEOUT_S * NSEC_PER_SEC)) ? nil : text;
}

void CTClipboardSet(NSString *text) {
    dispatch_sync(dispatch_get_main_queue(), ^{ UIPasteboard.generalPasteboard.string = text; });
}

BOOL CTText(NSString *text) {
    CTClipboardSet(text);
    return CTKey(7, USAGE_V, MOD_LEFT_CMD);
}
