// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKAudio.h>
#import "MKUtils.h"
#import "MKAudioInput.h"
#import "MKAudioOutput.h"

NSString *MKAudioDidRestartNotification = @"MKAudioDidRestartNotification";

@interface MKAudio () {
    MKAudioInput     *_audioInput;
    MKAudioOutput    *_audioOutput;
    MKAudioSettings   _audioSettings;
    BOOL              _running;
}
@end

#if TARGET_OS_IPHONE == 1
static void MKAudio_InterruptCallback(void *udata, UInt32 interrupt) {
    MKAudio *audio = (MKAudio *) udata;

    if (interrupt == kAudioSessionBeginInterruption) {
        [audio stop];
    } else if (interrupt == kAudioSessionEndInterruption) {
        UInt32 val = TRUE;
        OSStatus err = AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryMixWithOthers, sizeof(val), &val);
        if (err != kAudioSessionNoError) {
            NSLog(@"MKAudio: unable to set MixWithOthers property in InterruptCallback.");
        }

        [audio start];
    }
}

static void MKAudio_AudioInputAvailableCallback(MKAudio *audio, AudioSessionPropertyID prop, UInt32 len, uint32_t *avail) {
    BOOL audioInputAvailable;
    UInt32 val;
    OSStatus err;

    if (avail) {
        audioInputAvailable = *avail;
        val = audioInputAvailable ? kAudioSessionCategory_PlayAndRecord : kAudioSessionCategory_MediaPlayback;
        err = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(val), &val);
        if (err != kAudioSessionNoError) {
            NSLog(@"MKAudio: unable to set AudioCategory property.");
            return;
        }

        if (val == kAudioSessionCategory_PlayAndRecord) {
            val = 1;
            err = AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryDefaultToSpeaker, sizeof(val), &val);
            if (err != kAudioSessionNoError) {
                NSLog(@"MKAudio: unable to set OverrideCategoryDefaultToSpeaker property.");
                return;
            }
        }
        
        UInt32 val = TRUE;
        OSStatus err = AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryMixWithOthers, sizeof(val), &val);
        if (err != kAudioSessionNoError) {
            NSLog(@"MKAudio: unable to set MixWithOthers property in AudioInputAvailableCallback.");
        }

        [audio restart];
    }
}

static void MKAudio_AudioRouteChangedCallback(MKAudio *audio, AudioSessionPropertyID prop, UInt32 len, NSDictionary *dict) {
    int reason = [[dict objectForKey:(id)kAudioSession_RouteChangeKey_Reason] intValue];
    switch (reason) {
        case kAudioSessionRouteChangeReason_Override:
        case kAudioSessionRouteChangeReason_CategoryChange:
        case kAudioSessionRouteChangeReason_NoSuitableRouteForCategory:
            NSLog(@"MKAudio: audio route changed, skipping; reason=%i", reason);
            return;
    }

    UInt32 val = TRUE;
    OSStatus err = AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryMixWithOthers, sizeof(val), &val);
    if (err != kAudioSessionNoError) {
        NSLog(@"MKAudio: unable to set MixWithOthers property in AudioRouteChangedCallback.");
    }
    
    NSLog(@"MKAudio: audio route changed, restarting audio; reason=%i", reason);
    [audio restart];
}

static void MKAudio_SetupAudioSession(MKAudio *audio) {
    OSStatus err;
    UInt32 val, valSize;
    Float64 fval;
    BOOL audioInputAvailable = YES;
    
    // Initialize Audio Session
    err = AudioSessionInitialize(CFRunLoopGetMain(), kCFRunLoopDefaultMode, MKAudio_InterruptCallback, audio);
    if (err != kAudioSessionNoError) {
        NSLog(@"MKAudio: unable to initialize AudioSession.");
        return;
    }
    
    // Listen for audio route changes
    err = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange,
                                          (AudioSessionPropertyListener) MKAudio_AudioRouteChangedCallback,
                                          audio);
    if (err != kAudioSessionNoError) {
        NSLog(@"MKAudio: unable to register property listener for AudioRouteChange.");
        return;
    }
    
    // Listen for audio input availability changes
    err = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioInputAvailable,
                                          (AudioSessionPropertyListener)MKAudio_AudioInputAvailableCallback,
                                          audio);
    if (err != kAudioSessionNoError) {
        NSLog(@"MKAudio: unable to register property listener for AudioInputAvailable.");
        return;
    }
    
    // To be able to select the correct category, we must query whethe audio input is available.
    valSize = sizeof(UInt32);
    err = AudioSessionGetProperty(kAudioSessionProperty_AudioInputAvailable, &valSize, &val);
    if (err != kAudioSessionNoError || valSize != sizeof(UInt32)) {
        NSLog(@"MKAudio: unable to query for input availability.");
        return;
    }
    
    // Set the correct category for our Audio Session depending on our current audio input situation.
    audioInputAvailable = (BOOL) val;
    val = audioInputAvailable ? kAudioSessionCategory_PlayAndRecord : kAudioSessionCategory_MediaPlayback;
    err = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(val), &val);
    if (err != kAudioSessionNoError) {
        NSLog(@"MKAudio: unable to set AudioCategory property.");
        return;
    }
    
    if (audioInputAvailable) {
        // The OverrideCategoryDefaultToSpeaker property makes us output to the speakers of the iOS device
        // as long as there's not a headset connected.
        val = TRUE;
        err = AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryDefaultToSpeaker, sizeof(val), &val);
        if (err != kAudioSessionNoError) {
            NSLog(@"MKAudio: unable to set OverrideCategoryDefaultToSpeaker property.");
            return;
        }
    }
    
    // Set the preferred hardware sample rate.
    //
    // fixme(mkrautz): The AudioSession *can* reject this, in which case we need
    // to be able to handle whatever input sampling rate is chosen for us. This is
    // apparently 8KHz on a 1st gen iPhone.
    fval = SAMPLE_RATE;
    err = AudioSessionSetProperty(kAudioSessionProperty_PreferredHardwareSampleRate, sizeof(Float64), &fval);
    if (err != kAudioSessionNoError) {
        NSLog(@"MKAudio: unable to set preferred hardware sample rate.");
        return;
    }
    
    if (audioInputAvailable) {
        // Allow input from Bluetooth devices.
        val = 1;
        err = AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryEnableBluetoothInput, sizeof(val), &val);
        if (err != kAudioSessionNoError) {
            NSLog(@"MKAudio: unable to enable bluetooth input.");
            return;
        }
    }
    
    // Allow us to be mixed with other applications.
    // It's important that this call comes last, since changing the other OverrideCategory properties
    // apparently reset the state of this property.
    val = TRUE;
    err = AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryMixWithOthers, sizeof(val), &val);
    if (err != kAudioSessionNoError) {
        NSLog(@"MKAudio: unable to set MixWithOthers property.");
        return;
    }
}
#else
static void MKAudio_SetupAudioSession(MKAudio *audio) {
    (void) audio;
}
#endif

