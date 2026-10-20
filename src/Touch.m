#import "Touch.h"
#import "Auth.h"
#import "HID.h"
#import <mach/mach_time.h>
#import <os/log.h>
#import <stdatomic.h>
#import <sys/sysctl.h>

#define kIOHIDEventTypeDigitizer 11
#define kIOHIDDigitizerTransducerTypeHand 3
#define DigitizerField(n) (kIOHIDEventTypeDigitizer << 16 | (n))
#define kIOHIDEventFieldDigitizerEventMask DigitizerField(7)
#define kIOHIDEventFieldDigitizerRange DigitizerField(8)
#define kIOHIDEventFieldDigitizerTouch DigitizerField(9)
#define kIOHIDEventFieldDigitizerIsDisplayIntegrated DigitizerField(25)
enum { kRange = 1, kTouch = 2, kPosition = 4, kIdentity = 0x20 }; // kIOHIDDigitizerEvent*

#define MAX_FINGER 10

static IOHIDEventSystemClientRef client;
static dispatch_queue_t queue; // owns `fingers` and every dispatch, so events keep their order
// ponytail: one finger table for all connections; two clients using the same finger number share it
static struct { BOOL down; double x, y; } fingers[MAX_FINGER + 1];
static _Atomic uint64_t senderID; // 0 until learned

// --- sender ID: copied from a real touch, cached for this boot so a respring doesn't need a new one

static long BootTime(void) {
    struct timeval tv = {0};
    size_t len = sizeof tv;
    sysctlbyname("kern.boottime", &tv, &len, NULL, 0);
    return tv.tv_sec;
}

static NSString *CachePath(void) {
    return CTStatePath(@"touch.plist");
}

