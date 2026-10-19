#import "Keyboard.h"
#import "HID.h"
#import <mach/mach_time.h>

static void Send(IOHIDEventSystemClientRef client, uint32_t page, uint32_t usage, BOOL down) {
    IOHIDEventRef e = IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, mach_absolute_time(), page, usage, down, 0);
    IOHIDEventSystemClientDispatchEvent(client, e);
    CFRelease(e);
}

BOOL SAKey(NSInteger page, NSInteger usage, NSInteger modifiers) {
    static IOHIDEventSystemClientRef client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ client = IOHIDEventSystemClientCreate(kCFAllocatorDefault); });
    if (!client || page < 1 || page > 0xFFFF || usage < 1 || usage > 0xFFFF || modifiers < 0 || modifiers > 0xFF)
        return NO;

    for (int bit = 0; bit < 8; bit++)
        if (modifiers & 1 << bit) Send(client, 7, 0xE0 + bit, YES);
    Send(client, (uint32_t)page, (uint32_t)usage, YES);
    Send(client, (uint32_t)page, (uint32_t)usage, NO);
    for (int bit = 7; bit >= 0; bit--)
        if (modifiers & 1 << bit) Send(client, 7, 0xE0 + bit, NO);
    return YES;
}
