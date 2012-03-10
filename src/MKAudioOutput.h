// Copyright 2005-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKAudio.h>
#import <MumbleKit/MKUser.h>
#import <MumbleKit/MKConnection.h>
#import "MKAudioOutputUser.h"

@class MKUser;

@interface MKAudioOutput : NSObject

- (id) initWithSettings:(MKAudioSettings *)settings;
- (void) dealloc;

- (BOOL) setupDevice;
- (BOOL) teardownDevice;

- (void) removeBuffer:(MKAudioOutputUser *)u;
- (BOOL) mixFrames: (void *)frames amount:(unsigned int)nframes;
- (void) addFrameToBufferWithSession:(NSUInteger)session data:(NSData *)data sequence:(NSUInteger)seq type:(MKUDPMessageType)msgType;

@end
