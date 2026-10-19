#import <Foundation/Foundation.h>

// width/height (portrait points), scale, orientation (frontmost app's UIInterfaceOrientation). Not on the main thread.
NSDictionary *SAScreenInfo(void);
// PNG of the screen at full resolution, nil on failure. Not on the main thread.
NSData *SAScreenshotPNG(void);
