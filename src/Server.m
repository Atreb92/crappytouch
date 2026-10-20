#import "Server.h"
#import "Auth.h"
#import "Pairing.h"
#import "Touch.h"
#import "Keyboard.h"
#import "Clipboard.h"
#import "Screen.h"
#import "Apps.h"
#import "Awake.h"
#import <arpa/inet.h>
#import <errno.h>
#import <os/log.h>
#import <stdatomic.h>
#import <sys/socket.h>
#import <unistd.h>

#define MAX_FRAME (16u << 20)
#define MAX_FRAME_BEFORE_AUTH (64u << 10) // an unauthenticated client can't make SpringBoard allocate 16 MiB
#define MAX_CLIENTS 8                     // one thread each
#define HELD_TIMEOUT_S 10                 // a computer silent this long with a finger held has its fingers lifted
#define SEND_TIMEOUT_S 10                 // a computer that stops reading can't block its thread forever
#define AUTH_TIMEOUT_S 10                 // ponytail: per read, not a deadline; a byte trickler keeps a slot, cap covers it

static atomic_int clientCount;
static NSMutableDictionary<NSNumber *, NSString *> *live; // fd -> host id of each authenticated session; @synchronized

// `timedOut`: set when SO_RCVTIMEO fired before the first byte (a quiet connection, not a broken frame).
static BOOL ReadExact(int fd, void *buf, size_t n, BOOL *timedOut) {
    for (size_t got = 0; got < n;) {
        ssize_t r = recv(fd, (uint8_t *)buf + got, n - got, 0);
        if (r > 0) got += r;
        else if (r < 0 && errno == EINTR) continue;
        else {
            if (r < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) && got == 0 && timedOut) *timedOut = YES;
            return NO; // EOF, error or SO_RCVTIMEO
        }
    }
    return YES;
}

// nil = close the connection (EOF, timeout, oversized, not a JSON object), unless *idle: it was just quiet.
static NSDictionary *ReadFrame(int fd, uint32_t max, BOOL *idle) {
    uint32_t len;
    if (!ReadExact(fd, &len, 4, idle)) return nil;
    len = ntohl(len);
    if (len > max) return nil;
    NSMutableData *body = [NSMutableData dataWithLength:len];
    if (!ReadExact(fd, body.mutableBytes, len, NULL)) return nil;
    id obj = [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL];
    return [obj isKindOfClass:NSDictionary.class] ? obj : nil;
}

static BOOL WriteFrame(int fd, NSDictionary *obj) {
    NSData *body = [NSJSONSerialization dataWithJSONObject:obj options:0 error:NULL];
    uint32_t len = htonl((uint32_t)body.length);
    NSMutableData *frame = [NSMutableData dataWithBytes:&len length:4];
    [frame appendData:body];
    const uint8_t *p = frame.bytes;
    for (size_t sent = 0; sent < frame.length;) {
        ssize_t w = send(fd, p + sent, frame.length - sent, 0);
        if (w > 0) sent += w;
        else if (w < 0 && errno == EINTR) continue;
        else return NO;
    }
    return YES;
}

static void SetReadTimeout(int fd, int seconds) {
    struct timeval tv = {.tv_sec = seconds};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
}

static void SetWriteTimeout(int fd, int seconds) {
    struct timeval tv = {.tv_sec = seconds};
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
}

