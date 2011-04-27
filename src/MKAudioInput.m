/* Copyright (C) 2009-2010 Mikkel Krautz <mikkel@krautz.dk>
   Copyright (C) 2005-2010 Thorvald Natvig <thorvald@natvig.com>

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

#import <MumbleKit/MKAudioInput.h>
#import <MumbleKit/MKPacketDataStream.h>
#import <MumbleKit/MKConnectionController.h>
#import <MumbleKit/MKServerModel.h>

#include <speex/speex.h>
#include <speex/speex_preprocess.h>
#include <speex/speex_echo.h>
#include <speex/speex_resampler.h>
#include <speex/speex_jitter.h>
#include <speex/speex_types.h>
#include <celt.h>

#include "timedelta.h"

struct MKAudioInputPrivate {
	SpeexPreprocessState *preprocessorState;
	CELTEncoder *celtEncoder;
	SpeexResamplerState *micResampler;
	SpeexBits speexBits;
	void *speexEncoder;
};

static OSStatus inputCallback(void *udata, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts,
                              UInt32 busnum, UInt32 nframes, AudioBufferList *buflist) {
	MKAudioInput *i = (MKAudioInput *)udata;
	OSStatus err;

	if (! i->buflist.mBuffers->mData) {
		NSLog(@"AudioInput: No buffer allocated.");
		i->buflist.mNumberBuffers = 1;
		AudioBuffer *b = i->buflist.mBuffers;
		b->mNumberChannels = i->numMicChannels;
		b->mDataByteSize = i->micSampleSize * nframes;
		b->mData = calloc(1, b->mDataByteSize);
	}

	if (i->buflist.mBuffers->mDataByteSize < (nframes/i->micSampleSize)) {
		NSLog(@"AudioInput: Buffer too small. Allocating more space.");
		AudioBuffer *b = i->buflist.mBuffers;
		free(b->mData);
		b->mDataByteSize = i->micSampleSize * nframes;
		b->mData = calloc(1, b->mDataByteSize);
	}

	err = AudioUnitRender(i->audioUnit, flags, ts, busnum, nframes, &i->buflist);
	if (err != noErr) {
#if 0
		NSLog(@"AudioInput: AudioUnitRender failed. err = %i", err);
#endif
		return err;
	}

	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	short *buf = (short *)i->buflist.mBuffers->mData;
	[i addMicrophoneDataWithBuffer:buf amount:nframes];
	[pool release];

	return noErr;
}

@implementation MKAudioInput

- (id) initWithSettings:(MKAudioSettings *)settings {
	self = [super init];
	if (self == nil)
		return nil;

	// Copy settings
	memcpy(&_settings, settings, sizeof(MKAudioSettings));

	// Allocate private struct.
	_private = malloc(sizeof(struct MKAudioInputPrivate));
	_private->preprocessorState = NULL;
	_private->celtEncoder = NULL;
	_private->micResampler = NULL;
	_private->speexEncoder = NULL;

	frameCounter = 0;


	if (_settings.codec == MKCodecFormatCELT) {
		sampleRate = SAMPLE_RATE;
		frameSize = SAMPLE_RATE / 100;
		NSLog(@"AudioInput: %i bits/s, %d Hz, %d sample CELT", _settings.quality, sampleRate, frameSize);
	} else if (_settings.codec == MKCodecFormatSpeex) {
		sampleRate = 32000;

		speex_bits_init(&_private->speexBits);
		speex_bits_reset(&_private->speexBits);
		_private->speexEncoder = speex_encoder_init(speex_lib_get_mode(SPEEX_MODEID_UWB));
		speex_encoder_ctl(_private->speexEncoder, SPEEX_GET_FRAME_SIZE, &frameSize);
		speex_encoder_ctl(_private->speexEncoder, SPEEX_GET_SAMPLING_RATE, &sampleRate);

		int iArg = 1;
		speex_encoder_ctl(_private->speexEncoder, SPEEX_SET_VBR, &iArg);

		iArg = 0;
		speex_encoder_ctl(_private->speexEncoder, SPEEX_SET_VAD, &iArg);
		speex_encoder_ctl(_private->speexEncoder, SPEEX_SET_DTX, &iArg);

		float fArg = 8.0;
		speex_encoder_ctl(_private->speexEncoder, SPEEX_SET_VBR_QUALITY, &fArg);

		iArg = _settings.quality;
		speex_encoder_ctl(_private->speexEncoder, SPEEX_SET_VBR_MAX_BITRATE, &iArg);

		iArg = 5;
		speex_encoder_ctl(_private->speexEncoder, SPEEX_SET_COMPLEXITY, &iArg);
		NSLog(@"AudioInput: %d bits/s, %d Hz, %d sample Speex-UWB", _settings.quality, sampleRate, frameSize);
	}

	doResetPreprocessor = YES;
	previousVoice = NO;

	numMicChannels = 0;
	bitrate = 0;

	/*
	 if (g.uiSession)
		setMaxBandwidth(g.iMaxBandwidth);
	 */

	/* Allocate buffer list. */
	frameList = [[NSMutableArray alloc] initWithCapacity: 20]; /* should be iAudioFrames. */

	udpMessageType = ~0;

	return self;
}

