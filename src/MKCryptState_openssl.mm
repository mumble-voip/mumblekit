/* Copyright (C) 2005-2009, Thorvald Natvig <thorvald@natvig.com>
   Copyright (C) 2009-2010 Mikkel Krautz <mikkel@krautz.dk>

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

/*
 * This code implements OCB-AES128.
 * In the US, OCB is covered by patents. The inventor has given a license
 * to all programs distributed under the GPL.
 * Mumble is BSD (revised) licensed, meaning you can use the code in a
 * closed-source program. If you do, you'll have to either replace
 * OCB with something else or get yourself a license.
 */

#import <MumbleKit/MKCryptState.h>
#include "CryptState.h"

using namespace MumbleClient;

struct MKCryptStatePrivate {
	CryptState cs;
};

@interface MKCryptState () {
    struct MKCryptStatePrivate *_priv;
}
@end

@implementation MKCryptState

- (id) init {
	self = [super init];
	if (self == nil)
		return nil;

	_priv = (struct MKCryptStatePrivate *) malloc(sizeof(struct MKCryptStatePrivate));

	return self;
}

- (void) dealloc {
	free(_priv);

	[super dealloc];
}

- (BOOL) valid {
	return (BOOL)_priv->cs.isValid();
}

- (void) generateKey {
	_priv->cs.genKey();
}

- (void) setKey:(NSData *)key eiv:(NSData *)enc div:(NSData *)dec {
	NSAssert([key length] == AES_BLOCK_SIZE, @"key length not AES_BLOCK_SIZE");
	NSAssert([enc length] == AES_BLOCK_SIZE, @"enc length not AES_BLOCK_SIZE");
	NSAssert([dec length] == AES_BLOCK_SIZE, @"dec length not AES_BLOCK_SIZE");
	_priv->cs.setKey((const unsigned char *)[key bytes], (const unsigned char *)[enc bytes], (const unsigned char *)[dec bytes]);
}

- (void) setDecryptIV:(NSData *)dec {
	NSAssert([dec length] == AES_BLOCK_SIZE, @"dec length not AES_BLOCK_SIZE");
	_priv->cs.setDecryptIV((const unsigned char *)[dec bytes]);
	
}

- (NSData *) getEncryptIV {
	return [[NSData alloc] initWithBytes:_priv->cs.getEncryptIV() length:AES_BLOCK_SIZE];
}

- (NSData *) encryptData:(NSData *)data {
	NSMutableData *crypted = [[NSMutableData alloc] initWithLength:[data length]+4];
	_priv->cs.encrypt((const unsigned char *)[data bytes], (unsigned char *)[crypted mutableBytes], [data length]);
	return crypted;
}

- (NSData *) decryptData:(NSData *)data {
	if (!([data length] > 4))
		return nil;

	NSMutableData *plain = [[NSMutableData alloc] initWithLength:[data length]-4];
	if (_priv->cs.decrypt((const unsigned char *)[data bytes], (unsigned char *)[plain mutableBytes], [data length])) {
		return plain;
	} else {
		[plain release];
		return nil;
	}
}

@end
