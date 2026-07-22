// Copyright 2005-2024 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.
//
// Certificate operations reimplemented using Apple Security framework
// (replaces the original OpenSSL implementation).

#import <MumbleKit/MKCertificate.h>
#import "MKDistinguishedNameParser.h"

#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>

NSString *MKCertificateItemCommonName   = @"CN";
NSString *MKCertificateItemCountry      = @"C";
NSString *MKCertificateItemOrganization = @"O";
NSString *MKCertificateItemSerialNumber = @"serialNumber";

// ---------------------------------------------------------------------------
// Minimal ASN.1 / DER helpers needed to build a self-signed X.509 certificate
// ---------------------------------------------------------------------------

static void der_append(NSMutableData *d, uint8_t tag, NSData *content) {
    uint8_t t = tag;
    [d appendBytes:&t length:1];
    NSUInteger len = content.length;
    if (len < 0x80) {
        uint8_t l = (uint8_t)len;
        [d appendBytes:&l length:1];
    } else if (len <= 0xFF) {
        uint8_t hdr[2] = {0x81, (uint8_t)len};
        [d appendBytes:hdr length:2];
    } else {
        uint8_t hdr[3] = {0x82, (uint8_t)(len >> 8), (uint8_t)len};
        [d appendBytes:hdr length:3];
    }
    [d appendData:content];
}

static NSData *der_seq(NSData *inner) {
    NSMutableData *r = [NSMutableData data];
    der_append(r, 0x30, inner);
    return r;
}

static NSData *der_set(NSData *inner) {
    NSMutableData *r = [NSMutableData data];
    der_append(r, 0x31, inner);
    return r;
}

static NSData *der_integer_small(uint8_t v) {
    uint8_t buf[3] = {0x02, 0x01, v};
    return [NSData dataWithBytes:buf length:3];
}