- (void) dealloc {
	// fixme(mkrautz): Return value?
	[self teardownDevice];

	[frameList release];

	if (psMic)
		free(psMic);
	if (psOut)
		free(psOut);

	if (_private->speexEncoder)
		speex_encoder_destroy(_private->speexEncoder);
	if (_private->micResampler)
		speex_resampler_destroy(_private->micResampler);
	if (_private->celtEncoder)
		celt_encoder_destroy(_private->celtEncoder);
	if (_private->preprocessorState)
		speex_preprocess_state_destroy(_private->preprocessorState);

	if (_private)
		free(_private);

	[super dealloc];
}

- (void) initializeMixer {
	int err;

	NSLog(@"AudioInput: initializeMixer -- iMicFreq=%u, iSampleRate=%u", micFrequency, sampleRate);

	micLength = (frameSize * micFrequency) / sampleRate;

	if (_private->micResampler)
		speex_resampler_destroy(_private->micResampler);

	if (psMic)
		free(psMic);
	if (psOut)
		free(psOut);

	if (micFrequency != sampleRate)
		_private->micResampler = speex_resampler_init(1, micFrequency, sampleRate, 3, &err);

	psMic = malloc(micLength * sizeof(short));
	psOut = malloc(frameSize * sizeof(short));
	micSampleSize = numMicChannels * sizeof(short);
	doResetPreprocessor = YES;

	NSLog(@"AudioInput: Initialized mixer for %i channel %i Hz and %i channel %i Hz echo", numMicChannels, micFrequency, 0, 0);
}

- (BOOL) setupDevice {
	UInt32 len;
	UInt32 val;
	OSStatus err;
	AudioComponent comp;
	AudioComponentDescription desc;
	AudioStreamBasicDescription fmt;
#if TARGET_OS_MAC == 1 && TARGET_OS_IPHONE == 0
	AudioDeviceID devId;

	// Get default device
	len = sizeof(AudioDeviceID);
	err = AudioHardwareGetProperty(kAudioHardwarePropertyDefaultInputDevice, &len, &devId);
	if (err != noErr) {
		NSLog(@"AudioInput: Unable to query for default device.");
		return NO;
	}
#endif

	desc.componentType = kAudioUnitType_Output;
#if TARGET_OS_IPHONE == 1
# ifdef USE_VPIO
    desc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
# else
	desc.componentSubType = kAudioUnitSubType_RemoteIO;
# endif
#elif TARGET_OS_MAC == 1
	desc.componentSubType = kAudioUnitSubType_HALOutput;
#endif
	desc.componentManufacturer = kAudioUnitManufacturer_Apple;
	desc.componentFlags = 0;
	desc.componentFlagsMask = 0;

	comp = AudioComponentFindNext(NULL, &desc);
	if (! comp) {
		NSLog(@"AudioInput: Unable to find AudioUnit.");
		return NO;
	}

	err = AudioComponentInstanceNew(comp, (AudioComponentInstance *) &audioUnit);
	if (err != noErr) {
		NSLog(@"AudioInput: Unable to instantiate new AudioUnit.");
		return NO;
	}

#if TARGET_OS_MAC == 1 && TARGET_OS_IPHONE == 0
	err = AudioUnitInitialize(audioUnit);
	if (err != noErr) {
		NSLog(@"AudioInput: Unable to initialize AudioUnit.");
		return NO;
	}
#endif

	/* fixme(mkrautz): Backport some of this to the desktop CoreAudio backend? */

	val = 1;
	err = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &val, sizeof(UInt32));
	if (err != noErr) {
		NSLog(@"AudioInput: Unable to configure input scope on AudioUnit.");
		return NO;
	}

	val = 0;
	err = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &val, sizeof(UInt32));
	if (err != noErr) {
		NSLog(@"AudioInput: Unable to configure output scope on AudioUnit.");
		return NO;
	}

