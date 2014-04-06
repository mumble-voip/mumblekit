// Copyright 2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MKVoiceProcessingDevice.h"

#import <MumbleKit/MKAudio.h>

#import <AudioUnit/AudioUnit.h>
#import <AudioUnit/AUComponent.h>
#import <AudioToolbox/AudioToolbox.h>
#import <UIKit/UIKit.h>

@interface MKVoiceProcessingDevice () {
@public
    MKAudioSettings              _settings;
    AudioUnit                    _audioUnit;
    AudioBufferList              _buflist;
    int                          _micFrequency;
    int                          _micSampleSize;
    int                          _numMicChannels;
    MKAudioDeviceOutputFunc      _outputFunc;
    MKAudioDeviceInputFunc       _inputFunc;
}
@end

// DeviceIsRunningiOS7OrGreater returns YES if
// the iOS device is on iOS 7 or greater.
static BOOL DeviceIsRunningiOS7OrGreater() {
    BOOL iOS7OrGreater = NO;
    NSString *iOSVersion = [[UIDevice currentDevice] systemVersion];
    if (iOSVersion) {
        NSArray *iOSVersionComponents = [iOSVersion componentsSeparatedByString:@"."];
        if ([iOSVersionComponents count] > 0) {
            NSInteger majorVersion = [[iOSVersionComponents objectAtIndex:0] integerValue];
            iOS7OrGreater = majorVersion >= 7;
        }
    }
    return iOS7OrGreater;
}

static OSStatus inputCallback(void *udata, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts,
                              UInt32 busnum, UInt32 nframes, AudioBufferList *buflist) {
    MKVoiceProcessingDevice *dev = (MKVoiceProcessingDevice *)udata;
    OSStatus err;
        
    if (! dev->_buflist.mBuffers->mData) {
        NSLog(@"MKVoiceProcessingDevice: No buffer allocated.");
        dev->_buflist.mNumberBuffers = 1;
        AudioBuffer *b = dev->_buflist.mBuffers;
        b->mNumberChannels = dev->_numMicChannels;
        b->mDataByteSize = dev->_micSampleSize * nframes;
        b->mData = calloc(1, b->mDataByteSize);
    }
    
    if (dev->_buflist.mBuffers->mDataByteSize < (nframes/dev->_micSampleSize)) {
        NSLog(@"MKVoiceProcessingDevice: Buffer too small. Allocating more space.");
        AudioBuffer *b = dev->_buflist.mBuffers;
        free(b->mData);
        b->mDataByteSize = dev->_micSampleSize * nframes;
        b->mData = calloc(1, b->mDataByteSize);
    }
        
    err = AudioUnitRender(dev->_audioUnit, flags, ts, busnum, nframes, &dev->_buflist);
    if (err != noErr) {
        NSLog(@"MKVoiceProcessingDevice: AudioUnitRender failed. err = %li", (long int)err);
        return err;
    }
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    short *buf = (short *) dev->_buflist.mBuffers->mData;
    MKAudioDeviceInputFunc inputFunc = dev->_inputFunc;
    if (inputFunc) {
        inputFunc(buf, nframes);
    }
    [pool release];
    
    return noErr;
}

static OSStatus outputCallback(void *udata, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts,
                               UInt32 busnum, UInt32 nframes, AudioBufferList *buflist) {
    MKVoiceProcessingDevice *dev = (MKVoiceProcessingDevice *) udata;
    AudioBuffer *buf = buflist->mBuffers;
    MKAudioDeviceOutputFunc outputFunc = dev->_outputFunc;
    BOOL done;
    
    if (outputFunc == NULL) {
        // No frames available yet.
        buf->mDataByteSize = 0;
        return -1;
    }
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    done = outputFunc(buf->mData, nframes);
    if (! done) {
        // No frames available yet.
        buf->mDataByteSize = 0;
        [pool release];
        return -1;
    }
        
    [pool release];
    return noErr;
}

@implementation MKVoiceProcessingDevice

- (id) initWithSettings:(MKAudioSettings *)settings {
    if ((self = [super init])) {
        memcpy(&_settings, settings, sizeof(MKAudioSettings));
    }
    return self;
}

- (void) dealloc {
    [_inputFunc release];
    [_outputFunc release];
    [super dealloc];
}