static NSData *der_utf8string(NSString *s) {
    NSData *utf8 = [s dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *r = [NSMutableData data];
    der_append(r, 0x0C, utf8);
    return r;
}

static NSData *der_ia5string(NSString *s) {
    NSData *ascii = [s dataUsingEncoding:NSASCIIStringEncoding];
    NSMutableData *r = [NSMutableData data];
    der_append(r, 0x16, ascii ?: [NSData data]);
    return r;
}

static NSData *der_utctime(NSString *s) { // "YYMMDDHHMMSSZ"
    NSData *ascii = [s dataUsingEncoding:NSASCIIStringEncoding];
    NSMutableData *r = [NSMutableData data];
    der_append(r, 0x17, ascii);
    return r;
}

static NSData *der_oid(const uint8_t *bytes, NSUInteger len) {
    NSMutableData *r = [NSMutableData data];
    der_append(r, 0x06, [NSData dataWithBytes:bytes length:len]);
    return r;
}

static NSData *der_bitstring_with_leading_zero(NSData *inner) {
    NSMutableData *wrapped = [NSMutableData data];
    uint8_t zero = 0x00;
    [wrapped appendBytes:&zero length:1];
    [wrapped appendData:inner];
    NSMutableData *r = [NSMutableData data];
    der_append(r, 0x03, wrapped);
    return r;
}

static NSData *der_explicit_context(uint8_t ctx, NSData *inner) {
    NSMutableData *r = [NSMutableData data];
    uint8_t tag = 0xA0 | ctx;
    der_append(r, tag, inner);
    return r;
}

// OID bytes
static const uint8_t oid_sha256WithRSA[] = {0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x0b};
static const uint8_t oid_rsaEncryption[] = {0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01};
static const uint8_t oid_commonName[]    = {0x55,0x04,0x03};
static const uint8_t oid_subjectAltName[]= {0x55,0x1d,0x11};
static const uint8_t oid_basicConstraints[]   = {0x55,0x1d,0x13};
static const uint8_t oid_extKeyUsage[]        = {0x55,0x1d,0x25};
static const uint8_t oid_clientAuth[]         = {0x2b,0x06,0x01,0x05,0x05,0x07,0x03,0x02};
static const uint8_t oid_subjectKeyId[]       = {0x55,0x1d,0x0e};

static NSData *der_name_with_cn(NSString *cn) {
    NSMutableData *rdn = [NSMutableData data];
    [rdn appendData:der_oid(oid_commonName, sizeof(oid_commonName))];
    [rdn appendData:der_utf8string(cn)];
    return der_set(der_seq(rdn));
}

static NSData *build_self_signed_tbs(NSString *cn, NSString *email, NSData *spkiDER) {
    NSMutableData *tbs = [NSMutableData data];

    // version [0] EXPLICIT v3 (2)
    [tbs appendData:der_explicit_context(0, der_integer_small(2))];
    // serialNumber 1
    [tbs appendData:der_integer_small(1)];
    // signature alg
    NSMutableData *sigAlg = [NSMutableData data];
    [sigAlg appendData:der_oid(oid_sha256WithRSA, sizeof(oid_sha256WithRSA))];
    uint8_t null_val[2] = {0x05, 0x00};
    [sigAlg appendBytes:null_val length:2];
    [tbs appendData:der_seq(sigAlg)];
    // issuer = subject = CN
    NSData *name = der_name_with_cn(cn ?: @"Mumble User");
    [tbs appendData:name];
    // validity: now .. now+20years
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat:@"yyMMddHHmmss'Z'"];
    [fmt setTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    NSDate *now = [NSDate date];
    NSDate *expire = [NSDate dateWithTimeIntervalSinceNow:60*60*24*365*20];
    NSMutableData *validity = [NSMutableData data];
    [validity appendData:der_utctime([fmt stringFromDate:now])];
    [validity appendData:der_utctime([fmt stringFromDate:expire])];
    [tbs appendData:der_seq(validity)];
    [fmt release];
    // subject
    [tbs appendData:name];
    // subjectPublicKeyInfo (already DER-encoded as SPKI by SecKeyCopyExternalRepresentation on macOS,
    // but on iOS the raw PKCS#1 is returned, so we need to wrap it)
    [tbs appendData:spkiDER];

    // Extensions [3]
    NSMutableData *exts = [NSMutableData data];

    // basicConstraints: CA:FALSE
    {
        NSMutableData *ext = [NSMutableData data];
        [ext appendData:der_oid(oid_basicConstraints, sizeof(oid_basicConstraints))];
        uint8_t critical[4] = {0x01, 0x01, 0xff, 0x00}; // BOOLEAN TRUE + padding
        // Actually encode critical flag and value
        uint8_t crit[3] = {0x01, 0x01, 0xff};
        [ext appendBytes:crit length:3];
        // value: OCTET STRING containing SEQUENCE {} (empty = CA:FALSE)
        uint8_t bc_val[4] = {0x04, 0x02, 0x30, 0x00};
        [ext appendBytes:bc_val length:4];
        (void)critical; // suppress unused warning
        [exts appendData:der_seq(ext)];
    }

    // extKeyUsage: clientAuth
    {
        NSMutableData *ext = [NSMutableData data];
        [ext appendData:der_oid(oid_extKeyUsage, sizeof(oid_extKeyUsage))];
        NSMutableData *eku_inner = [NSMutableData data];
        [eku_inner appendData:der_oid(oid_clientAuth, sizeof(oid_clientAuth))];
        NSData *eku_seq = der_seq(eku_inner);
        NSMutableData *eku_octet = [NSMutableData data];
        der_append(eku_octet, 0x04, eku_seq);
        [ext appendData:eku_octet];
        [exts appendData:der_seq(ext)];
    }

    // subjectAltName with email
    if (email && [email length] > 0) {
        NSMutableData *ext = [NSMutableData data];
        [ext appendData:der_oid(oid_subjectAltName, sizeof(oid_subjectAltName))];
        // RFC822 email is context tag 1
        NSMutableData *san_inner = [NSMutableData data];
        NSData *emailData = [email dataUsingEncoding:NSASCIIStringEncoding];
        uint8_t san_tag = 0x81; // [1] rfc822Name
        [san_inner appendBytes:&san_tag length:1];
        uint8_t san_len = (uint8_t)emailData.length;
        [san_inner appendBytes:&san_len length:1];
        [san_inner appendData:emailData];
        NSData *san_seq = der_seq(san_inner);
        NSMutableData *san_octet = [NSMutableData data];
        der_append(san_octet, 0x04, san_seq);
        [ext appendData:san_octet];
        [exts appendData:der_seq(ext)];
    }

    [tbs appendData:der_explicit_context(3, der_seq(exts))];

    return der_seq(tbs);
}

// Wrap a raw PKCS#1 RSA public key in SubjectPublicKeyInfo DER.
static NSData *spki_from_pkcs1(NSData *pkcs1) {
    NSMutableData *algId = [NSMutableData data];
    [algId appendData:der_oid(oid_rsaEncryption, sizeof(oid_rsaEncryption))];
    uint8_t null_val[2] = {0x05, 0x00};
    [algId appendBytes:null_val length:2];
    NSMutableData *spki = [NSMutableData data];
    [spki appendData:der_seq(algId)];
    [spki appendData:der_bitstring_with_leading_zero(pkcs1)];
    return der_seq(spki);
}

// ---------------------------------------------------------------------------
// MKCertificate
// ---------------------------------------------------------------------------

@interface MKCertificate () {
    NSData          *_derCert;
    NSData          *_derPrivKey;

    NSDictionary    *_subjectDict;
    NSDictionary    *_issuerDict;

    NSDate          *_notAfterDate;
    NSDate          *_notBeforeDate;

    NSMutableArray  *_emailAddresses;
    NSMutableArray  *_dnsEntries;
}
- (void) setCertificate:(NSData *)cert;
- (NSData *) certificate;
- (void) setPrivateKey:(NSData *)pkey;
- (NSData *) privateKey;
- (void) extractCertInfo;
@end

@implementation MKCertificate

+ (void) initialize {
    // Nothing needed — not using OpenSSL
}

- (void) dealloc {
    [_derCert release];
    [_derPrivKey release];
    [_subjectDict release];
    [_issuerDict release];
    [_notAfterDate release];
    [_notBeforeDate release];
    [_emailAddresses release];
    [_dnsEntries release];
    [super dealloc];
}

- (void) setCertificate:(NSData *)cert { _derCert = [cert retain]; }
- (NSData *) certificate { return _derCert; }
- (void) setPrivateKey:(NSData *)pkey { _derPrivKey = [pkey retain]; }
- (NSData *) privateKey { return _derPrivKey; }

+ (MKCertificate *) certificateWithCertificate:(NSData *)cert privateKey:(NSData *)privkey {
    MKCertificate *c = [[MKCertificate alloc] init];
    [c setCertificate:cert];
    [c setPrivateKey:privkey];
    [c extractCertInfo];
    return [c autorelease];
}

+ (MKCertificate *) selfSignedCertificateWithName:(NSString *)name email:(NSString *)email {
    return [self selfSignedCertificateWithName:name email:email rsaKeyPair:nil];
}

+ (MKCertificate *) selfSignedCertificateWithName:(NSString *)name email:(NSString *)email rsaKeyPair:(MKRSAKeyPair *)keyPair {
    if (keyPair == nil)
        keyPair = [MKRSAKeyPair generateKeyPairOfSize:2048 withDelegate:nil];
    if (keyPair == nil)
        return nil;

    NSData *pubPKCS1 = [keyPair publicKey];
    if (pubPKCS1 == nil) return nil;

    NSData *spki = spki_from_pkcs1(pubPKCS1);
    NSString *cn = (name && name.length > 0) ? name : @"Mumble User";
    NSData *tbsDER = build_self_signed_tbs(cn, email, spki);

    // Sign the TBS certificate
    NSData *privDER = [keyPair privateKey];
    if (privDER == nil) return nil;

    CFErrorRef cfErr = NULL;
    NSDictionary *keyAttrs = @{
        (__bridge id)kSecAttrKeyType: (__bridge id)kSecAttrKeyTypeRSA,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate,
    };
    SecKeyRef privKey = SecKeyCreateWithData((__bridge CFDataRef)privDER,
                                             (__bridge CFDictionaryRef)keyAttrs, &cfErr);
    if (privKey == NULL) {
        if (cfErr) CFRelease(cfErr);
        return nil;
    }

    CFDataRef cfSig = SecKeyCreateSignature(
        privKey,
        kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA256,
        (__bridge CFDataRef)tbsDER,
        &cfErr);
    CFRelease(privKey);

    if (cfSig == NULL) {
        if (cfErr) CFRelease(cfErr);
        return nil;
    }
    NSData *signature = [NSData dataWithBytes:CFDataGetBytePtr(cfSig)
                                       length:(NSUInteger)CFDataGetLength(cfSig)];
    CFRelease(cfSig);

    // Build the final Certificate DER: SEQUENCE { tbs, algId, signature }
    NSMutableData *certBody = [NSMutableData data];
    [certBody appendData:tbsDER];

    NSMutableData *sigAlg = [NSMutableData data];
    [sigAlg appendData:der_oid(oid_sha256WithRSA, sizeof(oid_sha256WithRSA))];
    uint8_t null_val[2] = {0x05, 0x00};
    [sigAlg appendBytes:null_val length:2];
    [certBody appendData:der_seq(sigAlg)];
    [certBody appendData:der_bitstring_with_leading_zero(signature)];

    NSData *certDER = der_seq(certBody);

    MKCertificate *cert = [[MKCertificate alloc] init];
    [cert setCertificate:certDER];
    [cert setPrivateKey:privDER];
    [cert extractCertInfo];
    return [cert autorelease];
}

+ (MKCertificate *) certificateWithPKCS12:(NSData *)pkcs12 password:(NSString *)password {
    NSArray *items = nil;
    NSDictionary *opts = password ? @{(__bridge id)kSecImportExportPassphrase: password} : @{};
    OSStatus err = SecPKCS12Import((__bridge CFDataRef)pkcs12,
                                   (__bridge CFDictionaryRef)opts,
                                   (CFArrayRef *)&items);
    if (err != errSecSuccess || items.count == 0) return nil;

    NSDictionary *item = [items objectAtIndex:0];
    SecIdentityRef identity = (__bridge SecIdentityRef)[item objectForKey:(__bridge id)kSecImportItemIdentity];
    if (!identity) return nil;

    SecCertificateRef secCert = NULL;
    SecIdentityCopyCertificate(identity, &secCert);
    if (!secCert) return nil;

    CFDataRef cfCertData = SecCertificateCopyData(secCert);
    CFRelease(secCert);
    NSData *certDER = cfCertData ? [NSData dataWithBytes:CFDataGetBytePtr(cfCertData)
                                                  length:(NSUInteger)CFDataGetLength(cfCertData)] : nil;
    if (cfCertData) CFRelease(cfCertData);

    SecKeyRef privKey = NULL;
    SecIdentityCopyPrivateKey(identity, &privKey);
    NSData *privDER = nil;
    if (privKey) {
        CFErrorRef cfErr = NULL;
        CFDataRef cfPrivData = SecKeyCopyExternalRepresentation(privKey, &cfErr);
        if (cfErr) CFRelease(cfErr);
        CFRelease(privKey);
        privDER = cfPrivData ? [NSData dataWithBytes:CFDataGetBytePtr(cfPrivData)
                                              length:(NSUInteger)CFDataGetLength(cfPrivData)] : nil;
        if (cfPrivData) CFRelease(cfPrivData);
    }

    return [MKCertificate certificateWithCertificate:certDER privateKey:privDER];
}

+ (NSArray *) certificatesWithPKCS12:(NSData *)pkcs12 password:(NSString *)password {
    if (!pkcs12) return @[];
    NSArray *items = nil;
    NSDictionary *opts = password ? @{(__bridge id)kSecImportExportPassphrase: password} : @{};
    OSStatus err = SecPKCS12Import((__bridge CFDataRef)pkcs12,
                                   (__bridge CFDictionaryRef)opts,
                                   (CFArrayRef *)&items);
    if (err != errSecSuccess) return @[];

    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *item in items) {
        SecIdentityRef identity = (__bridge SecIdentityRef)[item objectForKey:(__bridge id)kSecImportItemIdentity];
        SecCertificateRef secCert = NULL;
        NSData *certDER = nil;
        NSData *privDER = nil;

        if (identity) {
            SecIdentityCopyCertificate(identity, &secCert);
            SecKeyRef privKey = NULL;
            SecIdentityCopyPrivateKey(identity, &privKey);
            if (privKey) {
                CFErrorRef cfErr = NULL;
                CFDataRef cfPriv = SecKeyCopyExternalRepresentation(privKey, &cfErr);
                if (cfErr) CFRelease(cfErr);
                CFRelease(privKey);
                privDER = cfPriv ? [NSData dataWithBytes:CFDataGetBytePtr(cfPriv)
                                                  length:(NSUInteger)CFDataGetLength(cfPriv)] : nil;
                if (cfPriv) CFRelease(cfPriv);
            }
        } else {
            NSArray *chain = [item objectForKey:(__bridge id)kSecImportItemCertChain];
            if (chain.count > 0)
                secCert = (__bridge SecCertificateRef)[chain objectAtIndex:0];
        }

        if (secCert) {
            CFDataRef cfCert = SecCertificateCopyData(secCert);
            if (identity) CFRelease(secCert);
            certDER = cfCert ? [NSData dataWithBytes:CFDataGetBytePtr(cfCert)
                                              length:(NSUInteger)CFDataGetLength(cfCert)] : nil;
            if (cfCert) CFRelease(cfCert);
        }

        if (certDER) {
            MKCertificate *c = [MKCertificate certificateWithCertificate:certDER privateKey:privDER];
            [result addObject:c];
        }
    }
    return result;
}