#if TARGET_OS_MAC == 1 && TARGET_OS_IPHONE == 0
	// Set default device
	len = sizeof(AudioDeviceID);
	err = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &devId, len);
	if (err != noErr) {
		NSLog(@"AudioInput: Unable to set default device.");
		return NO;
	}
#endif

	AURenderCallbackStruct cb;
	cb.inputProc = inputCallback;
	cb.inputProcRefCon = self;
	len = sizeof(AURenderCallbackStruct);
	err = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &cb, len);
	if (err != noErr) {
		NSLog(@"AudioInput: Unable to setup callback.");
		return NO;
	}

	len = sizeof(AudioStreamBasicDescription);
	err = AudioUnitGetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &fmt, &len);
	if (err != noErr) {
		NSLog(@"CoreAudioInput: Unable to query device for stream info.");
		return NO;
	}

	if (fmt.mChannelsPerFrame > 1) {
		NSLog(@"AudioInput: Input device with more than one channel detected. Defaulting to 1.");
	}

	micFrequency = (int) 48000;
	numMicChannels = 1;
	[self initializeMixer];

	fmt.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
	fmt.mBitsPerChannel = sizeof(short) * 8;
	fmt.mFormatID = kAudioFormatLinearPCM;
	fmt.mSampleRate = micFrequency;
	fmt.mChannelsPerFrame = numMicChannels;
	fmt.mBytesPerFrame = micSampleSize;
	fmt.mBytesPerPacket = micSampleSize;
	fmt.mFramesPerPacket = 1;

	len = sizeof(AudioStreamBasicDescription);
	err = AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &fmt, len);
	if (err != noErr) {
		NSLog(@"AudioInput: Unable to set stream format for output device. (output scope)");
		return NO;
	}

/*	len = sizeof(AudioStreamBasicDescription);
	err = AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, len);
	if (err != noErr) {
		NSLog(@"AudioInput: Unable to set stream format for output device. (input scope)");
		return NO;
	}*/

#if TARGET_OS_MAC == 1 && TARGET_OS_IPHONE == 1
#ifdef USE_VPIO
    val = 1;
    len = sizeof(UInt32);
    err = AudioUnitSetProperty(audioUnit, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 0, &val, len);
    if (err != noErr) {
        NSLog(@"AudioInput: Unable to disable VPIO voice processing.");
        return NO;
    }

    val = 0;
    len = sizeof(UInt32);
    err = AudioUnitSetProperty(audioUnit, kAUVoiceIOProperty_VoiceProcessingEnableAGC, kAudioUnitScope_Global, 0, &val, len);
    if (err != noErr) {
        NSLog(@"AudioInput: Unable to disable VPIO AGC.");
        return NO;
    }
#endif

	err = AudioUnitInitialize(audioUnit);
	if (err != noErr) {
		NSLog(@"AudioInput: Unable to initialize AudioUnit.");
		return NO;
	}
#endif

	err = AudioOutputUnitStart(audioUnit);
	if (err != noErr) {
		NSLog(@"AudioInput: Unable to start AudioUnit.");
		return NO;
	}

	return YES;
}

- (BOOL) teardownDevice {
	OSStatus err;

	err = AudioOutputUnitStop(audioUnit);
	if (err != noErr) {
		NSLog(@"AudioInput: Unable to stop AudioUnit.");
		return NO;
	}

	AudioBuffer *b = buflist.mBuffers;
	if (b && b->mData)
		free(b->mData);

	NSLog(@"AudioInput: Teardown finished.");
	return YES;
}

- (void) addMicrophoneDataWithBuffer:(short *)input amount:(NSUInteger)nsamp {
	int i;

	while (nsamp > 0) {
		unsigned int left = MIN(nsamp, micLength - micFilled);

		short *output = psMic + micFilled;

		for (i = 0; i < left; i++) {
			output[i] = input[i];
		}

		input += left;
		micFilled += left;
		nsamp -= left;

		if (micFilled == micLength) {
			// Should we resample?
			if (_private->micResampler) {
				spx_uint32_t inlen = micLength;
				spx_uint32_t outlen = frameSize;
				speex_resampler_process_int(_private->micResampler, 0, psMic, &inlen, psOut, &outlen);
			}
			micFilled = 0;
			[self encodeAudioFrame];
		}
	}
}

