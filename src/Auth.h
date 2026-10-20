#import <Foundation/Foundation.h>

// Random bytes from SecRandomCopyBytes; nil only if the system RNG fails.
NSData *CTRandomBytes(size_t n);
NSString *CTHex(NSData *data);
NSData *CTUnhex(NSString *hex); // nil unless an even-length string of hex digits
// `file` in the agent's private state dir (created, mode 700, if missing).
NSString *CTStatePath(NSString *file);

typedef NS_ENUM(NSInteger, CTAuthResult) { CTAuthOK, CTAuthUnknownHost, CTAuthBadMac };

// Checks `mac` = hex HMAC-SHA256(key, nonce) for the host `hostID` in hosts.plist (PROTOCOL.md).
CTAuthResult CTAuthCheck(NSString *hostID, NSString *mac, NSData *nonce);

// Remembers the computer that owns `secret` (32 bytes) under its derived id; NO if hosts.plist can't be written.
BOOL CTAuthAddHost(NSString *name, NSData *secret);
