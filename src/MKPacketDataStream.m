// Copyright 2005-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MKPacketDataStream.h"

@interface MKPacketDataStream () {
    NSMutableData   *mutableData;
    NSData          *immutableData;
    unsigned char   *data;
    NSUInteger      maxSize;
    NSUInteger      offset;
    NSUInteger      overshoot;
    BOOL            ok;
}
@end

@implementation MKPacketDataStream

- (id) initWithData:(NSData *)ourContainer {
    if ((self = [super init])) {
        immutableData = ourContainer;
        [immutableData retain];
        data = (unsigned char *)[immutableData bytes];
        offset = 0;
        overshoot = 0;
        maxSize = [immutableData length];
        ok = YES;
    }
    return self;
}

- (id) initWithBuffer:(unsigned char *)buffer length:(NSUInteger)len {
    if ((self = [super init])) {
        data = buffer;
        offset = 0;
        overshoot = 0;
        maxSize = len;
        ok = YES;
    }
    return self;
}

- (void) dealloc {
    [mutableData release];
    [immutableData release];
    [super dealloc];
}

- (NSUInteger) size {
    return offset;
}

- (NSUInteger) capactiy {
    return maxSize;
}

- (NSUInteger) left {
    return maxSize - offset;
}

- (BOOL) valid {
    return ok;
}

- (void) appendValue:(uint64_t)value {
    assert(value <= 0xff);

    if (offset < maxSize)
        data[offset++] = (unsigned char)value;
    else {
        ok = NO;
        overshoot++;
    }
}

- (void) appendBytes:(unsigned char *)buffer length:(NSUInteger)len {
    if ([self left] >= len) {
        memcpy(&data[offset], buffer, len);
        offset += len;
    } else {
        NSUInteger l = [self left];
        memset(&data[offset], 0, l);
        overshoot += len - l;
        ok = NO;
    }
}

- (void) skip:(NSUInteger)amount {
    if ([self left] >= amount) {
        offset += amount;
    } else
        ok = NO;
}

- (uint64_t) next {
    if (offset < maxSize) {
        return data[offset++];
    } else {
        ok = NO;
        return 0;
    }
}

- (uint8_t) next8 {
    if (offset < maxSize) {
        return data[offset++];
    } else {
        ok = NO;
        return 0;
    }
}

- (void) rewind {
    offset = 0;
}

- (void) truncate {
    maxSize = offset;
}

- (unsigned char *) dataPtr {
    return (unsigned char *)&data[offset];
}

- (char *) charPtr {
    return (char *)&data[offset];
}

- (NSData *) data {
    return (NSData *)mutableData;
}

- (NSMutableData *) mutableData {
    return mutableData;
}

- (void) addVarint:(uint64_t)value {
    uint64_t i = value;

    if ((i & 0x8000000000000000LL) && (~i < 0x100000000LL)) {
        // Signed number.
        i = ~i;
        if (i <= 0x3) {
            // Shortcase for -1 to -4
            [self appendValue:(0xFC | i)];
        } else {
            [self appendValue:(0xF8)];
        }
    }
    if (i < 0x80) {
        // Need top bit clear
        [self appendValue:i];
    } else if (i < 0x4000) {
        // Need top two bits clear
        [self appendValue:((i >> 8) | 0x80)];
        [self appendValue:(i & 0xFF)];
    } else if (i < 0x200000) {
        // Need top three bits clear
        [self appendValue:((i >> 16) | 0xC0)];
        [self appendValue:((i >> 8) & 0xFF)];
        [self appendValue:(i & 0xFF)];
    } else if (i < 0x10000000) {
        // Need top four bits clear
        [self appendValue:((i >> 24) | 0xE0)];
        [self appendValue:((i >> 16) & 0xFF)];
        [self appendValue:((i >> 8) & 0xFF)];
        [self appendValue:(i & 0xFF)];
    } else if (i < 0x100000000LL) {
        // It's a full 32-bit integer.
        [self appendValue:(0xF0)];
        [self appendValue:((i >> 24) & 0xFF)];
        [self appendValue:((i >> 16) & 0xFF)];
        [self appendValue:((i >> 8) & 0xFF)];
        [self appendValue:(i & 0xFF)];
    } else {
        // It's a 64-bit value.
        [self appendValue:(0xF4)];
        [self appendValue:((i >> 56) & 0xFF)];
        [self appendValue:((i >> 48) & 0xFF)];
        [self appendValue:((i >> 40) & 0xFF)];
        [self appendValue:((i >> 32) & 0xFF)];
        [self appendValue:((i >> 24) & 0xFF)];
        [self appendValue:((i >> 16) & 0xFF)];
        [self appendValue:((i >> 8) & 0xFF)];
        [self appendValue:(i & 0xFF)];
    }
}

- (uint64_t) getVarint {
    uint64_t i = 0;
    uint64_t v = [self next];

    if ((v & 0x80) == 0x00) {
        i = (v & 0x7F);
    } else if ((v & 0xC0) == 0x80) {
        i = (v & 0x3F) << 8 | [self next];
    } else if ((v & 0xF0) == 0xF0) {
        switch (v & 0xFC) {
            case 0xF0:
                i=[self next] << 24 | [self next] << 16 | [self next] << 8 | [self next];
                break;
            case 0xF4:
                i = [self next] << 56 | [self next] << 48 | [self next] << 40 | [self next] << 32 | [self next] << 24 | [self next] << 16 | [self next] << 8 | [self next];
                break;
            case 0xF8:
                i = [self getVarint];
                i = ~i;
                break;
            case 0xFC:
                i = v & 0x03;
                i = ~i;
                break;
            default:
                ok = NO;
                i = 0;
                break;
        }
    } else if ((v & 0xF0) == 0xE0) {
        i = (v & 0x0F) << 24 | [self next] << 16 | [self next] << 8 | [self next];
    } else if ((v & 0xE0) == 0xC0) {
        i = (v & 0x1F) << 16 | [self next] << 8 | [self next];
    }
    return i;
}

- (unsigned int) getUnsignedInt {
    return (unsigned int) [self getVarint];
}

- (int) getInt {
    return (int) [self getVarint];
}

- (short) getShort {
    return (short) [self getVarint];
}

- (unsigned short) getUnsignedShort {
    return (unsigned short) [self getVarint];
}

- (char) getChar {
    return (char) [self getVarint];
}

- (unsigned char) getUnsignedChar {
    return (unsigned char) [self getVarint];
}

- (float) getFloat {
    float32u u;

    if ([self left] < 4) {
        ok = NO;
        return 0.0f;
    }

    u.b[0] = [self next8];
    u.b[1] = [self next8];
    u.b[2] = [self next8];
    u.b[3] = [self next8];

    return u.f;
}

- (double) getDouble {
    NSLog(@"PacketDataStream: getDouble not implemented yet.");
    return 0.0f;
}

- (NSData *) copyDataBlock:(NSUInteger)len {
    if ([self left] >= len) {
        NSData *db = [[NSData alloc] initWithBytes:[self dataPtr] length:len];
        offset += len;
        return db;
    } else {
        NSLog(@"PacketDataStream: Unable to copyDataBlock. Requsted=%lu, avail=%lu", (unsigned long)len, (unsigned long)[self left]);
        ok = NO;
        return nil;
    }
}

@end
