// Copyright 2005-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

typedef union _float32u {
    uint8_t b[4];
    float f;
} float32u;

@interface MKPacketDataStream : NSObject

- (id) initWithData:(NSData *)data;
- (id) initWithBuffer:(unsigned char *)buffer length:(NSUInteger)len;
- (void) dealloc;

- (NSUInteger) size;
- (NSUInteger) capactiy;
- (NSUInteger) left;
- (BOOL) valid;

- (void) rewind;
- (void) truncate;

- (unsigned char *) dataPtr;
- (char *) charPtr;
- (NSData *) data;
- (NSMutableData *) mutableData;

- (void) appendValue:(uint64_t)value;
- (void) appendBytes:(unsigned char *)buffer length:(NSUInteger)len;

- (void) skip:(NSUInteger)amount;
- (uint64_t) next;
- (uint8_t) next8;

- (void) addVarint:(uint64_t)value;

- (uint64_t) getVarint;
- (int) getInt;
- (unsigned int) getUnsignedInt;
- (short) getShort;
- (unsigned short) getUnsignedShort;
- (char) getChar;
- (unsigned char) getUnsignedChar;
- (float) getFloat;
- (double) getDouble;

- (NSData *) copyDataBlock:(NSUInteger)len;

@end
