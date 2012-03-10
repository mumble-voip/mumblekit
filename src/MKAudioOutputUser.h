// Copyright 2005-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKUser.h>

@interface MKAudioOutputUser : NSObject

- (id) init;
- (void) dealloc;

- (MKUser *) user;
- (float *) buffer;
- (NSUInteger) bufferLength;

- (BOOL) needSamples:(NSUInteger)nsamples;
- (void) resizeBuffer:(NSUInteger)newSize;

@end
