// Copyright 2005-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKConnectionController.h>
#import <MumbleKit/MKServerModel.h>
#import <MumbleKit/MKVersion.h>
#import "MKPacketDataStream.h"
#import "MKAudioInput.h"

#include <speex/speex.h>
#include <speex/speex_preprocess.h>
#include <speex/speex_echo.h>
#include <speex/speex_resampler.h>
#include <speex/speex_jitter.h>
#include <speex/speex_types.h>
#include <celt.h>
#include <opus.h>

@interface MKAudioInput () {
    @public
    AudioUnit              audioUnit;
    AudioBufferList        buflist;
    int                    micSampleSize;
    int                    numMicChannels;

    @private
    MKAudioSettings        _settings;

    SpeexPreprocessState   *_preprocessorState;
    CELTEncoder            *_celtEncoder;
    SpeexResamplerState    *_micResampler;
    SpeexBits              _speexBits;
    void                   *_speexEncoder;
    OpusEncoder            *_opusEncoder;

    int                    frameSize;
    int                    micFrequency;
    int                    sampleRate;

    int                    micFilled;
    int                    micLength;
    int                    bitrate;
    int                    frameCounter;
    int                    _bufferedFrames;

    BOOL                   doResetPreprocessor;

    short                  *psMic;
    short                  *psOut;

    MKUDPMessageType       udpMessageType;
    NSMutableArray         *frameList;

    MKCodecFormat          _codecFormat;
    BOOL                   _doTransmit;
    BOOL                   _forceTransmit;
    BOOL                   _lastTransmit;

    signed long            _preprocRunningAvg;
    signed long            _preprocAvgItems;

    float                  _speechProbability;
    float                  _peakCleanMic;

    BOOL                   _selfMuted;
    BOOL                   _muted;
    BOOL                   _suppressed;
    
    NSMutableData          *_opusBuffer;
}
- (BOOL) setupMacDevice;
- (BOOL) setupiOSDevice;
@end

