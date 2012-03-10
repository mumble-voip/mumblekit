// Copyright 2005-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MKAudioOutputUser.h"
#import "MKAudioOutputUserPrivate.h"

@implementation MKAudioOutputUser

- (id) init {
    if ((self = [super init])) {
        bufferSize = 0;
        buffer = NULL;
        volume = NULL;

        pos[0] = pos[1] = pos[2] = 0.0f;
    }
    return self;
}

- (void) dealloc {
    if (buffer)
        free(buffer);
    if (volume)
        free(volume);

    [super dealloc];
}

- (MKUser *) user {
    return nil;
}

- (float *) buffer {
    return buffer;
}

- (NSUInteger) bufferLength {
    return bufferSize;
}

- (void) resizeBuffer:(NSUInteger)newSize {
    if (newSize > bufferSize) {
        float *n = malloc(sizeof(float)*newSize);
        if (buffer != NULL) {
            memcpy(n, buffer, sizeof(float)*bufferSize);
            free(buffer);
        }
        buffer = n;
        bufferSize = newSize;
    }
}

- (BOOL) needSamples:(NSUInteger)nsamples {
    return NO;
}

@end
