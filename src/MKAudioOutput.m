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

#import "MKUtils.h"
#import "MKAudioOutput.h"
#import "MKAudioOutputSpeech.h"
#import "MKAudioOutputUser.h"
#import "MKReadWriteLock.h"

#import <AudioUnit/AudioUnit.h>
#import <AudioUnit/AUComponent.h>
#import <AudioToolbox/AudioToolbox.h>

/*
 * Output callback.
 */
static OSStatus outputCallback(void *udata, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts,
                               UInt32 busnum, UInt32 nframes, AudioBufferList *buflist) {
    MKAudioOutput *ao = (MKAudioOutput *) udata;
    AudioBuffer *buf = buflist->mBuffers;
    MK_UNUSED OSStatus err;
    BOOL done;

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    done = [ao mixFrames:buf->mData amount:nframes];
    if (! done) {
        /*
         * Not very obvious from the documentation, but CoreAudio simply wants you to set your buffer
         * size to 0, and return a non-zero value when you don't have anything to feed it. It will call
         * you back later.
         */
        buf->mDataByteSize = 0;
        [pool release];
        return -1;
    }

    [pool release];
    return noErr;
}

@interface MKAudioOutput () {
    MKAudioSettings _settings;
    
    AudioUnit audioUnit;
    int sampleSize;
    int frameSize;
    int mixerFrequency;
    int numChannels;
    float *speakerVolume;
    
    MKReadWriteLock *outputLock;
    NSMutableDictionary *outputs;
}
@end

@implementation MKAudioOutput

- (id) initWithSettings:(MKAudioSettings *)settings {
    self = [super init];
    if (self == nil)
        return nil;

    // Copy settings
    memcpy(&_settings, settings, sizeof(MKAudioSettings));

    sampleSize = 0;
    frameSize = SAMPLE_RATE / 100;
    mixerFrequency = 0;

    outputLock = [[MKReadWriteLock alloc] init];
    outputs = [[NSMutableDictionary alloc] init];

    return self;
}

- (void) dealloc {
    // fixme(mkrautz): Return value?
    [self teardownDevice];

    [outputLock release];
    [outputs release];

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

    err = AudioComponentInstanceNew(comp, (AudioComponentInstance *) &audioUnit);
    if (err != noErr) {
        NSLog(@"MKAudioOutput: Unable to instantiate new AudioUnit.");
        return NO;
    }

    err = AudioUnitInitialize(audioUnit);
    if (err != noErr) {
        NSLog(@"MKAudioOutput: Unable to initialize AudioUnit.");
        return NO;
    }

    len = sizeof(AudioStreamBasicDescription);
    err = AudioUnitGetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &fmt, &len);
    if (err != noErr) {
        NSLog(@"MKAudioOuptut: Unable to get output stream format from AudioUnit.");
        return NO;
    }

    mixerFrequency = (int) 48000;
    numChannels = (int) fmt.mChannelsPerFrame;
    sampleSize = numChannels * sizeof(short);

    if (speakerVolume) {
        free(speakerVolume);
    }
    speakerVolume = malloc(sizeof(float)*numChannels);

    int i;
    for (i = 0; i < numChannels; ++i) {
        speakerVolume[i] = 1.0f;
    }

    fmt.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    fmt.mBitsPerChannel = sizeof(short) * 8;

    NSLog(@"MKAudioOutput: Output device currently configured as %iHz sample rate, %i channels, %i sample size", mixerFrequency, numChannels, sampleSize);

    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mSampleRate = mixerFrequency;
    fmt.mBytesPerFrame = sampleSize;
    fmt.mBytesPerPacket = sampleSize;
    fmt.mFramesPerPacket = 1;

    len = sizeof(AudioStreamBasicDescription);
    err = AudioUnitSetProperty(audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, len);
    if (err != noErr) {
        NSLog(@"MKAudioOutput: Unable to set stream format for output device.");
        return NO;
    }

    AURenderCallbackStruct cb;
    cb.inputProc = outputCallback;
    cb.inputProcRefCon = self;
    len = sizeof(AURenderCallbackStruct);
    err = AudioUnitSetProperty(audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &cb, len);
    if (err != noErr) {
        NSLog(@"MKAudioOutput: Could not set render callback.");
        return NO;
    }

    /* On desktop we call AudioDeviceSetProperty() with kAudioDevicePropertyBufferFrameSize to set our frame size up. */

    err = AudioOutputUnitStart(audioUnit);
    if (err != noErr) {
        NSLog(@"MKAudioOutput: Unable to start AudioUnit");
        return NO;
    }

    return YES;
}

