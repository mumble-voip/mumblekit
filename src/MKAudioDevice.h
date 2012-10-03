// Copyright 2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKAudio.h>

typedef BOOL (^MKAudioDeviceOutputFunc)(short *frames, unsigned int nsamp);
typedef BOOL (^MKAudioDeviceInputFunc)(short *frames, unsigned int nsamp);

@interface MKAudioDevice : NSObject
- (id) initWithSettings:(MKAudioSettings *)settings;
- (BOOL) setupDevice;
- (BOOL) teardownDevice;

- (void) setupInput:(MKAudioDeviceInputFunc)inf;
- (void) setupOutput:(MKAudioDeviceOutputFunc)outf;

- (int) inputSampleRate;
- (int) outputSampleRate;
- (int) numberOfInputChannels;
- (int) numberOfOutputChannels;
@end