+ (NSData *) exportCertificateChainAsPKCS12:(NSArray *)chain withPassword:(NSString *)password {
    // Exporting PKCS12 requires SecItemExport (macOS) or Keychain round-trip.
    // Not implemented for SPM/iOS build — certificate export is not required
    // for basic Mumble connectivity.
    NSLog(@"MKCertificate: PKCS12 export not implemented in Security-framework build.");
    return nil;
}

- (NSData *) exportPKCS12WithPassword:(NSString *)password {
    return [MKCertificate exportCertificateChainAsPKCS12:@[self] withPassword:password];
}

- (BOOL) hasCertificate { return _derCert != nil; }
- (BOOL) hasPrivateKey  { return _derPrivKey != nil; }

- (void) extractCertInfo {
    if (!_derCert) return;

    SecCertificateRef secCert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)_derCert);
    if (!secCert) return;

    // Subject / issuer via platform APIs
    CFStringRef cn = NULL;
    SecCertificateCopyCommonName(secCert, &cn);
    if (cn) {
        _subjectDict = [@{MKCertificateItemCommonName: (__bridge NSString *)cn} retain];
        CFRelease(cn);
    }

    // Validity dates and SANs via SecCertificateCopyValues (macOS 10.6+)
#if TARGET_OS_OSX
    CFArrayRef oids = NULL;
    CFDictionaryRef vals = SecCertificateCopyValues(secCert, oids, NULL);
    if (vals) {
        // notBefore
        NSDictionary *nbDict = [(__bridge NSDictionary *)vals
            objectForKey:(__bridge id)kSecOIDX509V1ValidityNotBefore];
        id nbVal = nbDict ? [nbDict objectForKey:(__bridge id)kSecPropertyKeyValue] : nil;
        if (nbVal) _notBeforeDate = [[NSDate dateWithTimeIntervalSinceReferenceDate:[nbVal doubleValue]] retain];

        // notAfter
        NSDictionary *naDict = [(__bridge NSDictionary *)vals
            objectForKey:(__bridge id)kSecOIDX509V1ValidityNotAfter];
        id naVal = naDict ? [naDict objectForKey:(__bridge id)kSecPropertyKeyValue] : nil;
        if (naVal) _notAfterDate = [[NSDate dateWithTimeIntervalSinceReferenceDate:[naVal doubleValue]] retain];

        CFRelease(vals);
    }