static OSStatus inputCallback(void *udata, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts,
                              UInt32 busnum, UInt32 nframes, AudioBufferList *buflist) {
    MKAudioInput *i = (MKAudioInput *)udata;
    OSStatus err;
    
    if (! i->buflist.mBuffers->mData) {
        NSLog(@"MKAudioInput: No buffer allocated.");
        i->buflist.mNumberBuffers = 1;
        AudioBuffer *b = i->buflist.mBuffers;
        b->mNumberChannels = i->numMicChannels;
        b->mDataByteSize = i->micSampleSize * nframes;
        b->mData = calloc(1, b->mDataByteSize);
    }

    if (i->buflist.mBuffers->mDataByteSize < (nframes/i->micSampleSize)) {
        NSLog(@"MKAudioInput: Buffer too small. Allocating more space.");
        AudioBuffer *b = i->buflist.mBuffers;
        free(b->mData);
        b->mDataByteSize = i->micSampleSize * nframes;
        b->mData = calloc(1, b->mDataByteSize);
    }

    err = AudioUnitRender(i->audioUnit, flags, ts, busnum, nframes, &i->buflist);
    if (err != noErr) {
        NSLog(@"MKAudioInput: AudioUnitRender failed. err = %ld", err);
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
    
    _preprocessorState = NULL;
    _celtEncoder = NULL;
    _micResampler = NULL;
    _speexEncoder = NULL;
    frameCounter = 0;
    _bufferedFrames = 0;
    
    // Fall back to CELT if Opus is not enabled.
    if (![[MKVersion sharedVersion] isOpusEnabled] && _settings.codec == MKCodecFormatOpus) {
        _settings.codec = MKCodecFormatCELT;
        NSLog(@"Falling back to CELT");
    }

    if (_settings.codec == MKCodecFormatOpus) {
        sampleRate = SAMPLE_RATE;
        frameSize = SAMPLE_RATE / 100;
        _opusEncoder = opus_encoder_create(SAMPLE_RATE, 1, OPUS_APPLICATION_VOIP, NULL);
        opus_encoder_ctl(_opusEncoder, OPUS_SET_VBR(1));
        NSLog(@"MKAudioInput: %i bits/s, %d Hz, %d sample Opus", _settings.quality, sampleRate, frameSize);
    } else if (_settings.codec == MKCodecFormatCELT) {
        sampleRate = SAMPLE_RATE;
        frameSize = SAMPLE_RATE / 100;
        NSLog(@"MKAudioInput: %i bits/s, %d Hz, %d sample CELT", _settings.quality, sampleRate, frameSize);
    } else if (_settings.codec == MKCodecFormatSpeex) {
        sampleRate = 32000;

        speex_bits_init(&_speexBits);
        speex_bits_reset(&_speexBits);
        _speexEncoder = speex_encoder_init(speex_lib_get_mode(SPEEX_MODEID_UWB));
        speex_encoder_ctl(_speexEncoder, SPEEX_GET_FRAME_SIZE, &frameSize);
        speex_encoder_ctl(_speexEncoder, SPEEX_GET_SAMPLING_RATE, &sampleRate);

        int iArg = 1;
        speex_encoder_ctl(_speexEncoder, SPEEX_SET_VBR, &iArg);

        iArg = 0;
        speex_encoder_ctl(_speexEncoder, SPEEX_SET_VAD, &iArg);
        speex_encoder_ctl(_speexEncoder, SPEEX_SET_DTX, &iArg);

        float fArg = 8.0;
        speex_encoder_ctl(_speexEncoder, SPEEX_SET_VBR_QUALITY, &fArg);

        iArg = _settings.quality;
        speex_encoder_ctl(_speexEncoder, SPEEX_SET_VBR_MAX_BITRATE, &iArg);

        iArg = 5;
        speex_encoder_ctl(_speexEncoder, SPEEX_SET_COMPLEXITY, &iArg);
        NSLog(@"MKAudioInput: %d bits/s, %d Hz, %d sample Speex-UWB", _settings.quality, sampleRate, frameSize);
    }

    doResetPreprocessor = YES;
    _lastTransmit = NO;

    numMicChannels = 0;
    bitrate = 0;

    /*
     if (g.uiSession)
        setMaxBandwidth(g.iMaxBandwidth);
     */

    frameList = [[NSMutableArray alloc] initWithCapacity:_settings.audioPerPacket];

    udpMessageType = ~0;

    return self;
}

- (void) dealloc {
    // fixme(mkrautz): Return value?
    [self teardownDevice];

    [frameList release];
    [_opusBuffer release];

    if (psMic)
        free(psMic);
    if (psOut)
        free(psOut);

    if (_speexEncoder)
        speex_encoder_destroy(_speexEncoder);
    if (_micResampler)
        speex_resampler_destroy(_micResampler);
    if (_celtEncoder)
        celt_encoder_destroy(_celtEncoder);
    if (_preprocessorState)
        speex_preprocess_state_destroy(_preprocessorState);
    if (_opusEncoder)
		opus_encoder_destroy(_opusEncoder);

    [super dealloc];
}

- (void) initializeMixer {
    int err;

    NSLog(@"MKAudioInput: initializeMixer -- iMicFreq=%u, iSampleRate=%u", micFrequency, sampleRate);

    micLength = (frameSize * micFrequency) / sampleRate;

    if (_micResampler)
        speex_resampler_destroy(_micResampler);

    if (psMic)
        free(psMic);
    if (psOut)
        free(psOut);

    if (micFrequency != sampleRate) {
        _micResampler = speex_resampler_init(1, micFrequency, sampleRate, 3, &err);
        NSLog(@"MKAudioInput: initialized resampler (%iHz -> %iHz)", micFrequency, sampleRate);
    }

    psMic = malloc(micLength * sizeof(short));
    psOut = malloc(frameSize * sizeof(short));
    micSampleSize = numMicChannels * sizeof(short);
    doResetPreprocessor = YES;

    NSLog(@"MKAudioInput: Initialized mixer for %i channel %i Hz and %i channel %i Hz echo", numMicChannels, micFrequency, 0, 0);
}

- (BOOL) setupDevice {
#if TARGET_IPHONE_SIMULATOR
    return [self setupiOSDevice];
#else
#if TARGET_OS_MAC == 1 && TARGET_OS_IPHONE == 0
    return [self setupMacDevice];
#elif TARGET_OS_MAC == 1 && TARGET_OS_IPHONE == 1
    return [self setupiOSDevice];
#endif
#endif
}

- (BOOL) setupMacDevice {
#if TARGET_OS_MAC == 1 && TARGET_OS_IPHONE == 0
    UInt32 len;
    UInt32 val;
    OSStatus err;
    AudioComponent comp;
    AudioComponentDescription desc;
    AudioStreamBasicDescription fmt;
    AudioDeviceID devId;

    // Get default device
    len = sizeof(AudioDeviceID);
    err = AudioHardwareGetProperty(kAudioHardwarePropertyDefaultInputDevice, &len, &devId);
    if (err != noErr) {
        NSLog(@"MKAudioInput: Unable to query for default device.");
        return NO;
    }

    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_HALOutput;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;

    comp = AudioComponentFindNext(NULL, &desc);
    if (! comp) {
        NSLog(@"MKAudioInput: Unable to find AudioUnit.");
        return NO;
    }

    err = AudioComponentInstanceNew(comp, (AudioComponentInstance *) &audioUnit);
    if (err != noErr) {
        NSLog(@"AudioInput: Unable to instantiate new AudioUnit.");
        return NO;
    }

    err = AudioUnitInitialize(audioUnit);
    if (err != noErr) {
        NSLog(@"MKAudioInput: Unable to initialize AudioUnit.");
        return NO;
    }

    val = 1;
    err = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &val, sizeof(UInt32));
    if (err != noErr) {
        NSLog(@"MKAudioInput: Unable to configure input scope on AudioUnit.");
        return NO;
    }

    val = 0;
    err = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &val, sizeof(UInt32));
    if (err != noErr) {
        NSLog(@"MKAudioInput: Unable to configure output scope on AudioUnit.");
        return NO;
    }

    // Set default device
    len = sizeof(AudioDeviceID);
    err = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &devId, len);
    if (err != noErr) {
        NSLog(@"MKAudioInput: Unable to set default device.");
        return NO;
    }

    len = sizeof(AudioStreamBasicDescription);
    err = AudioUnitGetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &fmt, &len);
    if (err != noErr) {
        NSLog(@"MKAudioInput: Unable to query device for stream info.");
        return NO;
    }

    if (fmt.mChannelsPerFrame > 1) {
        NSLog(@"MKAudioInput: Input device with more than one channel detected. Defaulting to 1.");
    }

    micFrequency = (int) fmt.mSampleRate;
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
        NSLog(@"MKAudioInput: Unable to set stream format for output device. (output scope)");
        return NO;
    }

    AURenderCallbackStruct cb;
    cb.inputProc = inputCallback;
    cb.inputProcRefCon = self;
    len = sizeof(AURenderCallbackStruct);
    err = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &cb, len);
    if (err != noErr) {
        NSLog(@"MKAudioInput: Unable to setup callback.");
        return NO;
    }

    err = AudioOutputUnitStart(audioUnit);
    if (err != noErr) {
        NSLog(@"MKAudioInput: Unable to start AudioUnit.");
        return NO;
    }

    return YES;
