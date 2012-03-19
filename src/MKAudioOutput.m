// Copyright 2005-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MKUtils.h"
#import "MKAudioOutput.h"
#import "MKAudioOutputSpeech.h"
#import "MKAudioOutputUser.h"

#import <AudioUnit/AudioUnit.h>
#import <AudioUnit/AUComponent.h>
#import <AudioToolbox/AudioToolbox.h>

static OSStatus outputCallback(void *udata, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts,
                               UInt32 busnum, UInt32 nframes, AudioBufferList *buflist) {
    MKAudioOutput *ao = (MKAudioOutput *) udata;
    AudioBuffer *buf = buflist->mBuffers;
    MK_UNUSED OSStatus err;
    BOOL done;

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    done = [ao mixFrames:buf->mData amount:nframes];
    if (! done) {
         // Not very obvious from the documentation, but CoreAudio simply wants you to set your buffer
         // size to 0, and return a non-zero value when you don't have anything to feed it. It will call
         // you back later.
        buf->mDataByteSize = 0;
        [pool release];
        return -1;
    }

    [pool release];
    return noErr;
}

@interface MKAudioOutput () {
    MKAudioSettings       _settings;
    AudioUnit             _audioUnit;
    int                   _sampleSize;
    int                   _frameSize;
    int                   _mixerFrequency;
    int                   _numChannels;
    float                *_speakerVolume;
    NSLock               *_outputLock;
    NSMutableDictionary  *_outputs;
}
@end

@implementation MKAudioOutput

- (id) initWithSettings:(MKAudioSettings *)settings {
    if ((self = [super init])) {
        memcpy(&_settings, settings, sizeof(MKAudioSettings));
        _sampleSize = 0;
        _frameSize = SAMPLE_RATE / 100;
        _mixerFrequency = 0;
        _outputLock = [[NSLock alloc] init];
        _outputs = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void) dealloc {
    [self teardownDevice];
    [_outputLock release];
    [_outputs release];
    [super dealloc];
}

- (BOOL) setupDevice {
    UInt32 len;
    OSStatus err;
    AudioComponent comp;
    AudioComponentDescription desc;
    AudioStreamBasicDescription fmt;

    desc.componentType = kAudioUnitType_Output;
#if TARGET_OS_IPHONE == 1
    desc.componentSubType = kAudioUnitSubType_RemoteIO;
#elif TARGET_OS_MAC == 1
    desc.componentSubType = kAudioUnitSubType_HALOutput;
#endif
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;

    comp = AudioComponentFindNext(NULL, &desc);
    if (! comp) {
        NSLog(@"MKAudioOutput: Unable to find AudioUnit.");
        return NO;
    }

    err = AudioComponentInstanceNew(comp, (AudioComponentInstance *) &_audioUnit);
    if (err != noErr) {
        NSLog(@"MKAudioOutput: Unable to instantiate new AudioUnit.");
        return NO;
    }

    err = AudioUnitInitialize(_audioUnit);
    if (err != noErr) {
        NSLog(@"MKAudioOutput: Unable to initialize AudioUnit.");
        return NO;
    }

    len = sizeof(AudioStreamBasicDescription);
    err = AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &fmt, &len);
    if (err != noErr) {
        NSLog(@"MKAudioOuptut: Unable to get output stream format from AudioUnit.");
        return NO;
    }

    _mixerFrequency = (int) 48000;
    _numChannels = (int) fmt.mChannelsPerFrame;
    _sampleSize = _numChannels * sizeof(short);

    if (_speakerVolume) {
        free(_speakerVolume);
    }
    _speakerVolume = malloc(sizeof(float)*_numChannels);

    int i;
    for (i = 0; i < _numChannels; ++i) {
        _speakerVolume[i] = 1.0f;
    }

    fmt.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    fmt.mBitsPerChannel = sizeof(short) * 8;

    NSLog(@"MKAudioOutput: Output device currently configured as %iHz sample rate, %i channels, %i sample size", _mixerFrequency, _numChannels, _sampleSize);

    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mSampleRate = _mixerFrequency;
    fmt.mBytesPerFrame = _sampleSize;
    fmt.mBytesPerPacket = _sampleSize;
    fmt.mFramesPerPacket = 1;

    len = sizeof(AudioStreamBasicDescription);
    err = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, len);
    if (err != noErr) {
        NSLog(@"MKAudioOutput: Unable to set stream format for output device.");
        return NO;
    }

    AURenderCallbackStruct cb;
    cb.inputProc = outputCallback;
    cb.inputProcRefCon = self;
    len = sizeof(AURenderCallbackStruct);
    err = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &cb, len);
    if (err != noErr) {
        NSLog(@"MKAudioOutput: Could not set render callback.");
        return NO;
    }

    // On desktop we call AudioDeviceSetProperty() with kAudioDevicePropertyBufferFrameSize
    // to setup our frame size.

    err = AudioOutputUnitStart(_audioUnit);
    if (err != noErr) {
        NSLog(@"MKAudioOutput: Unable to start AudioUnit");
        return NO;
    }

    return YES;
}

