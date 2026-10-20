#import "Auth.h"
#import <CommonCrypto/CommonHMAC.h>
#import <Security/Security.h>
#import <rootless.h>
#import <string.h>

NSString *CTStatePath(NSString *file) {
    NSString *dir = ROOT_PATH_NS(@"/var/mobile/Library/crappytouch");
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES
                                             attributes:@{NSFilePosixPermissions: @0700} error:NULL];
    return [dir stringByAppendingPathComponent:file];
}

static NSString *HostsPath(void) {
    return CTStatePath(@"hosts.plist");
}

static NSData *SHA256WithPrefix(NSString *prefix, NSData *secret) {
    NSMutableData *input = [[prefix dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    [input appendData:secret];
    NSMutableData *digest = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(input.bytes, (CC_LONG)input.length, digest.mutableBytes);
    return digest;
}

NSData *CTRandomBytes(size_t n) {
    NSMutableData *data = [NSMutableData dataWithLength:n];
    return SecRandomCopyBytes(kSecRandomDefault, n, data.mutableBytes) == errSecSuccess ? data : nil;
}

NSString *CTHex(NSData *data) {
    const uint8_t *b = data.bytes;
    NSMutableString *s = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) [s appendFormat:@"%02x", b[i]];
    return s;
}

NSData *CTUnhex(NSString *hex) {
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

CTAuthResult CTAuthCheck(NSString *hostID, NSString *mac, NSData *nonce) {
    if (![hostID isKindOfClass:NSString.class]) return CTAuthUnknownHost;
    NSDictionary *hosts = [NSDictionary dictionaryWithContentsOfFile:HostsPath()];
    NSDictionary *host = hosts[hostID];
    NSData *key = [host isKindOfClass:NSDictionary.class] ? host[@"key"] : nil;
    if (![key isKindOfClass:NSData.class]) return CTAuthUnknownHost;

    uint8_t expected[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, nonce.bytes, nonce.length, expected);
    NSData *got = CTUnhex(mac);
    if (got.length != sizeof expected || timingsafe_bcmp(got.bytes, expected, sizeof expected))
        return CTAuthBadMac;
    return CTAuthOK;
}

BOOL CTAuthAddHost(NSString *name, NSData *secret) {
    NSMutableDictionary *hosts = [[NSDictionary dictionaryWithContentsOfFile:HostsPath()] mutableCopy]
                                 ?: [NSMutableDictionary dictionary];
    hosts[CTHex(SHA256WithPrefix(@"scrcrappy-id", secret))] =
        @{@"name": name, @"key": SHA256WithPrefix(@"scrcrappy-key", secret)};
    NSURL *url = [NSURL fileURLWithPath:HostsPath()];
    return [hosts writeToURL:url error:NULL] &&
           [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:HostsPath() error:NULL];
}
