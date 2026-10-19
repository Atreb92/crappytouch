#import "Clipboard.h"
#import "Keyboard.h"
#import <UIKit/UIKit.h>

#define USAGE_V 0x19
#define MOD_LEFT_CMD 0x08

NSString *SAClipboardGet(void) {
    __block NSString *text;
    dispatch_sync(dispatch_get_main_queue(), ^{ text = UIPasteboard.generalPasteboard.string; });
    return text ?: @"";
}

void SAClipboardSet(NSString *text) {
    dispatch_sync(dispatch_get_main_queue(), ^{ UIPasteboard.generalPasteboard.string = text; });
}

BOOL SAText(NSString *text) {
    SAClipboardSet(text);
    return SAKey(USAGE_V, MOD_LEFT_CMD);
}