- (void) resetPreprocessor {
	int iArg;

	_preprocAvgItems = 0;
	_preprocRunningAvg = 0;

	if (_private->preprocessorState)
		speex_preprocess_state_destroy(_private->preprocessorState);

	_private->preprocessorState = speex_preprocess_state_init(frameSize, sampleRate);
	SpeexPreprocessState *state = _private->preprocessorState;

	iArg = 1;
	speex_preprocess_ctl(state, SPEEX_PREPROCESS_SET_VAD, &iArg);
	speex_preprocess_ctl(state, SPEEX_PREPROCESS_SET_AGC, &iArg);
	speex_preprocess_ctl(state, SPEEX_PREPROCESS_SET_DENOISE, &iArg);
	speex_preprocess_ctl(state, SPEEX_PREPROCESS_SET_DEREVERB, &iArg);

	iArg = 30000;
	speex_preprocess_ctl(state, SPEEX_PREPROCESS_SET_AGC_TARGET, &iArg);

	//float v = 30000.0f / (float) 0.0f; // iMinLoudness
	//iArg = iroundf(floorf(20.0f * log10f(v)));
	//speex_preprocess_ctl(state, SPEEX_PREPROCESS_SET_AGC_MAX_GAIN, &iArg);

	iArg = _settings.noiseSuppression;
	speex_preprocess_ctl(state, SPEEX_PREPROCESS_SET_NOISE_SUPPRESS, &iArg);
}

- (void) encodeAudioFrame {

	frameCounter++;

	if (doResetPreprocessor) {
		[self resetPreprocessor];
		doResetPreprocessor = NO;
	}

	int isSpeech = 0;
	if (_settings.enablePreprocessor) {
#if 1
		if (_settings.enableBenchmark) {
			TimeDelta td;
			TimeDelta_start(&td);
			isSpeech = speex_preprocess_run(_private->preprocessorState, psMic);
			TimeDelta_stop(&td);
			unsigned long udt = TimeDelta_usec_delta(&td);
			if (_preprocAvgItems == 0)
				_preprocRunningAvg = (long)udt;
			else
				_preprocRunningAvg += (((long)udt - _preprocRunningAvg) / _preprocAvgItems);
			++_preprocAvgItems;
		} else
#endif
		{
			isSpeech = speex_preprocess_run(_private->preprocessorState, psMic);
		}
	}

	unsigned char buffer[1024];
	int len = 0;

	if (_settings.codec == MKCodecFormatCELT) {
		CELTEncoder *encoder = _private->celtEncoder;
		if (encoder == NULL) {
			CELTMode *mode = celt_mode_create(SAMPLE_RATE, SAMPLE_RATE / 100, NULL);
			_private->celtEncoder = celt_encoder_create(mode, 1, NULL);
			encoder = _private->celtEncoder;
		}

		// Make sure our messageType is set up correctly....
		// This is just temporary. We should have a MKCodecController that should handle this.
		static const NSInteger ourCodec = 0x8000000b;
		NSArray *conns = [[MKConnectionController sharedController] allConnections];
		if ([conns count] > 0) {
			MKConnection *conn = [[conns objectAtIndex:0] pointerValue];
			if ([conn connected]) {
				NSInteger alpha = [conn alphaCodec];
				NSInteger beta = [conn betaCodec];
				BOOL preferAlpha = [conn preferAlphaCodec];
				NSInteger newCodec = preferAlpha ? alpha : beta;
				NSInteger msgType = preferAlpha ? UDPVoiceCELTAlphaMessage : UDPVoiceCELTBetaMessage;
				if (newCodec != ourCodec) {
					newCodec = preferAlpha ? beta : alpha;
					msgType = preferAlpha ? UDPVoiceCELTBetaMessage : UDPVoiceCELTAlphaMessage;
				}
				if (newCodec == ourCodec && msgType != udpMessageType) {
					udpMessageType = msgType;
					NSLog(@"MKAudioInput: udpMessageType changed to %i", msgType);
				}
			}
		}

		if (!previousVoice) {
			celt_encoder_ctl(encoder, CELT_RESET_STATE);
			NSLog(@"AudioInput: Reset CELT state.");
		}

		celt_encoder_ctl(encoder, CELT_SET_PREDICTION(0));
		celt_encoder_ctl(encoder, CELT_SET_VBR_RATE(_settings.quality));
		len = celt_encode(encoder, psMic, NULL, buffer, MIN(_settings.quality / 800, 127));

		bitrate = len * 100 * 8;
	} else if (_settings.codec == MKCodecFormatSpeex) {
		int vbr = 0;
		speex_encoder_ctl(_private->speexEncoder, SPEEX_GET_VBR_MAX_BITRATE, &vbr);
		if (vbr != _settings.quality) {
			vbr = _settings.quality;
			speex_encoder_ctl(_private->speexEncoder, SPEEX_SET_VBR_MAX_BITRATE, &vbr);
		}
		if (! previousVoice)
			speex_encoder_ctl(_private->speexEncoder, SPEEX_RESET_STATE, NULL);
		speex_encode_int(_private->speexEncoder, psOut, &_private->speexBits);
		len = speex_bits_write(&_private->speexBits, (char *)buffer, 127);
		speex_bits_reset(&_private->speexBits);
		bitrate = len * 50 * 8;
		udpMessageType = UDPVoiceSpeexMessage;
		NSLog(@"MKAudioInput: udpMessageType changed to 0x%x", udpMessageType);
	}

	NSData *outputBuffer = [[NSData alloc] initWithBytes:buffer length:len];
	[self flushCheck:outputBuffer terminator:NO];
	[outputBuffer release];

	previousVoice = YES;
}

