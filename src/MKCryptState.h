// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

struct MKCryptStatePrivate;

@interface MKCryptState : NSObject

- (id) init;
- (void) dealloc;

- (BOOL) valid;
- (void) generateKey;
- (void) setKey:(NSData *)key eiv:(NSData *)enc div:(NSData *)dec;
- (void) setDecryptIV:(NSData *)dec;
- (NSData *) encryptData:(NSData *)data;
- (NSData *) decryptData:(NSData *)data;

@end
