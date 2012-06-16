// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKAudio.h>
#import <MumbleKit/MKConnection.h>
#import <AudioUnit/AudioUnit.h>
#import <AudioUnit/AUComponent.h>
#import <AudioToolbox/AudioToolbox.h>

@interface MKAudioInput : NSObject

- (id) initWithSettings:(MKAudioSettings *)settings;
- (void) dealloc;

- (BOOL) setupDevice;
- (BOOL) teardownDevice;

- (void) initializeMixer;

- (void) resetPreprocessor;
- (void) addMicrophoneDataWithBuffer:(short *)input amount:(NSUInteger)nsamp;
- (void) flushCheck:(NSData *)outputBuffer terminator:(BOOL)terminator;

- (void) setForceTransmit:(BOOL)flag;
- (BOOL) forceTransmit;

- (signed long) preprocessorAvgRuntime;
- (float) peakCleanMic;
- (float) speechProbability;

- (void) setSelfMuted:(BOOL)selfMuted;
- (void) setSuppressed:(BOOL)suppressed;
- (void) setMuted:(BOOL)muted;

@end
