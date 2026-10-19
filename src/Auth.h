#import <Foundation/Foundation.h>

// Random bytes from SecRandomCopyBytes; nil only if the system RNG fails.
NSData *SARandomBytes(size_t n);
NSString *SAHex(NSData *data);
NSData *SAUnhex(NSString *hex); // nil unless an even-length string of hex digits
// `file` in the agent's private state dir (created, mode 700, if missing).
NSString *SAStatePath(NSString *file);

typedef NS_ENUM(NSInteger, SAAuthResult) { SAAuthOK, SAAuthUnknownHost, SAAuthBadMac };

// Checks `mac` = hex HMAC-SHA256(key, nonce) for the host `hostID` in hosts.plist (PROTOCOL.md).
SAAuthResult SAAuthCheck(NSString *hostID, NSString *mac, NSData *nonce);

// Remembers the computer that owns `secret` (32 bytes) under its derived id; NO if hosts.plist can't be written.
BOOL SAAuthAddHost(NSString *name, NSData *secret);