// Commands after auth; nil = no reply (touch). `held` = fingers this connection holds down.
static NSDictionary *HandleCommand(NSString *cmd, NSDictionary *msg, NSMutableIndexSet *held) {
    if ([cmd isEqual:@"touch"]) {
        CTTouch(msg[@"events"], held);
        return nil;
    }
    if ([cmd isEqual:@"key"]) {
        id page = msg[@"page"] ?: @7, usage = msg[@"usage"], mods = msg[@"modifiers"] ?: @0;
        BOOL ok = [page isKindOfClass:NSNumber.class] && [usage isKindOfClass:NSNumber.class] &&
                  [mods isKindOfClass:NSNumber.class] && CTKey([page integerValue], [usage integerValue], [mods integerValue]);
        return ok ? @{@"ok": @YES} : @{@"error": @"bad key"};
    }
    if ([cmd isEqual:@"text"] || [cmd isEqual:@"clipboard_set"]) {
        NSString *text = msg[@"text"];
        if (![text isKindOfClass:NSString.class]) return @{@"error": @"bad text"};
        if ([cmd isEqual:@"clipboard_set"]) CTClipboardSet(text);
        else if (!CTText(text)) return @{@"error": @"can't type"};
        return @{@"ok": @YES};
    }
    if ([cmd isEqual:@"clipboard_get"]) {
        NSString *text = CTClipboardGet();
        return text ? @{@"ok": @YES, @"text": text} : @{@"error": @"clipboard timeout"};
    }
    if ([cmd isEqual:@"screen"]) {
        NSMutableDictionary *r = [CTScreenInfo() mutableCopy];
        [r addEntriesFromDictionary:@{@"ok": @YES, @"touch_ready": @(CTTouchReady()),
                                      @"fingers_down": @(CTTouchFingersDown())}];
        return r;
    }
    if ([cmd isEqual:@"screenshot"]) {
        NSData *png = CTScreenshotPNG();
        return png ? @{@"ok": @YES, @"png": [png base64EncodedStringWithOptions:0]} : @{@"error": @"screenshot failed"};
    }
    if ([cmd isEqual:@"apps"]) return @{@"ok": @YES, @"apps": CTApps()};
    if ([cmd isEqual:@"open"]) {
        NSString *bundleID = msg[@"id"];
        NSString *error = [bundleID isKindOfClass:NSString.class] ? CTOpenApp(bundleID) : @"unknown app";
        return error ? @{@"error": error} : @{@"ok": @YES};
    }
    if ([cmd isEqual:@"open_url"]) {
        NSString *error = CTOpenURL(msg[@"url"]);
        return error ? @{@"error": error} : @{@"ok": @YES};
    }
    return @{@"error": @"unknown command"};
}