- (BOOL) setupDevice {
    UInt32 len;
    UInt32 val;
    OSStatus err;
    AudioComponent comp;
    AudioComponentDescription desc;
    AudioStreamBasicDescription fmt;
    
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    
    comp = AudioComponentFindNext(NULL, &desc);
    if (! comp) {
        NSLog(@"MKVoiceProcessingDevice: Unable to find AudioUnit.");
        return NO;
    }
    
    err = AudioComponentInstanceNew(comp, (AudioComponentInstance *) &_audioUnit);
    if (err != noErr) {
        NSLog(@"MKVoiceProcessingDevice: Unable to instantiate new AudioUnit.");
        return NO;
    }
    
    val = 1;
    err = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &val, sizeof(UInt32));
    if (err != noErr) {
        NSLog(@"MKVoiceProcessingDevice: Unable to configure input scope on AudioUnit.");
        return NO;
    }
    
    val = 1;
    err = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &val, sizeof(UInt32));
    if (err != noErr) {
        NSLog(@"MKVoiceProcessingDevice: Unable to configure output scope on AudioUnit.");
        return NO;
    }
    
    AURenderCallbackStruct cb;
    cb.inputProc = inputCallback;
    cb.inputProcRefCon = self;
    len = sizeof(AURenderCallbackStruct);
    err = AudioUnitSetProperty(_audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &cb, len);
    if (err != noErr) {
        NSLog(@"MKVoiceProcessingDevice: Unable to setup callback.");
        return NO;
    }
    
    cb.inputProc = outputCallback;
    cb.inputProcRefCon = self;
    len = sizeof(AURenderCallbackStruct);
    err = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Global, 0, &cb, len);
    if (err != noErr) {
        NSLog(@"MKVoiceProcessingDevice: Could not set render callback.");
        return NO;
    }
    
    len = sizeof(AudioStreamBasicDescription);
    err = AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &fmt, &len);
    if (err != noErr) {
        NSLog(@"MKVoiceProcessingDevice: Unable to query device for stream info.");
        return NO;
    }
    
    if (fmt.mChannelsPerFrame > 1) {
        NSLog(@"MKVoiceProcessingDevice: Input device with more than one channel detected. Defaulting to 1.");
    }
    
    _micFrequency = 48000;
    _numMicChannels = 1;
    _micSampleSize = _numMicChannels * sizeof(short);
    
    fmt.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    fmt.mBitsPerChannel = sizeof(short) * 8;
    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mSampleRate = _micFrequency;
    fmt.mChannelsPerFrame = _numMicChannels;
    fmt.mBytesPerFrame = _micSampleSize;
    fmt.mBytesPerPacket = _micSampleSize;
    fmt.mFramesPerPacket = 1;
    
    len = sizeof(AudioStreamBasicDescription);
    err = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &fmt, len);
    if (err != noErr) {
        NSLog(@"MKVoiceProcessingDevice: Unable to set stream format for output device. (output scope)");
        return NO;
    }
    
    len = sizeof(AudioStreamBasicDescription);
    err = AudioUnitSetProperty(_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &fmt, len);
    if (err != noErr) {
        NSLog(@"MKVoiceProcessingDevice: Unable to set stream format for input device. (input scope)");
        return NO;
    }
    
    val = 0;
    len = sizeof(UInt32);
    err = AudioUnitSetProperty(_audioUnit, kAUVoiceIOProperty_BypassVoiceProcessing, kAudioUnitScope_Global, 0, &val, len);
    if (err != noErr) {
        NSLog(@"MKVoiceProcessingDevice: Unable to disable VPIO voice processing.");
        return NO;
    }
        
    val = 0;
    len = sizeof(UInt32);
    err = AudioUnitSetProperty(_audioUnit, kAUVoiceIOProperty_VoiceProcessingEnableAGC, kAudioUnitScope_Global, 0, &val, len);
    if (err != noErr) {
        NSLog(@"MKVoiceProcessingDevice: Unable to disable VPIO AGC.");
        return NO;
    }

    // When running Mumble built with the iOS 6.1 SDK, built using Xcode 4.6.3 on iOS 7,
    // we sometimes get zero samples from the VPIO Audio Unit.  When building with Xcode 5
    // against the iOS 7 SDK, everything is OK, though.
    //
    // This is somehow related to setting VoiceProcessingQuality in the 'low' range. If we don't set
    // it at all (and thus presumably stay in the 'high quality' range) iOS 7 doesn't complain. So do
    // that as a workaround for now.
#if __IPHONE_OS_VERSION_MAX_ALLOWED <= 60100
    if (!DeviceIsRunningiOS7OrGreater()) {
#else
    {
#endif
        // It's sufficient to set the quality to 0 for our use case; we do our own preprocessing
        // after this, and the job of the VPIO is only to do echo cancellation.
        val = 0;
        len = sizeof(UInt32);
        err = AudioUnitSetProperty(_audioUnit, kAUVoiceIOProperty_VoiceProcessingQuality, kAudioUnitScope_Global, 0, &val, len);
        if (err != noErr) {
            NSLog(@"MKVoiceProcessingDevice: unable to set VPIO quality.");
            return NO;
        }
    }
    
    val = 0;
    len = sizeof(UInt32);
    err = AudioUnitSetProperty(_audioUnit, kAUVoiceIOProperty_MuteOutput, kAudioUnitScope_Global, 0, &val, len);
    if (err != noErr) {
        NSLog(@"MKVoiceProcessingDevice: unable to unmute output.");
        return NO;
    }
    
    err = AudioUnitInitialize(_audioUnit);
    if (err != noErr) {
        NSLog(@"MKVoiceProcessingDevice: Unable to initialize AudioUnit.");
        return NO;
    }
    
    err = AudioOutputUnitStart(_audioUnit);
    if (err != noErr) {
        NSLog(@"MKVoiceProcessingDevice: Unable to start AudioUnit.");
        return NO;
    }
    
    return YES;
}

- (BOOL) teardownDevice {
    OSStatus err;
    
    err = AudioOutputUnitStop(_audioUnit);
    if (err != noErr) {
        NSLog(@"MKVoiceProcessingDevice: unable to stop AudioUnit.");
        return NO;
    }
    
    err = AudioComponentInstanceDispose(_audioUnit);
    if (err != noErr) {
        NSLog(@"MKVoiceProcessingDevice: unable to dispose of AudioUnit.");
        return NO;
    }
    
    AudioBuffer *b = _buflist.mBuffers;
    if (b && b->mData)
        free(b->mData);
    
    NSLog(@"MKVoiceProcessingDevice: teardown finished.");
    return YES;
}

- (void) setupOutput:(MKAudioDeviceOutputFunc)outf {
    _outputFunc = [outf copy];
}

- (void) setupInput:(MKAudioDeviceInputFunc)inf {
    _inputFunc = [inf copy];
}

- (int) inputSampleRate {
    return _micFrequency;
}

- (int) outputSampleRate {
    return _micFrequency;
}

- (int) numberOfInputChannels {
    return _numMicChannels;
}

- (int) numberOfOutputChannels {
    return _numMicChannels;
}

@end
