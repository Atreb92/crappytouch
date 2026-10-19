#import <Foundation/Foundation.h>

// Random bytes from SecRandomCopyBytes; nil only if the system RNG fails.
NSData *SARandomBytes(size_t n);
NSString *SAHex(NSData *data);
NSData *SAUnhex(NSString *hex); // nil unless an even-length string of hex digits

typedef NS_ENUM(NSInteger, SAAuthResult) { SAAuthOK, SAAuthUnknownHost, SAAuthBadMac };

// Checks `mac` = hex HMAC-SHA256(key, nonce) for the host `hostID` in hosts.plist (PROTOCOL.md).
SAAuthResult SAAuthCheck(NSString *hostID, NSString *mac, NSData *nonce);
