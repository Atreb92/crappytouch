#import <Foundation/Foundation.h>

// Main thread, once: sets up the HID client and starts learning the touchscreen's sender ID.
void SATouchStart(void);

// `events` as in the protocol's `touch` command; invalid entries and touches before the sender ID
// is known are dropped. `held` (one per connection) tracks the fingers this connection holds down.
void SATouch(NSArray *events, NSMutableIndexSet *held);
// Lifts every finger in `held`, e.g. when its connection closes.
void SATouchRelease(NSMutableIndexSet *held);

BOOL SATouchReady(void);
NSUInteger SATouchFingersDown(void);