static void OnHIDEvent(void *target, void *refcon, void *sender, IOHIDEventRef event) {
    if (atomic_load(&senderID) || IOHIDEventGetType(event) != kIOHIDEventTypeDigitizer ||
        !IOHIDEventGetIntegerValue(event, kIOHIDEventFieldDigitizerIsDisplayIntegrated)) return;
    uint64_t sid = IOHIDEventGetSenderID(event);
    if (!sid) return;
    atomic_store(&senderID, sid);
    [@{@"senderID": @(sid), @"boot": @(BootTime())} writeToURL:[NSURL fileURLWithPath:CachePath()] error:NULL];
    os_log(OS_LOG_DEFAULT, "crappytouch: touchscreen sender 0x%llx", sid);
    dispatch_async(dispatch_get_main_queue(), ^{ // not from inside the callback
        IOHIDEventSystemClientUnregisterEventCallback(client);
        IOHIDEventSystemClientUnscheduleWithRunLoop(client, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    });
}

void CTTouchStart(void) {
    queue = dispatch_queue_create("crappytouch.touch", DISPATCH_QUEUE_SERIAL);
    client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) {
        os_log_error(OS_LOG_DEFAULT, "crappytouch: no HID event system client, touch disabled");
        return;
    }
    NSDictionary *cache = [NSDictionary dictionaryWithContentsOfFile:CachePath()];
    if ([cache[@"boot"] isEqual:@(BootTime())] && [cache[@"senderID"] unsignedLongLongValue]) {
        atomic_store(&senderID, [cache[@"senderID"] unsignedLongLongValue]);
        return;
    }
    IOHIDEventSystemClientScheduleWithRunLoop(client, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
    IOHIDEventSystemClientRegisterEventCallback(client, OnHIDEvent, NULL, NULL);
}

BOOL CTTouchReady(void) {
    return atomic_load(&senderID) != 0;
}

// --- injection (on `queue`)

// One hand event carrying every finger that is down or changed; masks[i] = what changed for finger i.
static void Dispatch(const uint32_t masks[MAX_FINGER + 1]) {
    uint64_t now = mach_absolute_time();
    IOHIDEventRef hand = IOHIDEventCreateDigitizerEvent(kCFAllocatorDefault, now, kIOHIDDigitizerTransducerTypeHand,
                                                        0, 0, 0, 0, 0, 0, 0, 0, 0, false, false, 0);
    uint32_t handMask = 0;
    BOOL touching = NO;
    for (int i = 1; i <= MAX_FINGER; i++) {
        if (!masks[i] && !fingers[i].down) continue;
        BOOL down = fingers[i].down;
        IOHIDEventRef finger = IOHIDEventCreateDigitizerFingerEvent(
            kCFAllocatorDefault, now, i, i, masks[i], fingers[i].x, fingers[i].y, 0, down ? 1 : 0, 0, down, down, 0);
        IOHIDEventAppendEvent(hand, finger, 0);
        CFRelease(finger);
        handMask |= masks[i];
        touching |= down;
    }
    IOHIDEventSetIntegerValue(hand, kIOHIDEventFieldDigitizerEventMask, handMask);
    IOHIDEventSetIntegerValue(hand, kIOHIDEventFieldDigitizerRange, touching);
    IOHIDEventSetIntegerValue(hand, kIOHIDEventFieldDigitizerTouch, touching);
    IOHIDEventSetIntegerValue(hand, kIOHIDEventFieldDigitizerIsDisplayIntegrated, 1);
    IOHIDEventSetSenderID(hand, atomic_load(&senderID));
    IOHIDEventSystemClientDispatchEvent(client, hand);
    CFRelease(hand);
}

static double Fraction(id v) {
    double d = [v isKindOfClass:NSNumber.class] ? [v doubleValue] : NAN;
    return isnan(d) ? NAN : fmin(fmax(d, 0), 1);
}

void CTTouch(NSArray *events, NSMutableIndexSet *held) {
    if (![events isKindOfClass:NSArray.class] || !CTTouchReady()) return;
    dispatch_async(queue, ^{
        uint32_t masks[MAX_FINGER + 1] = {0};
        BOOL any = NO;
        for (NSDictionary *e in events) {
            if (![e isKindOfClass:NSDictionary.class] || ![e[@"finger"] isKindOfClass:NSNumber.class]) continue;
            int i = [e[@"finger"] intValue];
            NSString *phase = e[@"phase"];
            double x = Fraction(e[@"x"]), y = Fraction(e[@"y"]);
            if (i < 1 || i > MAX_FINGER || isnan(x) || isnan(y)) continue;
            if ([phase isEqual:@"down"] && !fingers[i].down) {
                fingers[i].down = YES;
                masks[i] |= kRange | kTouch | kIdentity | kPosition;
                [held addIndex:i];
            } else if ([phase isEqual:@"move"] || [phase isEqual:@"down"]) { // repeated down = move
                if (!fingers[i].down) continue;
                masks[i] |= kPosition;
            } else if ([phase isEqual:@"up"] && fingers[i].down) {
                fingers[i].down = NO;
                masks[i] |= kRange | kTouch;
                [held removeIndex:i];
            } else continue;
            fingers[i].x = x;
            fingers[i].y = y;
            any = YES;
        }
        if (any) Dispatch(masks);
    });
}

void CTTouchRelease(NSMutableIndexSet *held) {
    if (!queue) return;
    dispatch_sync(queue, ^{
        if (!held.count) return;
        uint32_t masks[MAX_FINGER + 1] = {0};
        for (NSUInteger i = held.firstIndex; i != NSNotFound; i = [held indexGreaterThanIndex:i]) {
            fingers[i].down = NO;
            masks[i] = kRange | kTouch;
        }
        [held removeAllIndexes];
        Dispatch(masks);
    });
}

NSUInteger CTTouchFingersDown(void) {
    if (!queue) return 0;
    __block NSUInteger n = 0;
    dispatch_sync(queue, ^{
        for (int i = 1; i <= MAX_FINGER; i++) n += fingers[i].down;
    });
    return n;
}
