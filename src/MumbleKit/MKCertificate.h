/* Copyright (C) 2009-2010 Mikkel Krautz <mikkel@krautz.dk>
   Copyright (c) 2005-2010 Thorvald Natvig, <thorvald@natvig.com>

   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

   - Redistributions of source code must retain the above copyright notice,
     this list of conditions and the following disclaimer.
   - Redistributions in binary form must reproduce the above copyright notice,
     this list of conditions and the following disclaimer in the documentation
     and/or other materials provided with the distribution.
   - Neither the name of the Mumble Developers nor the names of its
     contributors may be used to endorse or promote products derived from this
     software without specific prior written permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR
   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

@class MKRSAKeyPair;


///-----------------------------------
/// @name MKCertificate accessor items
///-----------------------------------

/**
 * @constant The Common Name item. (CN)
 */ 
extern NSString *MKCertificateItemCommonName;
/**
 * @constant The Country item. (C)
 */
extern NSString *MKCertificateItemCountry;

/**
 * @constant The Organization item. (O)
 */
extern NSString *MKCertificateItemOrganization;

/**
 * @constant The serialNumber item. (serialNumber)
 */
extern NSString *MKCertificateItemSerialNumber;


/**
 * MKCertificate is a helper class for creating, reading and exporting X.509 certificates.
 */
@interface MKCertificate : NSObject

///------------------------------------------
/// @name Creating and accessing certificates
///------------------------------------------

/**
 * Returns a new MKCertificate object from the given certificate and private key.
 *
 * @param cert     A DER-encoded X.509 certificate
 * @param privkey  The private key corresponding to the certificate passed in via cert.
 *
 * @returns A MKCertificate object with the given certificate data and optionally the
 *          given private key. Passing in a private key is mostly used in situations
 *          where one wants to export the certificate in another format (for example PKCS12).
 */
+ (MKCertificate *) certificateWithCertificate:(NSData *)cert privateKey:(NSData *)privkey;

/**
 * Generate a self-signed MKCertificate object using the given name and email address.
 * This generates a public and private keypair, and uses that key pair to create a self-
 * signed X.509 certificate that is compatible with Mumble.
 *
 * @param name  The name to be used when creating the certificate. This becomes the
 *              Subject Name of the X.509 certificate.
 * @param email The email address to embed in the certificate. This value may be nil if
 *              no email address should be included in the generated X.509 certificate.
 *
 * @returns A MKCertificate that backs a self-signed X.509 certificate backed by a random
 *          public and private keypair.
 */
+ (MKCertificate *) selfSignedCertificateWithName:(NSString *)name email:(NSString *)email;

/**
 * Generate a self-signed MKCertificate object using the given name and email address.
 * This method optionally takes a MKRSAKeyPair which it will use for the certificate it
 * generates.
 *
 * @param name     The name to be used when creating the certificate. This becomes the
 *                 Subject Name of the X.509 certificate.
 *
 * @param email    The email address to embed in the certificate. This value may be nil if
 *                 no email address should be included in the generated X.509 certificate.
 *
 * @param keyPair  An optional MKRSAKeyPair to use instead of generating a new key pair.
 *                 If nil is passed for this parameter, the method will generate its own
 *                 keypair (by default: 2048 bits).
 *
 * @returns A MKCertificate that backs a self-signed X.509 certificate backed by a random
 *          public and private keypair.
 */
+ (MKCertificate *) selfSignedCertificateWithName:(NSString *)name email:(NSString *)email rsaKeyPair:(MKRSAKeyPair *)keyPair;

/**
 * Import a certificate from a PKCS12 file with the given password.
 *
 * @param pkcs12    A PKCS12-encoded certificate with a public and private keypair.
 * @param password  The password to decode the given PKCS12-encoded file.
 *                  May be nil if no password, or a blank password should be used for decoding
 *                  the given PKCS12 data.
 *
 * @returns A MKCertificate backed by the certificate and public and private keypair
 *          from the given PKCS12 data.
 */
+ (MKCertificate *) certificateWithPKCS12:(NSData *)pkcs12 password:(NSString *)password;

///---------------------------------
/// @name Certificate content status
///---------------------------------

/**
 * Determine whether the certificate has a certificate (and public key)
 *
 * @return Returns YES if the MKCertificate object has a certificate and public key.
 *         Otherwise, returns NO.
 */
- (BOOL) hasCertificate;

/**
 * Determine whether the MKCertficiate object has private key data.
 *
 * @returns Returns YES if the MKCertificate object has a private key.
 *          Otherwise, returns NO.
 */
- (BOOL) hasPrivateKey;

///--------------------------------
/// @name Exporting a MKCertificate
///--------------------------------

