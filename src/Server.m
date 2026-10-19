#import "Server.h"
#import "Auth.h"
#import "Pairing.h"
#import "Touch.h"
#import <arpa/inet.h>
#import <errno.h>
#import <os/log.h>
#import <stdatomic.h>
#import <sys/socket.h>
#import <unistd.h>

#define MAX_FRAME (16u << 20)
#define MAX_FRAME_BEFORE_AUTH (64u << 10) // an unauthenticated client can't make SpringBoard allocate 16 MiB
#define MAX_CLIENTS 8                     // one thread each
#define AUTH_TIMEOUT_S 10                 // ponytail: per read, not a deadline; a byte trickler keeps a slot, cap covers it

static atomic_int clientCount;

static BOOL ReadExact(int fd, void *buf, size_t n) {
    for (size_t got = 0; got < n;) {
        ssize_t r = recv(fd, (uint8_t *)buf + got, n - got, 0);
        if (r > 0) got += r;
        else if (r < 0 && errno == EINTR) continue;
        else return NO; // EOF, error or SO_RCVTIMEO
    }
    return YES;
}

// nil = close the connection (EOF, timeout, oversized, not a JSON object).
static NSDictionary *ReadFrame(int fd, uint32_t max) {
    uint32_t len;
    if (!ReadExact(fd, &len, 4)) return nil;
    len = ntohl(len);
    if (len > max) return nil;
    NSMutableData *body = [NSMutableData dataWithLength:len];
    if (!ReadExact(fd, body.mutableBytes, len)) return nil;
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

// Commands after auth; nil = no reply (touch). `held` = fingers this connection holds down.
static NSDictionary *HandleCommand(NSString *cmd, NSDictionary *msg, NSMutableIndexSet *held) {
    if ([cmd isEqual:@"touch"]) {
        SATouch(msg[@"events"], held);
        return nil;
    }
    if ([cmd isEqual:@"screen"]) // size and orientation: Task 7
        return @{@"ok": @YES, @"touch_ready": @(SATouchReady()), @"fingers_down": @(SATouchFingersDown())};
    return @{@"error": @"unknown command"};
}

static void ServeClient(int fd) {
    NSData *nonce = SARandomBytes(16);
    struct sockaddr_in local;
    socklen_t local_len = sizeof local;
    char addr[INET_ADDRSTRLEN] = "";
    if (getsockname(fd, (struct sockaddr *)&local, &local_len) == 0)
        inet_ntop(AF_INET, &local.sin_addr, addr, sizeof addr);
    if (!nonce || !WriteFrame(fd, @{@"hello": @1, @"nonce": SAHex(nonce), @"addr": @(addr)})) return;

    SetReadTimeout(fd, AUTH_TIMEOUT_S);
    for (;;) { // until authenticated
        NSDictionary *msg = ReadFrame(fd, MAX_FRAME_BEFORE_AUTH);
        if (!msg) return;
        NSString *cmd = msg[@"cmd"];
        if ([cmd isEqual:@"auth"]) {
            SAAuthResult r = SAAuthCheck(msg[@"id"], msg[@"mac"], nonce);
            if (r != SAAuthOK) { // one try per nonce
                WriteFrame(fd, @{@"error": r == SAAuthUnknownHost ? @"unknown host" : @"bad mac"});
                return;
            }
            if (!WriteFrame(fd, @{@"ok": @YES})) return;
            os_log(OS_LOG_DEFAULT, "scrcrappy-agent: authenticated %{public}@",
                   [msg[@"host"] isKindOfClass:NSString.class] ? msg[@"host"] : @"?");
            break;
        } else if ([cmd isEqual:@"pair"]) {
            NSString *name = msg[@"host"];
            NSData *secret = SAUnhex(msg[@"secret"]);
            NSString *error = ![name isKindOfClass:NSString.class] || !name.length || name.length > 64 ? @"bad host name"
                            : secret.length != 32 ? @"bad secret"
                            : SAPair(name, secret);
            if (!WriteFrame(fd, error ? @{@"error": error} : @{@"ok": @YES})) return;
        } else {
            WriteFrame(fd, @{@"error": @"auth required"});
            return;
        }
    }

    SetReadTimeout(fd, 0);
    NSMutableIndexSet *held = [NSMutableIndexSet indexSet];
    @try {
        for (NSDictionary *msg; (msg = ReadFrame(fd, MAX_FRAME));) {
            NSString *cmd = msg[@"cmd"];
            NSDictionary *reply = [cmd isKindOfClass:NSString.class] ? HandleCommand(cmd, msg, held)
                                                                    : @{@"error": @"missing cmd"};
            if (reply && !WriteFrame(fd, reply)) return;
        }
    } @finally { // a finger left down would block the whole screen
        SATouchRelease(held);
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
                    os_log_error(OS_LOG_DEFAULT, "scrcrappy-agent: %{public}@", e);
                }
            }
            close(fd);
            atomic_fetch_sub(&clientCount, 1);
        }];
    }
}

void SAServerStart(void) {
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    int one = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in sa = {.sin_len = sizeof sa, .sin_family = AF_INET, .sin_port = htons(SA_PORT),
                             .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    if (listener < 0 || bind(listener, (struct sockaddr *)&sa, sizeof sa) || listen(listener, 8)) {
        os_log_error(OS_LOG_DEFAULT, "scrcrappy-agent: can't listen on 127.0.0.1:%d: %{errno}d", SA_PORT, errno);
        if (listener >= 0) close(listener);
        return;
    }
    os_log(OS_LOG_DEFAULT, "scrcrappy-agent: listening on 127.0.0.1:%d", SA_PORT);
    [NSThread detachNewThreadWithBlock:^{ AcceptLoop(listener); }];
}