#endif

    CFRelease(secCert);
}

- (BOOL) isSignedBy:(MKCertificate *)parentCert {
    // Basic check: compare issuer fingerprint.
    // A full signature verification would require lower-level ASN.1 work.
    if (!_derCert || !parentCert || !parentCert->_derCert) return NO;
    SecCertificateRef us     = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)_derCert);
    SecCertificateRef parent = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)parentCert->_derCert);
    if (!us || !parent) {
        if (us) CFRelease(us);
        if (parent) CFRelease(parent);
        return NO;
    }
    // Use SecTrust to verify
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    CFArrayRef certs = CFArrayCreate(NULL, (const void **)&us, 1, &kCFTypeArrayCallBacks);
    SecTrustRef trust = NULL;
    SecTrustCreateWithCertificates(certs, policy, &trust);
    SecTrustSetAnchorCertificates(trust, (__bridge CFArrayRef)@[(__bridge id)parent]);
    CFRelease(certs);
    CFRelease(policy);

    SecTrustResultType result;
    SecTrustEvaluate(trust, &result);
    BOOL verified = (result == kSecTrustResultUnspecified || result == kSecTrustResultProceed);

    CFRelease(trust);
    CFRelease(us);
    CFRelease(parent);
    return verified;
}

- (BOOL) isValidOnDate:(NSDate *)date {
    if (!_notBeforeDate || !_notAfterDate) return YES;
    return [date compare:_notBeforeDate] == NSOrderedDescending &&
           [date compare:_notAfterDate]  == NSOrderedAscending;
}

