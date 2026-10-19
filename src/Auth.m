#import "Auth.h"
#import <CommonCrypto/CommonHMAC.h>
#import <Security/Security.h>
#import <rootless.h>
#import <string.h>

static NSString *HostsPath(void) {
    return ROOT_PATH_NS(@"/var/mobile/Library/scrcrappy-agent/hosts.plist");
}

NSData *SARandomBytes(size_t n) {
    NSMutableData *data = [NSMutableData dataWithLength:n];
    return SecRandomCopyBytes(kSecRandomDefault, n, data.mutableBytes) == errSecSuccess ? data : nil;
}

NSString *SAHex(NSData *data) {
    const uint8_t *b = data.bytes;
    NSMutableString *s = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) [s appendFormat:@"%02x", b[i]];
    return s;
}

NSData *SAUnhex(NSString *hex) {
    if (![hex isKindOfClass:NSString.class] || hex.length % 2) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:hex.length / 2];
    uint8_t *out = data.mutableBytes;
    for (NSUInteger i = 0; i < hex.length; i++) {
        unichar c = [hex characterAtIndex:i];
        int v = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10
              : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
        if (v < 0) return nil;
        out[i / 2] = (uint8_t)(out[i / 2] << 4 | v);
    }
    return data;
}

SAAuthResult SAAuthCheck(NSString *hostID, NSString *mac, NSData *nonce) {
    if (![hostID isKindOfClass:NSString.class]) return SAAuthUnknownHost;
    NSDictionary *hosts = [NSDictionary dictionaryWithContentsOfFile:HostsPath()];
    NSDictionary *host = hosts[hostID];
    NSData *key = [host isKindOfClass:NSDictionary.class] ? host[@"key"] : nil;
    if (![key isKindOfClass:NSData.class]) return SAAuthUnknownHost;

    uint8_t expected[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, nonce.bytes, nonce.length, expected);
    NSData *got = SAUnhex(mac);
    if (got.length != sizeof expected || timingsafe_bcmp(got.bytes, expected, sizeof expected))
        return SAAuthBadMac;
    return SAAuthOK;
}
