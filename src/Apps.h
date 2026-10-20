#import <Foundation/Foundation.h>

// Openable apps sorted by name: {id, name, pid (only when running)}. Not on the main thread.
NSArray<NSDictionary *> *SAApps(void);
// Brings the app to the front. nil on success, else "unknown app" / "locked" / "open failed".
// Not on the main thread.
NSString *SAOpenApp(NSString *bundleID);