- (BOOL) teardownDevice {
    OSStatus err = AudioOutputUnitStop(_audioUnit);
    if (err != noErr) {
        NSLog(@"MKAudioOutput: Unable to stop AudioUnit.");
        return NO;
    }

    NSLog(@"MKAudioOuptut: Teardown finished.");
    return YES;
}

- (BOOL) mixFrames:(void *)frames amount:(unsigned int)nsamp {
    unsigned int i, s;
    BOOL retVal = NO;

    NSMutableArray *mix = [[NSMutableArray alloc] init];
    NSMutableArray *del = [[NSMutableArray alloc] init];
    unsigned int nchan = _numChannels;

    [_outputLock lock];
    for (NSNumber *sessionKey in _outputs) {
        MKAudioOutputUser *ou = [_outputs objectForKey:sessionKey];
        if (! [ou needSamples:nsamp]) {
            [del addObject:ou];
        } else {
            [mix addObject:ou];
        }
    }

    float *mixBuffer = alloca(sizeof(float)*_numChannels*nsamp);
    memset(mixBuffer, 0, sizeof(float)*_numChannels*nsamp);

    if ([mix count] > 0) {
        for (MKAudioOutputUser *ou in mix) {
            const float * restrict userBuffer = [ou buffer];
            for (s = 0; s < nchan; ++s) {
                const float str = _speakerVolume[s];
                float * restrict o = (float *)mixBuffer + s;
                for (i = 0; i < nsamp; ++i) {
                    o[i*nchan] += userBuffer[i] * str;
                }
            }
        }

        short *outputBuffer = (short *)frames;
        for (i = 0; i < nsamp * _numChannels; ++i) {
            if (mixBuffer[i] > 1.0f) {
                outputBuffer[i] = 32768;
            } else if (mixBuffer[i] < -1.0f) {
                outputBuffer[i] = -32768;
            } else {
                outputBuffer[i] = mixBuffer[i] * 32768.0f;
            }
        }
    } else {
        memset((short *)frames, 0, nsamp * _numChannels);
    }
    [_outputLock unlock];

    for (MKAudioOutputUser *ou in del) {
        [self removeBuffer:ou];
    }

    retVal = [mix count] > 0;

    [mix release];
    [del release];

    return retVal;
}

- (void) removeBuffer:(MKAudioOutputUser *)u {
    if ([u respondsToSelector:@selector(userSession)]) {
        [_outputLock lock];
        [_outputs removeObjectForKey:[NSNumber numberWithUnsignedInt:[(id)u userSession]]];
        [_outputLock unlock];
    }
}

- (void) addFrameToBufferWithSession:(NSUInteger)session data:(NSData *)data sequence:(NSUInteger)seq type:(MKUDPMessageType)msgType {
    if (_numChannels == 0)
        return;

    [_outputLock lock];
    MKAudioOutputSpeech *outputUser = [_outputs objectForKey:[NSNumber numberWithUnsignedInt:session]];
    [outputUser retain];
    [_outputLock unlock];

    if (outputUser == nil || [outputUser messageType] != msgType) {
        if (outputUser != nil) {
            [self removeBuffer:outputUser];
            [outputUser release];
        }
        outputUser = [[MKAudioOutputSpeech alloc] initWithSession:session sampleRate:_mixerFrequency messageType:msgType];
        [_outputLock lock];
        [_outputs setObject:outputUser forKey:[NSNumber numberWithUnsignedInt:session]];
        [_outputLock unlock];
    }

    [outputUser addFrame:data forSequence:seq];
    [outputUser release];
}

@end
