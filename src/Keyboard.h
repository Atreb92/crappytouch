#import <Foundation/Foundation.h>

// Press and release HID `usage` on usage `page` (7 keyboard, 0x0C consumer: Home, power, volume) with
// `modifiers` held (HID modifier byte: bit 0 left Ctrl, 1 left Shift, 2 left Alt, 3 left Cmd, 4–7 the
// right ones). NO if the arguments are out of range.
BOOL CTKey(NSInteger page, NSInteger usage, NSInteger modifiers);