//
// Flush check.
//
// Queue up frames, and send them to the server when enough frames have been
// queued up.
//
- (void) flushCheck:(NSData *)codedSpeech terminator:(BOOL)terminator {
	[frameList addObject:codedSpeech];

	if (! terminator && [frameList count] < _settings.audioPerPacket) {
		return;
	}

	int flags = 0;
	if (terminator)
		flags = 0; /* g.iPrevTarget. */

	/*
	 * Server loopback:
	 * flags = 0x1f;
	 */
	flags |= (udpMessageType << 5);

	unsigned char data[1024];
	data[0] = (unsigned char )(flags & 0xff);

	MKPacketDataStream *pds = [[MKPacketDataStream alloc] initWithBuffer:(data+1) length:1023];
	[pds addVarint:(frameCounter - [frameList count])];

	/* fix terminator stuff here. */

	int i, nframes = [frameList count];
	for (i = 0; i < nframes; i++) {
		NSData *frame = [frameList objectAtIndex:i];
		unsigned char head = (unsigned char)[frame length];
		if (i < nframes-1)
			head |= 0x80;
		[pds appendValue:head];
		[pds appendBytes:(unsigned char *)[frame bytes] length:[frame length]];
	}
	[frameList removeAllObjects];

	NSUInteger len = [pds size] + 1;
	[pds release];

	_doTransmit = _forceTransmit;
	if (_lastTransmit != _doTransmit) {
		// fixme(mkrautz): Handle more talkstates
		MKTalkState talkState = _doTransmit ? MKTalkStateTalking : MKTalkStatePassive;
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		NSDictionary *talkStateDict = [NSDictionary dictionaryWithObjectsAndKeys:
											[NSNumber numberWithUnsignedInteger:talkState], @"talkState",
									   nil];
		NSNotification *notification = [NSNotification notificationWithName:@"MKAudioUserTalkStateChanged" object:talkStateDict];
		[center performSelectorOnMainThread:@selector(postNotification:) withObject:notification waitUntilDone:NO];
	}

	if (_doTransmit) {
		MKConnectionController *conns = [MKConnectionController sharedController];
		NSArray *connections = [conns allConnections];
		NSData *msgData = [[NSData alloc] initWithBytes:data length:len];

		for (NSValue *val in connections) {
			MKConnection *conn = [val pointerValue];
			[conn sendVoiceData:msgData];
		}

		[msgData release];
	}

	_lastTransmit = _doTransmit;
}

- (void) setForceTransmit:(BOOL)flag {
	_forceTransmit = flag;
}

- (BOOL) forceTransmit {
	return _forceTransmit;
}

- (long) preprocessorAvgRuntime {
	return _preprocRunningAvg;
}

@end