#else
    return NO;
#endif
}

- (BOOL) setupiOSDevice {
#if TARGET_OS_IPHONE == 1
    UInt32 len;
    UInt32 val;
    OSStatus err;
    AudioComponent comp;
    AudioComponentDescription desc;
    AudioStreamBasicDescription fmt;
    
    BOOL shouldCancelEcho = NO;
    if ([[MKAudio sharedAudio] echoCancellationAvailable]) {
        shouldCancelEcho = _settings.enableEchoCancellation;
    }
    
    desc.componentType = kAudioUnitType_Output;
    if (shouldCancelEcho)
        desc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    else
        desc.componentSubType = kAudioUnitSubType_RemoteIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    
    comp = AudioComponentFindNext(NULL, &desc);
    if (! comp) {
        NSLog(@"MKAudioInput: Unable to find AudioUnit.");
        return NO;
    }
    
    err = AudioComponentInstanceNew(comp, (AudioComponentInstance *) &audioUnit);
    if (err != noErr) {
        NSLog(@"MKAudioInput: Unable to instantiate new AudioUnit.");
        return NO;
    }
    
    /* fixme(mkrautz): Backport some of this to the desktop CoreAudio backend? */
    
    val = 1;
    err = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &val, sizeof(UInt32));
    if (err != noErr) {
        NSLog(@"MKAudioInput: Unable to configure input scope on AudioUnit.");
        return NO;
    }
    
    val = 0;
    err = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &val, sizeof(UInt32));
    if (err != noErr) {
        NSLog(@"MKAudioInput: Unable to configure output scope on AudioUnit.");
        return NO;
    }
    
    AURenderCallbackStruct cb;
    cb.inputProc = inputCallback;
    cb.inputProcRefCon = self;
    len = sizeof(AURenderCallbackStruct);
    err = AudioUnitSetProperty(audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &cb, len);
    if (err != noErr) {
        NSLog(@"MKAudioInput: Unable to setup callback.");
        return NO;
    }
    
    len = sizeof(AudioStreamBasicDescription);
    err = AudioUnitGetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &fmt, &len);
    if (err != noErr) {
        NSLog(@"MKAudioInput: Unable to query device for stream info.");
        return NO;
    }
    
    if (fmt.mChannelsPerFrame > 1) {
        NSLog(@"MKAudioInput: Input device with more than one channel detected. Defaulting to 1.");
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
        NSLog(@"MKAudioInput: Unable to set stream format for output device. (output scope)");
        return NO;
    }
    
    if (shouldCancelEcho) {
        val = 0;
        len = sizeof(UInt32);
        err = AudioUnitSetProperty(audioUnit, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 0, &val, len);
        if (err != noErr) {
            NSLog(@"MKAudioInput: Unable to disable VPIO voice processing.");
            return NO;
        }
    
        val = 0;
        len = sizeof(UInt32);
        err = AudioUnitSetProperty(audioUnit, kAUVoiceIOProperty_VoiceProcessingEnableAGC, kAudioUnitScope_Global, 0, &val, len);
        if (err != noErr) {
            NSLog(@"MKAudioInput: Unable to disable VPIO AGC.");
            return NO;
        }

        // It's sufficient to set the quality to 0 for our use case; we do our own preprocessing
        // after this, and the job of the VPIO is only to do echo cancellation.
        val = 0;
        len = sizeof(UInt32);
        err = AudioUnitSetProperty(audioUnit, kAUVoiceIOProperty_VoiceProcessingQuality, kAudioUnitScope_Global, 0, &val, len);
        if (err != noErr) {
            NSLog(@"MKAudioInput: unable to set VPIO quality.");
            return NO;
        }
    }

    err = AudioUnitInitialize(audioUnit);
    if (err != noErr) {
        NSLog(@"MKAudioInput: Unable to initialize AudioUnit.");
        return NO;
    }
    
    err = AudioOutputUnitStart(audioUnit);
    if (err != noErr) {
        NSLog(@"MKAudioInput: Unable to start AudioUnit.");
        return NO;
    }
    
    return YES;
