#import <Foundation/Foundation.h>

// Asks the user on the phone to allow `name`; blocks the calling (client) thread until Allow, Deny
// or 30 s. On Allow the host is saved. Returns nil when allowed, else the protocol error string.
// Never call from the main thread.
NSString *SAPair(NSString *name, NSData *secret);
