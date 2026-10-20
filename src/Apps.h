#import <Foundation/Foundation.h>

// Openable apps sorted by name: {id, name, pid (only when running)}. Not on the main thread.
NSArray<NSDictionary *> *SAApps(void);
// Brings the app to the front. nil on success, else "unknown app" / "locked" / "open failed".
// Not on the main thread.
NSString *SAOpenApp(NSString *bundleID);
// Opens a URL / deeplink, the way tapping a link would. nil on success, else "bad url" /
// "locked" / "open failed". Not on the main thread.
NSString *SAOpenURL(NSString *url);