static void ServeClient(int fd) {
    NSData *nonce = CTRandomBytes(16);
    NSString *hostID = nil;
    struct sockaddr_in local;
    socklen_t local_len = sizeof local;
    char addr[INET_ADDRSTRLEN] = "";
    if (getsockname(fd, (struct sockaddr *)&local, &local_len) == 0)
        inet_ntop(AF_INET, &local.sin_addr, addr, sizeof addr);
    if (!nonce || !WriteFrame(fd, @{@"hello": @1, @"nonce": CTHex(nonce), @"addr": @(addr)})) return;

    SetReadTimeout(fd, AUTH_TIMEOUT_S);
    for (;;) { // until authenticated
        NSDictionary *msg = ReadFrame(fd, MAX_FRAME_BEFORE_AUTH, NULL);
        if (!msg) return;
        NSString *cmd = msg[@"cmd"];
        if ([cmd isEqual:@"auth"]) {
            CTAuthResult r = CTAuthCheck(msg[@"id"], msg[@"mac"], nonce);
            if (r != CTAuthOK) { // one try per nonce
                WriteFrame(fd, @{@"error": r == CTAuthUnknownHost ? @"unknown host" : @"bad mac"});
                return;
            }
            if (!WriteFrame(fd, @{@"ok": @YES})) return;
            hostID = msg[@"id"];
            os_log(OS_LOG_DEFAULT, "crappytouch: authenticated %{public}@",
                   [msg[@"host"] isKindOfClass:NSString.class] ? msg[@"host"] : @"?");
            break;
        } else if ([cmd isEqual:@"pair"]) {
            NSString *name = msg[@"host"];
            NSData *secret = CTUnhex(msg[@"secret"]);
            NSString *error = ![name isKindOfClass:NSString.class] || !name.length || name.length > 64 ||
                              [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound ? @"bad host name"
                            : secret.length != 32 ? @"bad secret"
                            : CTPair(name, secret);
            if (!WriteFrame(fd, error ? @{@"error": error} : @{@"ok": @YES})) return;
        } else {
            WriteFrame(fd, @{@"error": @"auth required"});
            return;
        }
    }

    SetWriteTimeout(fd, SEND_TIMEOUT_S);
    NSNumber *key = @(fd);
    @synchronized(live) { live[key] = hostID; }
    NSMutableIndexSet *held = [NSMutableIndexSet indexSet];
    CTAwakeConnected();
    @try {
        for (;;) {
            SetReadTimeout(fd, held.count ? HELD_TIMEOUT_S : 0);
            BOOL idle = NO;
            NSDictionary *msg = ReadFrame(fd, MAX_FRAME, &idle);
            if (!msg) {
                if (!idle) return;
                CTTouchRelease(held); // silent with a finger down: lift it, keep the connection
                continue;
            }
            NSString *cmd = msg[@"cmd"];
            NSDictionary *reply = [cmd isKindOfClass:NSString.class] ? HandleCommand(cmd, msg, held)
                                                                    : @{@"error": @"missing cmd"};
            if (reply && !WriteFrame(fd, reply)) return;
        }
    } @finally { // a finger left down would block the whole screen
        @synchronized(live) { [live removeObjectForKey:key]; }
        CTTouchRelease(held);
        CTAwakeDisconnected();
    }
}

static void AcceptLoop(int listener) {
    for (;;) {
        int fd = accept(listener, NULL, NULL);
        if (fd < 0) {
            if (errno != EINTR) usleep(100000); // e.g. EMFILE: don't spin
            continue;
        }
        int one = 1;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        if (atomic_fetch_add(&clientCount, 1) >= MAX_CLIENTS) {
            atomic_fetch_sub(&clientCount, 1);
            close(fd);
            continue;
        }
        [NSThread detachNewThreadWithBlock:^{
            @autoreleasepool {
                @try {
                    ServeClient(fd);
                } @catch (NSException *e) { // never take SpringBoard down because of a client
                    os_log_error(OS_LOG_DEFAULT, "crappytouch: %{public}@", e);
                }
            }
            close(fd);
            atomic_fetch_sub(&clientCount, 1);
        }];
    }
}

// Settings removed a computer: cut the live sessions of every host that is no longer paired. shutdown() makes
// the session thread's read fail, so its normal teardown lifts held fingers.
static void DropRevokedSessions(void) {
    NSMutableSet *paired = [NSMutableSet set];
    for (NSDictionary *h in CTAuthListHosts()) [paired addObject:h[@"id"]];
    @synchronized(live) {
        [live enumerateKeysAndObjectsUsingBlock:^(NSNumber *fd, NSString *hostID, BOOL *stop) {
            if (![paired containsObject:hostID]) shutdown(fd.intValue, SHUT_RDWR);
        }];
    }
}

static void OnRevoked(CFNotificationCenterRef c, void *o, CFNotificationName n, const void *obj, CFDictionaryRef u) {
    DropRevokedSessions();
}

void CTServerStart(void) {
    live = [NSMutableDictionary dictionary];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, OnRevoked,
                                    CFSTR(CT_REVOKED_NOTIFICATION), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in sa = {.sin_len = sizeof sa, .sin_family = AF_INET, .sin_port = htons(CT_PORT),
                             .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    if (listener < 0 || bind(listener, (struct sockaddr *)&sa, sizeof sa) || listen(listener, 8)) {
        os_log_error(OS_LOG_DEFAULT, "crappytouch: can't listen on 127.0.0.1:%d: %{errno}d", CT_PORT, errno);
        if (listener >= 0) close(listener);
        return;
    }
    os_log(OS_LOG_DEFAULT, "crappytouch: listening on 127.0.0.1:%d", CT_PORT);
    [NSThread detachNewThreadWithBlock:^{ AcceptLoop(listener); }];
}
