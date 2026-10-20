#import <Foundation/Foundation.h>

// Asks the user on the phone to allow `name`; blocks the calling (client) thread until Allow, Deny
// or 30 s. On Allow the host is saved. Returns nil when allowed, else the protocol error string.
// Never call from the main thread.
NSString *CTPair(NSString *name, NSData *secret);
// Main thread. YES when the lock screen is up (or SpringBoard's lock manager can't be found).
BOOL CTPhoneLocked(void);