@implementation MKAudio

+ (MKAudio *) sharedAudio {
    static dispatch_once_t pred;
    static MKAudio *audio;

    dispatch_once(&pred, ^{
        audio = [[MKAudio alloc] init];
        MKAudio_SetupAudioSession(audio);
    });

    return audio;
}

// Read the current audio engine settings
- (void) readAudioSettings:(MKAudioSettings *)settings {
    if (settings == NULL)
        return;

    @synchronized(self) {
        memcpy(settings, &_audioSettings, sizeof(MKAudioSettings));
    }
}

// Set new settings for the audio engine
- (void) updateAudioSettings:(MKAudioSettings *)settings {
    @synchronized(self) {
        memcpy(&_audioSettings, settings, sizeof(MKAudioSettings));
    }
}

// Has MKAudio been started?
- (BOOL) isRunning {
    return _running;
}

// Stop the audio engine
- (void) stop {
    @synchronized(self) {
        [_audioInput release];
        _audioInput = nil;
        [_audioOutput release];
        _audioOutput = nil;
        _running = NO;
    }
#if TARGET_OS_IPHONE == 1
    AudioSessionSetActive(NO);
#endif
}

// Start the audio engine
- (void) start {
#if TARGET_OS_IPHONE == 1
    AudioSessionSetActive(YES);
#endif
    @synchronized(self) {
        _audioInput = [[MKAudioInput alloc] initWithSettings:&_audioSettings];
        _audioOutput = [[MKAudioOutput alloc] initWithSettings:&_audioSettings];
        [_audioInput setupDevice];
        [_audioOutput setupDevice];
        _running = YES;
    }
}

// Restart the audio engine
- (void) restart {
    [self stop];
    [self start];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:MKAudioDidRestartNotification object:self];
}

- (void) addFrameToBufferWithSession:(NSUInteger)session data:(NSData *)data sequence:(NSUInteger)seq type:(MKUDPMessageType)msgType {
    @synchronized(self) {
        [_audioOutput addFrameToBufferWithSession:session data:data sequence:seq type:msgType];
    }
}

- (MKTransmitType) transmitType {
    @synchronized(self) {
        return _audioSettings.transmitType;
    }
}

- (BOOL) forceTransmit {
    @synchronized(self) {
        return [_audioInput forceTransmit];
    }
}

- (void) setForceTransmit:(BOOL)flag {
    @synchronized(self) {
        [_audioInput setForceTransmit:flag];
    }
}

- (float) speechProbablity {
    @synchronized(self) {
        return [_audioInput speechProbability];
    }
}

- (float) peakCleanMic {
    @synchronized(self) {
        return [_audioInput peakCleanMic];
    }
}

- (void) setSelfMuted:(BOOL)selfMuted {
    @synchronized(self) {
        [_audioInput setSelfMuted:selfMuted];
    }
}

- (void) setSuppressed:(BOOL)suppressed {
    @synchronized(self) {
        [_audioInput setSuppressed:suppressed];
    }
}

- (void) setMuted:(BOOL)muted {
    @synchronized(self) {
        [_audioInput setMuted:muted];
    }
}

- (BOOL) echoCancellationAvailable {
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    NSDictionary *dict = nil;
    UInt32 valSize = sizeof(NSDictionary *);
    OSStatus err = AudioSessionGetProperty(kAudioSessionProperty_AudioRouteDescription, &valSize, &dict);
    if (err != kAudioSessionNoError) {
        return NO;
    }

    NSArray *inputs = [dict objectForKey:(id)kAudioSession_AudioRouteKey_Inputs];
    if ([inputs count] == 0) {
        return NO;
    }

    NSDictionary *input = [inputs objectAtIndex:0]; 
    NSString *inputKind = [input objectForKey:(id)kAudioSession_AudioRouteKey_Type];

    if ([inputKind isEqualToString:(NSString *)kAudioSessionInputRoute_BuiltInMic])
        return YES;
#endif
    return NO;
}

@end