- (BOOL) teardownDevice {
    OSStatus err = AudioOutputUnitStop(audioUnit);
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

    /*
     * The real mixer:
     */
    NSMutableArray *mix = [[NSMutableArray alloc] init];
    NSMutableArray *del = [[NSMutableArray alloc] init];
    unsigned int nchan = numChannels;

    /* if volume is too low, skip. */

    [outputLock readLock];
    for (NSNumber *sessionKey in outputs) {
        MKAudioOutputUser *ou = [outputs objectForKey:sessionKey];
        if (! [ou needSamples:nsamp]) {
            [del addObject:ou];
        } else {
            [mix addObject:ou];
        }
    }

    float *mixBuffer = alloca(sizeof(float)*numChannels*nsamp);
    memset(mixBuffer, 0, sizeof(float)*numChannels*nsamp);

    if ([mix count] > 0) {
        for (MKAudioOutputUser *ou in mix) {
            const float * restrict userBuffer = [ou buffer];
            for (s = 0; s < nchan; ++s) {
                const float str = speakerVolume[s];
                float * restrict o = (float *)mixBuffer + s;
                for (i = 0; i < nsamp; ++i) {
                    o[i*nchan] += userBuffer[i] * str;
                }
            }
        }

        short *outputBuffer = (short *)frames;
        for (i = 0; i < nsamp * numChannels; ++i) {
            if (mixBuffer[i] > 1.0f) {
                outputBuffer[i] = 32768;
            } else if (mixBuffer[i] < -1.0f) {
                outputBuffer[i] = -32768;
            } else {
                outputBuffer[i] = mixBuffer[i] * 32768.0f;
            }
        }
    } else {
        memset((short *)frames, 0, nsamp * numChannels);
    }

    [outputLock unlock];

    for (MKAudioOutputUser *ou in del) {
        [self removeBuffer:ou];
    }

    retVal = [mix count] > 0;

    [mix release];
    [del release];

    return retVal;
}

- (void) removeBuffer:(MKAudioOutputUser *)u {
    // hack(mkrautz): output sources should be a subclass, but should implement a protocol instead.
    if ([u respondsToSelector:@selector(userSession)]) {
        [outputLock writeLock];
        [outputs removeObjectForKey:[NSNumber numberWithUnsignedInt:[(id)u userSession]]];
        [outputLock unlock];
    }
}

- (void) addFrameToBufferWithSession:(NSUInteger)session data:(NSData *)data sequence:(NSUInteger)seq type:(MKUDPMessageType)msgType {
    if (numChannels == 0)
        return;

    [outputLock readLock];
    MKAudioOutputSpeech *outputUser = [outputs objectForKey:[NSNumber numberWithUnsignedInt:session]];
    [outputLock unlock];

    if (outputUser == nil || [outputUser messageType] != msgType) {
        if (outputUser != nil) {
            [self removeBuffer:outputUser];
        }
        outputUser = [[MKAudioOutputSpeech alloc] initWithSession:session sampleRate:mixerFrequency messageType:msgType];
        [outputLock writeLock];
        [outputs setObject:outputUser forKey:[NSNumber numberWithUnsignedInt:session]];
        [outputLock unlock];
        [outputUser release];
    }

    [outputUser addFrame:data forSequence:seq];
}

@end
