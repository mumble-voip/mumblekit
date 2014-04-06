// Copyright 2005-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/*
 * This code implements OCB-AES128.
 * In the US, OCB is covered by patents. The inventor has given a license
 * to all programs distributed under the GPL.
 * Mumble is BSD (revised) licensed, meaning you can use the code in a
 * closed-source program. If you do, you'll have to either replace
 * OCB with something else or get yourself a license.
 */

#import "MKCryptState.h"
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

- (NSData *) encryptData:(NSData *)data {
	if ([data length] > UINT_MAX) {
		return nil;
	}

	NSMutableData *crypted = [[NSMutableData alloc] initWithLength:[data length]+4];
	_priv->cs.encrypt((const unsigned char *)[data bytes], (unsigned char *)[crypted mutableBytes], (unsigned int)[data length]);
	return [crypted autorelease];
}

- (NSData *) decryptData:(NSData *)data {
	if (!([data length] > 4))
		return nil;

	if ([data length] > UINT_MAX) {
		return nil;
	}

	NSMutableData *plain = [[NSMutableData alloc] initWithLength:[data length]-4];
	if (_priv->cs.decrypt((const unsigned char *)[data bytes], (unsigned char *)[plain mutableBytes], (unsigned int)[data length])) {
		return [plain autorelease];
	} else {
		[plain release];
		return nil;
	}
}

@end
