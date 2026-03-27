// Copyright 2005-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <Foundation/Foundation.h>

#import <MumbleKit/MKConnection.h>
#import "MKAudioOutputUser.h"

struct MKAudioOutputSpeechPrivate;

@interface MKAudioOutputSpeech : MKAudioOutputUser

- (id) initWithSession:(NSUInteger)session sampleRate:(NSUInteger)freq messageType:(MKUDPMessageType)type;
- (void) dealloc;

- (NSUInteger) userSession;
- (MKUDPMessageType) messageType;

- (void) addFrame:(NSData *)data forSequence:(NSUInteger)seq;

@end
