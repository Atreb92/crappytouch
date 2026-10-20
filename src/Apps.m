#import "Apps.h"
#import "Pairing.h"
#import <UIKit/UIKit.h>

// SpringBoard private API, iOS 16
@interface SBApplicationProcessState : NSObject
@property (nonatomic, readonly) int pid;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@end

@interface SBApplicationInfo : NSObject
@property (nonatomic, readonly) NSArray *tags;
@end

@interface SBApplication : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSString *displayName;
@property (nonatomic, readonly) SBApplicationInfo *info;
@property (nonatomic, readonly) SBApplicationProcessState *processState;
@end

@interface SBApplicationController : NSObject
+ (instancetype)sharedInstance;
- (NSArray<SBApplication *> *)allApplications;
- (SBApplication *)applicationWithBundleIdentifier:(NSString *)bundleID;
@end

@interface UIApplication (SpringBoard)
- (BOOL)launchApplicationWithIdentifier:(NSString *)bundleID suspended:(BOOL)suspended;
@end

static SBApplicationController *Controller(void) {
    return [NSClassFromString(@"SBApplicationController") sharedInstance];
}

// Main thread. Hidden apps (web clips' host, system UI services, ...) have no icon and can't be opened.
static BOOL Openable(SBApplication *app) {
    SBApplicationInfo *info = [app respondsToSelector:@selector(info)] ? app.info : nil;
    NSArray *tags = [info respondsToSelector:@selector(tags)] ? info.tags : nil;
    return app.bundleIdentifier && ![tags containsObject:@"hidden"];
}

NSArray<NSDictionary *> *SAApps(void) {
    NSMutableArray *apps = [NSMutableArray array];
    dispatch_sync(dispatch_get_main_queue(), ^{
        for (SBApplication *app in Controller().allApplications) {
            if (!Openable(app)) continue;
            NSMutableDictionary *a = [@{@"id": app.bundleIdentifier, @"name": app.displayName ?: app.bundleIdentifier} mutableCopy];
            SBApplicationProcessState *state = app.processState; // nil when not running
            if (state.running && state.pid > 0) a[@"pid"] = @(state.pid);
            [apps addObject:a];
        }
    });
    [apps sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES
                                                                selector:@selector(localizedCaseInsensitiveCompare:)]]];
    return apps;
}

NSString *SAOpenApp(NSString *bundleID) {
    __block NSString *error = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        SBApplication *app = [Controller() applicationWithBundleIdentifier:bundleID];
        if (!app || !Openable(app)) error = @"unknown app";
        else if (SAPhoneLocked()) error = @"locked";
        else if (![UIApplication.sharedApplication launchApplicationWithIdentifier:bundleID suspended:NO])
            error = @"open failed";
    });
    return error;
}