/**
 * Export a MKCertificate object to a PKCS12 data blob using the given password.
 *
 * @param password  The password needed to decode the generated PKCS12-blob.
 *
 * @returns Returns a NSData object that holds the PKCS12-encoded version of
 *          the receiver MKCertificate's certificate and public and private keypair.
 */
- (NSData *) exportPKCS12WithPassword:(NSString *)password;

///--------------------------
/// @name Certificate Digests
///--------------------------

/**
 * Returns a SHA1 digest of raw DER-data backing the certificate and the public key
 * of the receiving MKCertificate object.
 *
 * @returns An NSData object that holds the calculated SHA1 digest.
 */
- (NSData *) digest;

/**
 * Returns a hex-encoded SHA1 digest of the raw DER-data backing the certifiate and the
 * public key of the receiving MKCertificate object.
 *
 * @returns A NSString with the (lowercase) hex-encoded SHA1 digest.
 */
- (NSString *) hexDigest;

///---------------------
/// @name Validity Dates
///---------------------

/**
 * Returns the Not Before date of the X.509 certificate.
 * This determines the date from which the certificate is deemed valid.
 *
 * @returns An NSDate object with the Not Before date.
 */
- (NSDate *) notBefore;

/**
 * Returns the Not After date of the X.509 certificate.
 * This date expresses the moment at which the certificate stops being deemed valid.
 * Note that a X.509 certificates can also be revoked, so the Not After date is not
 * an authoritative method of determining certificate validity.
 *
 * @returns An NSDate object with the Not After date.
 */
- (NSDate *) notAfter;

///------------------------------------------
/// @name Certificate Subject and Issuer data
///------------------------------------------

/**
 * Retruns the CN (Common Name) value of subjecdt of the X.509 certificate.
 *
 * @returns An NSString with the Common Name.
 */
- (NSString *) commonName;

/**
 * Returns the first email address listed in the X.509 certificate.
 * (This email is looked after in Subject Alt. Names.)
 *
 * @returns An NSString with the email address.
 */
- (NSString *) emailAddress;

/**
 * Returns the name of the body that issued the X.509 certificate.
 *
 * @returns An NSString with the issuer name.
 */
- (NSString *) issuerName;

/**
 * The issuerItem: method is used to directly access the issuer items of the X.509
 * certificate.
 *
 * @param item  An X.509 subject item key (CN, O, C, etc.)
 *              (See the 'MKCertificate accessor items' section for a list
 *               of pre-defined symbolic values for the item keys)
 *
 * @returns The value of the looked-up issuer item. Returns nil if the issuer
 *          item was not found.
 */
- (NSString *) issuerItem:(NSString *)item;

/**
 * The subjectItem: method is used to directly access the subject items of the X.509
 * certificate.
 *
 * @param item  An X.509 issuer item key (CN, O, C, etc.)
 *              (See the 'MKCertificate accessor items' section for a list
 *               of pre-defined symbolic values for the item keys)
 *
 * @returns The value of the looked-up subject item. Returns nil if the subject item
 *          was not found.
 */
- (NSString *) subjectItem:(NSString *)item;

@end

/**
 * MKRSAKeyPair is a protocol for getting notified when a MKRSAKeyPair is done generating its
 * public and private key.
 */
@protocol MKRSAKeyPairDelegate

/**
 * Called when an MKRSAKeyPair has finished generating its RSA key pair.
 *
 * @param  keyPair  The MKRSAKeyPair that finished generating its keys.
 */
- (void) rsaKeyPairDidFinishGenerating:(MKRSAKeyPair *)keyPair;
@end

/**
 * MKRSAKeyPair is a helper class for creating, reading and exporting RSA keypairs.
 */
@interface MKRSAKeyPair : NSObject

/**
 * Generate a new RSA keypair with bits key size. If a delegate is provided, the key generation will be
 * performed asynchronously on a distinct dispatch queue. If no delegate is provided, the key generation
 * is performed in the context in which the method is called.
 *
 * @param  bits       The size of the generated keys specified in bits.
 * @param  delegate   The delegate the MKRSAKeyPair should call its rsaKeyPairDidFinishGenerating: method on.
 *                    If no delegate is specified, this method will block the thread it is run in while generating.
 *                    If a delegate is specified, it will perform its key generation in a separate dispatch queue,
 *                    and call the delegate on the main thread.
 *
 * @returns A MKRSAKeyPair with a private and a public RSA key of bits length.
 */
+ (MKRSAKeyPair *) generateKeyPairOfSize:(NSUInteger)bits withDelegate:(id<MKRSAKeyPairDelegate>)delegate;
- (NSData *) publicKey;
- (NSData *) privateKey;
@end