- (NSData *) digest { return [self digestOfKind:@"sha1"]; }

- (NSData *) digestOfKind:(NSString *)digestKind {
    if (!_derCert || _derCert.length > UINT32_MAX) return nil;
    digestKind = [digestKind lowercaseString];
    if ([digestKind isEqualToString:@"sha1"]) {
        unsigned char buf[CC_SHA1_DIGEST_LENGTH];
        CC_SHA1(_derCert.bytes, (CC_LONG)_derCert.length, buf);
        return [NSData dataWithBytes:buf length:CC_SHA1_DIGEST_LENGTH];
    } else if ([digestKind isEqualToString:@"sha256"]) {
        unsigned char buf[CC_SHA256_DIGEST_LENGTH];
        CC_SHA256(_derCert.bytes, (CC_LONG)_derCert.length, buf);
        return [NSData dataWithBytes:buf length:CC_SHA256_DIGEST_LENGTH];
    }
    return nil;
}

- (NSString *) hexDigest { return [self hexDigestOfKind:@"sha1"]; }

- (NSString *) hexDigestOfKind:(NSString *)digestKind {
    if (!_derCert) return nil;
    NSData *digest = [self digestOfKind:digestKind];
    NSUInteger len = digest.length;
    if (len % 2 != 0) return nil;
    NSMutableData *hex = [NSMutableData dataWithLength:2*len];
    unsigned char *hexstr = [hex mutableBytes];
    const unsigned char *buf = digest.bytes;
    const char *tbl = "0123456789abcdef";
    for (NSUInteger i = 0; i < len; i++) {
        hexstr[2*i+0] = tbl[(buf[i] >> 4) & 0x0f];
        hexstr[2*i+1] = tbl[buf[i] & 0x0f];
    }
    return [[[NSString alloc] initWithData:hex encoding:NSASCIIStringEncoding] autorelease];
}

