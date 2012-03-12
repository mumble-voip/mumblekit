// Copyright 2005-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MKAudioOutputUser.h"
#import "MKAudioOutputUserPrivate.h"

@implementation MKAudioOutputUser

- (id) init {
    if ((self = [super init])) {
        _bufferSize = 0;
        _buffer = NULL;
        _volume = NULL;
        _pos[0] = 0.0f;
        _pos[1] = 0.0f;
        _pos[2] = 0.0f;
    }
    return self;
}

- (void) dealloc {
    if (_buffer)
        free(_buffer);
    if (_volume)
        free(_volume);

    [super dealloc];
}

- (MKUser *) user {
    return nil;
}

- (float *) buffer {
    return _buffer;
}

- (NSUInteger) bufferLength {
    return _bufferSize;
}

- (void) resizeBuffer:(NSUInteger)newSize {
    if (newSize > _bufferSize) {
        float *n = malloc(sizeof(float) * newSize);
        if (_buffer != NULL) {
            memcpy(n, _buffer, sizeof(float) * _bufferSize);
            free(_buffer);
        }
        _buffer = n;
        _bufferSize = newSize;
    }
}

- (BOOL) needSamples:(NSUInteger)nsamples {
    return NO;
}

@end