#endif
    return NO;
}

- (BOOL) teardownDevice {
    OSStatus err;

    err = AudioOutputUnitStop(audioUnit);
    if (err != noErr) {
        NSLog(@"MKAudioInput: unable to stop AudioUnit.");
        return NO;
    }
    
    err = AudioComponentInstanceDispose(audioUnit);
    if (err != noErr) {
        NSLog(@"MKAudioInput: unable to dispose of AudioUnit.");
        return NO;
    }

    AudioBuffer *b = buflist.mBuffers;
    if (b && b->mData)
        free(b->mData);

    NSLog(@"MKAudioInput: teardown finished.");
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
            if (_micResampler) {
                spx_uint32_t inlen = micLength;
                spx_uint32_t outlen = frameSize;
                speex_resampler_process_int(_micResampler, 0, psMic, &inlen, psOut, &outlen);
            }
            micFilled = 0;
            [self processAndEncodeAudioFrame];
        }
    }
}

- (void) resetPreprocessor {
    int iArg;

    _preprocAvgItems = 0;
    _preprocRunningAvg = 0;

    if (_preprocessorState)
        speex_preprocess_state_destroy(_preprocessorState);

    _preprocessorState = speex_preprocess_state_init(frameSize, sampleRate);
    SpeexPreprocessState *state = _preprocessorState;

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

- (int) encodeAudioFrameOfSpeech:(BOOL)isSpeech intoBuffer:(unsigned char *)encbuf ofSize:(int)max  {
    int len = 0;
    int encoded = 1;  
    BOOL resampled = micFrequency != sampleRate;
    
    if (max < 500)
        return -1;

    BOOL useOpus = NO;
    if (_lastTransmit) {
        useOpus = udpMessageType == UDPVoiceOpusMessage;
    } else if ([[MKVersion sharedVersion] isOpusEnabled]) {
        NSArray *conns = [[MKConnectionController sharedController] allConnections];
        if ([conns count] > 0) {
            MKConnection *conn = [[conns objectAtIndex:0] pointerValue];
            useOpus = [conn shouldUseOpus];
        }
    }
    
    if (useOpus && (_settings.codec == MKCodecFormatOpus || _settings.codec == MKCodecFormatCELT)) {
        encoded = 0;
        udpMessageType = UDPVoiceOpusMessage;
        if (_opusBuffer == nil)
            _opusBuffer = [[NSMutableData alloc] init];
        _bufferedFrames++;
        [_opusBuffer appendBytes:(resampled ? psOut : psMic) length:frameSize*sizeof(short)];
        if (!isSpeech || _bufferedFrames >= _settings.audioPerPacket) {
            if (!_lastTransmit) {
                opus_encoder_ctl(_opusEncoder, OPUS_RESET_STATE, NULL);
            }
            opus_encoder_ctl(_opusEncoder, OPUS_SET_BITRATE(_settings.quality));
            len = opus_encode(_opusEncoder, (short *) [_opusBuffer bytes], _bufferedFrames * frameSize, encbuf, max);
            bitrate = len * 100 * 8;
            [_opusBuffer setLength:0];
            if (len <= 0) {
                return -1;
            }
            encoded = 1;
        }
    } else if (!useOpus && (_settings.codec == MKCodecFormatCELT || _settings.codec == MKCodecFormatOpus)) {
        CELTEncoder *encoder = _celtEncoder;
        if (encoder == NULL) {
            CELTMode *mode = celt_mode_create(SAMPLE_RATE, SAMPLE_RATE / 100, NULL);
            _celtEncoder = celt_encoder_create(mode, 1, NULL);
            encoder = _celtEncoder;
        }
        
        // Make sure our messageType is set up correctly....
        // This is just temporary. We should have a MKCodecController that should handle this.
        NSArray *conns = [[MKConnectionController sharedController] allConnections];
        if ([conns count] > 0) {
            MKConnection *conn = [[conns objectAtIndex:0] pointerValue];
            if ([conn connected]) {
                NSUInteger ourCodec = 0x8000000b;
                NSUInteger alpha = [conn alphaCodec];
                NSUInteger beta = [conn betaCodec];
                BOOL preferAlpha = [conn preferAlphaCodec];
                
                NSInteger newCodec = preferAlpha ? alpha : beta;
                NSInteger msgType = preferAlpha ? UDPVoiceCELTAlphaMessage : UDPVoiceCELTBetaMessage;
                
                if (newCodec != ourCodec) {
                    newCodec = preferAlpha ? beta : alpha;
                    msgType = preferAlpha ? UDPVoiceCELTBetaMessage : UDPVoiceCELTAlphaMessage;
                }
                if (msgType != udpMessageType) {
                    udpMessageType = msgType;
                }
            }
        }
        if (!_lastTransmit) {
            celt_encoder_ctl(encoder, CELT_RESET_STATE);
        }
        
        celt_encoder_ctl(encoder, CELT_SET_PREDICTION(0));
        celt_encoder_ctl(encoder, CELT_SET_VBR_RATE(_settings.quality));
        len = celt_encode(encoder, resampled ? psOut : psMic, NULL, encbuf, MIN(_settings.quality / 800, 127));
        _bufferedFrames++;
        bitrate = len * 100 * 8;
    } else if (_settings.codec == MKCodecFormatSpeex) {
        int vbr = 0;
        speex_encoder_ctl(_speexEncoder, SPEEX_GET_VBR_MAX_BITRATE, &vbr);
        if (vbr != _settings.quality) {
            vbr = _settings.quality;
            speex_encoder_ctl(_speexEncoder, SPEEX_SET_VBR_MAX_BITRATE, &vbr);
        }
        if (!_lastTransmit)
            speex_encoder_ctl(_speexEncoder, SPEEX_RESET_STATE, NULL);
        speex_encode_int(_speexEncoder, psOut, &_speexBits);
        len = speex_bits_write(&_speexBits, (char *)encbuf, 127);
        speex_bits_reset(&_speexBits);
        _bufferedFrames++;
        bitrate = len * 50 * 8;
        udpMessageType = UDPVoiceSpeexMessage;
    }
    
    return encoded ? len : -1;
}

- (void) processAndEncodeAudioFrame {
    frameCounter++;

    if (doResetPreprocessor) {
        [self resetPreprocessor];
        doResetPreprocessor = NO;
    }

    int isSpeech = 0;
    if (_settings.enablePreprocessor) {
        isSpeech = speex_preprocess_run(_preprocessorState, psMic);
    } else {
        BOOL resampled = micFrequency != sampleRate;
        short *buf = resampled ? psOut : psMic;
        int i;
        for (i = 0; i < micLength; i++) {
            float val = (buf[i] / 32767.0f) * (1.0f + _settings.micBoost);
            if (val > 1.0f)
                val = 1.0f;
            buf[i] = val * 32767.0f;
        }
    }

    
    float sum = 1.0f;
    int i;
    for (i = 0; i < frameSize; i++) {
        sum += psMic[i] * psMic[i];
    }
    float micLevel = sqrtf(sum / frameSize);
    float peakSignal = 20.0f*log10f(micLevel/32768.0f);
    if (-96.0f > peakSignal)
        peakSignal = -96.0f;
    
    spx_int32_t prob = 0;
    speex_preprocess_ctl(_preprocessorState, SPEEX_PREPROCESS_GET_PROB, &prob);
    _speechProbability = prob / 100.0f;
    
    int arg;
    speex_preprocess_ctl(_preprocessorState, SPEEX_PREPROCESS_GET_AGC_GAIN, &arg);
    _peakCleanMic = peakSignal - (float)arg;
    if (-96.0f > _peakCleanMic) {
        _peakCleanMic = -96.0f;
    }
    
    if (_settings.transmitType == MKTransmitTypeVAD) {
        float level = _speechProbability;
        if (!_settings.enablePreprocessor || _settings.vadKind == MKVADKindAmplitude) {
            level = ((_peakCleanMic)/96.0f) + 1.0;
        }
        _doTransmit = NO;
        if (_settings.vadMax == 0 && _settings.vadMin == 0) {
            _doTransmit = NO;
        } else if (level > _settings.vadMax) {
            _doTransmit = YES;
        } else if (level > _settings.vadMin && _lastTransmit) {
            _doTransmit = YES;
        }
    } else if (_settings.transmitType == MKTransmitTypeContinuous) {
        _doTransmit = YES;
    } else if (_settings.transmitType == MKTransmitTypeToggle) {
        _doTransmit = _forceTransmit;
    }

    if (_selfMuted)
        _doTransmit = NO;
    if (_suppressed)
        _doTransmit = NO;
    if (_muted)
        _doTransmit = NO;
    
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
     
     if (!_lastTransmit && !_doTransmit) {
         return;
     }
    
    unsigned char buffer[500];
    int len = [self encodeAudioFrameOfSpeech:_doTransmit intoBuffer:&buffer[0] ofSize:500];
    if (len >= 0) {
        NSData *outputBuffer = [[NSData alloc] initWithBytes:buffer length:len];
        [self flushCheck:outputBuffer terminator:!_doTransmit];
        [outputBuffer release];
    }
    _lastTransmit = _doTransmit;
}

// Flush check.
// Queue up frames, and send them to the server when enough frames have been
// queued up.
- (void) flushCheck:(NSData *)codedSpeech terminator:(BOOL)terminator {
    [frameList addObject:codedSpeech];
    
    if (! terminator && _bufferedFrames < _settings.audioPerPacket) {
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
    
    int frames = _bufferedFrames;
    _bufferedFrames = 0;
    
    MKPacketDataStream *pds = [[MKPacketDataStream alloc] initWithBuffer:(data+1) length:1023];
    [pds addVarint:(frameCounter - frames)];

    if (udpMessageType == UDPVoiceOpusMessage) {
       NSData *frame = [frameList objectAtIndex:0]; 
        uint64_t header = [frame length];
        if (terminator)
            header |= (1 << 13); // Opus terminator flag
        [pds addVarint:header];
        [pds appendBytes:(unsigned char *)[frame bytes] length:[frame length]];
    } else {
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
    }
    
    [frameList removeAllObjects];

    NSUInteger len = [pds size] + 1;
    NSData *msgData = [[NSData alloc] initWithBytes:data length:len];
    [pds release];
    
    // fixme(mkrautz): Fix locking...
    MKConnectionController *conns = [MKConnectionController sharedController];
    NSArray *connections = [conns allConnections];
    for (NSValue *val in connections) {
        MKConnection *conn = [val pointerValue];
        [conn sendVoiceData:msgData];
    }

    [msgData release];
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

- (float) speechProbability {
    return _speechProbability;
}

- (float) peakCleanMic {
    return _peakCleanMic;
}

- (void) setSelfMuted:(BOOL)selfMuted {
    _selfMuted = selfMuted;
}

- (void) setSuppressed:(BOOL)suppressed {
    _suppressed = suppressed;
}

- (void) setMuted:(BOOL)muted {
    _muted = muted;
}

@end
