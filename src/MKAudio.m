/* Copyright (C) 2009-2010 Mikkel Krautz <mikkel@krautz.dk>

   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

   - Redistributions of source code must retain the above copyright notice,
     this list of conditions and the following disclaimer.
   - Redistributions in binary form must reproduce the above copyright notice,
     this list of conditions and the following disclaimer in the documentation
     and/or other materials provided with the distribution.
   - Neither the name of the Mumble Developers nor the names of its
     contributors may be used to endorse or promote products derived from this
     software without specific prior written permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR
   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import <MumbleKit/MKUtils.h>
#import <MumbleKit/MKAudio.h>
#import <MumbleKit/MKAudioInput.h>
#import <MumbleKit/MKAudioOutput.h>

@interface MKAudio (Private)
- (id) init;
- (void) dealloc;
@end

static MKAudio *audioSingleton = nil;

#if TARGET_OS_IPHONE == 1
static void MKAudio_InterruptCallback(void *udata, UInt32 interrupt) {
	MKAudio *audio = (MKAudio *) udata;

	if (interrupt == kAudioSessionBeginInterruption) {
		[audio stop];
	} else if (interrupt == kAudioSessionEndInterruption) {
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
			NSLog(@"MKAudio: Unable to set AudioCategory property.");
			return;
		}

		if (val == kAudioSessionCategory_PlayAndRecord) {
			val = 1;
			err = AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryDefaultToSpeaker, sizeof(val), &val);
			if (err != kAudioSessionNoError) {
				NSLog(@"MKAudio: Unable to set OverrideCategoryDefaultToSpeaker property.");
				return;
			}
		}

		[audio restart];
	}
}

static void MKAudio_AudioRouteChangedCallback(MKAudio *audio, AudioSessionPropertyID prop, UInt32 len, NSDictionary *dict) {
	NSLog(@"MKAudio: Audio route changed.");

}
#endif

@implementation MKAudio

+ (MKAudio *) sharedAudio {
	if (audioSingleton == nil)
		audioSingleton = [[MKAudio alloc] init];
	return audioSingleton;
}

- (id) init {
	Float64 fval;
	BOOL audioInputAvailable = YES;

	self = [super init];
	if (self == nil)
		return nil;

#if TARGET_OS_IPHONE == 1
	OSStatus err;
	UInt32 val, valSize;

	// Initialize Audio Session
	err = AudioSessionInitialize(CFRunLoopGetMain(), kCFRunLoopDefaultMode, MKAudio_InterruptCallback, self);
	if (err != kAudioSessionNoError) {
		NSLog(@"MKAudio: Unable to initialize AudioSession.");
		return nil;
	}

	// Listen for audio route changes
	err = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioRouteChange,
										  (AudioSessionPropertyListener)MKAudio_AudioRouteChangedCallback,
										  self);
	if (err != kAudioSessionNoError) {
		NSLog(@"MKAudio: Unable to register property listener for AudioRouteChange.");
		return nil;
	}

	// Listen for audio input availability changes
	err = AudioSessionAddPropertyListener(kAudioSessionProperty_AudioInputAvailable,
										  (AudioSessionPropertyListener)MKAudio_AudioInputAvailableCallback,
										  self);
	if (err != kAudioSessionNoError) {
		NSLog(@"MKAudio: Unable to register property listener for AudioInputAvailable.");
		return nil;
	}

	// To be able to select the correct category, we must query whethe audio input is
	// available.
	valSize = sizeof(UInt32);
	err = AudioSessionGetProperty(kAudioSessionProperty_AudioInputAvailable, &valSize, &val);
	if (err != kAudioSessionNoError || valSize != sizeof(UInt32)) {
		NSLog(@"MKAudio: Unable to query for input availability.");
	}

	// Set the correct category for our Audio Session depending on our current audio input situation.
	audioInputAvailable = (BOOL) val;
	val = audioInputAvailable ? kAudioSessionCategory_PlayAndRecord : kAudioSessionCategory_MediaPlayback;
	err = AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(val), &val);
	if (err != kAudioSessionNoError) {
		NSLog(@"MKAudio: Unable to set AudioCategory property.");
		return nil;
	}

	if (audioInputAvailable) {
		// The OverrideCategoryDefaultToSpeaker property makes us output to the speakers of the iOS device
		// as long as there's not a headset connected.
		val = TRUE;
		err = AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryDefaultToSpeaker, sizeof(val), &val);
		if (err != kAudioSessionNoError) {
			NSLog(@"MKAudio: Unable to set OverrideCategoryDefaultToSpeaker property.");
			return nil;
		}
	}

	// Do we want to be mixed with other applications?
	val = TRUE;
	err = AudioSessionSetProperty(kAudioSessionProperty_OverrideCategoryMixWithOthers, sizeof(val), &val);
	if (err != kAudioSessionNoError) {
		NSLog(@"MKAudio: Unable to set MixWithOthers property.");
		return nil;
	}

	 // Set the preferred hardware sample rate.
	 //
	 // fixme(mkrautz): The AudioSession *can* reject this, in which case we need
	 // to be able to handle whatever input sampling rate is chosen for us. This is
	 // apparently 8KHz on a 1st gen iPhone.
	fval = SAMPLE_RATE;
	err = AudioSessionSetProperty(kAudioSessionProperty_PreferredHardwareSampleRate, sizeof(Float64), &fval);
	if (err != kAudioSessionNoError) {
		NSLog(@"MKAudio: Unable to set preferred hardware sample rate.");
		return nil;
	}

#elif TARGET_OS_MAC == 1
	audioInputAvailable = YES;
#endif

	return self;
}

- (void) dealloc {
	[_audioInput release];
	[_audioOutput release];

	[super dealloc];
}

// Get the audio input engine
- (MKAudioInput *) audioInput {
	return _audioInput;
}

// Get the audio output engine
- (MKAudioOutput *) audioOutput {
	return _audioOutput;
}

// Get current audio engine settings
- (MKAudioSettings *) audioSettings {
	return &_audioSettings;
}

// Set new settings for the audio engine
- (void) updateAudioSettings:(MKAudioSettings *)settings {
	memcpy(&_audioSettings, settings, sizeof(MKAudioSettings));
#ifdef ARCH_ARMV6
    // fixme(mkrautz): Unconditionally disable preprocessor for ARMv6
    _audioSettings.enablePreprocessor = NO;
#endif
}

// Has MKAudio been started?
- (BOOL) isRunning {
	return _running;
}

// Stop the audio engine
- (void) stop {
	[_audioInput release];
	_audioInput = nil;
	[_audioOutput release];
	_audioOutput = nil;
#if TARGET_OS_IPHONE == 1
	AudioSessionSetActive(NO);
#endif
	_running = NO;
}

// Start the audio engine
- (void) start {
#if TARGET_OS_IPHONE == 1
	AudioSessionSetActive(YES);
#endif

	_audioInput = [[MKAudioInput alloc] initWithSettings:&_audioSettings];
	_audioOutput = [[MKAudioOutput alloc] initWithSettings:&_audioSettings];
	[_audioInput setupDevice];
	[_audioOutput setupDevice];
	_running = YES;
}

// Restart the audio engine
- (void) restart {
	[self stop];
	[self start];
}

- (void) addFrameToBufferWithSession:(NSUInteger)session data:(NSData *)data sequence:(NSUInteger)seq type:(MKMessageType)msgType {
	[_audioOutput addFrameToBufferWithSession:session data:data sequence:seq type:msgType];
}

- (BOOL) forceTransmit {
	return [_audioInput forceTransmit];
}

- (void) setForceTransmit:(BOOL)flag {
	[_audioInput setForceTransmit:flag];
}

- (void) getBenchmarkData:(MKAudioBenchmark *)bench {
	if (bench != NULL) {
		bench->avgPreprocessorRuntime = [_audioInput preprocessorAvgRuntime];
	}
}

- (NSString *) currentAudioRoute {
#if TARGET_OS_IPHONE == 1
	// Query for the actual sample rate we're to cope with.
	NSString *route;
	UInt32 len = sizeof(NSString *);
	OSStatus err = AudioSessionGetProperty(kAudioSessionProperty_AudioRoute, &len, &route);
	if (err != kAudioSessionNoError) {
		NSLog(@"MKAudio: Unable to query for current audio route.");
		return @"Unknown";
	}
	return route;
#else
	return @"Unknown";
#endif
}


@end