- (NSString *) subjectName {
    NSString *cn = [_subjectDict objectForKey:MKCertificateItemCommonName];
    if (cn) return cn;
    if (_dnsEntries.count > 0) return [_dnsEntries objectAtIndex:0];
    if (_emailAddresses.count > 0) return [_emailAddresses objectAtIndex:0];
    return nil;
}

- (NSString *) commonName   { return [_subjectDict objectForKey:MKCertificateItemCommonName]; }
- (NSString *) emailAddress { return _emailAddresses.count > 0 ? [_emailAddresses objectAtIndex:0] : nil; }
- (NSString *) issuerName   { return [self issuerItem:MKCertificateItemCommonName]; }
- (NSDate *)   notAfter     { return _notAfterDate; }
- (NSDate *)   notBefore    { return _notBeforeDate; }
- (NSString *) issuerItem:(NSString *)item  { return [_issuerDict objectForKey:item]; }
- (NSString *) subjectItem:(NSString *)item { return [_subjectDict objectForKey:item]; }

@end

// ---------------------------------------------------------------------------
// MKRSAKeyPair — using SecKey instead of OpenSSL RSA
// ---------------------------------------------------------------------------

@interface MKRSAKeyPair () {
    NSData *_publicKey;
    NSData *_privateKey;
}
- (void) genKeysWithSize:(NSUInteger)bits;
@end

@implementation MKRSAKeyPair

+ (MKRSAKeyPair *) generateKeyPairOfSize:(NSUInteger)bits withDelegate:(id<MKRSAKeyPairDelegate>)delegate {
    MKRSAKeyPair *kp = [[MKRSAKeyPair alloc] init];
    if (delegate == nil) {
        [kp genKeysWithSize:bits];
    } else {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [kp genKeysWithSize:bits];
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate rsaKeyPairDidFinishGenerating:kp];
            });
        });
    }
    return [kp autorelease];
}

- (void) dealloc {
    [_privateKey release];
    [_publicKey release];
    [super dealloc];
}

- (void) genKeysWithSize:(NSUInteger)bits {
    NSDictionary *params = @{
        (__bridge id)kSecAttrKeyType:       (__bridge id)kSecAttrKeyTypeRSA,
        (__bridge id)kSecAttrKeySizeInBits: @(bits),
    };
    CFErrorRef cfErr = NULL;
    SecKeyRef privKey = SecKeyCreateRandomKey((__bridge CFDictionaryRef)params, &cfErr);
    if (!privKey) {
        if (cfErr) CFRelease(cfErr);
        return;
    }
    SecKeyRef pubKey = SecKeyCopyPublicKey(privKey);

    _privateKey = (__bridge_transfer NSData *)SecKeyCopyExternalRepresentation(privKey, &cfErr);
    if (cfErr) { CFRelease(cfErr); cfErr = NULL; }
    _publicKey  = (__bridge_transfer NSData *)SecKeyCopyExternalRepresentation(pubKey, &cfErr);
    if (cfErr) CFRelease(cfErr);

    CFRelease(pubKey);
    CFRelease(privKey);
}

- (NSData *) publicKey  { return _publicKey; }
- (NSData *) privateKey { return _privateKey; }

@end
