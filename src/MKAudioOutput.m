// Copyright 2005-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MKUtils.h"
#import "MKAudioOutput.h"
#import "MKAudioOutputSpeech.h"
#import "MKAudioOutputUser.h"
#import "MKAudioDevice.h"

#import <AudioUnit/AudioUnit.h>
#import <AudioUnit/AUComponent.h>
#import <AudioToolbox/AudioToolbox.h>

@interface MKAudioOutput () {
    MKAudioDevice        *_device;
    MKAudioSettings       _settings;
    AudioUnit             _audioUnit;
    int                   _sampleSize;
    int                   _frameSize;
    int                   _mixerFrequency;
    int                   _numChannels;
    float                *_speakerVolume;
    NSLock               *_outputLock;
    NSMutableDictionary  *_outputs;

	//atuzzi comfort noise generator
	double				_cngAmpliScaler;
	double				_cngLastSample;
	long				_cngRegister1;
	long				_cngRegister2;
	BOOL				_cngEnabled;
	//atuzzi comfort noise generator end
}
@end

@implementation MKAudioOutput

- (id) initWithDevice:(MKAudioDevice *)device andSettings:(MKAudioSettings *)settings {
    if ((self = [super init])) {
        memcpy(&_settings, settings, sizeof(MKAudioSettings));
        _device = [device retain];
        _sampleSize = 0;
        _frameSize = SAMPLE_RATE / 100;
        _mixerFrequency = 0;
        _outputLock = [[NSLock alloc] init];
        _outputs = [[NSMutableDictionary alloc] init];
        
        _mixerFrequency = [_device inputSampleRate];
        _numChannels = [_device numberOfInputChannels];
        _sampleSize = _numChannels * sizeof(short);
        
		//atuzzi comfort noise generator init
		_cngRegister1 = 0x67452301;
		_cngRegister2 = 0xefcdab89;
		_cngEnabled = settings->enableComfortNoise;
		_cngAmpliScaler = 2.0f / 0xffffffff;
		_cngAmpliScaler *= 0.00150;
		_cngAmpliScaler *= settings->comfortNoiseLevel;
		_cngLastSample = 0.0;
		//atuzzi comfort noise generator init end
		
       if (_speakerVolume) {
            free(_speakerVolume);
        }
        _speakerVolume = malloc(sizeof(float)*_numChannels);
        
        int i;
        for (i = 0; i < _numChannels; ++i) {
            _speakerVolume[i] = 1.0f;
        }
        
        [_device setupOutput:^BOOL(short *frames, unsigned int nsamp) {
            return [self mixFrames:frames amount:nsamp];
        }];
    }
    return self;
}

- (void) dealloc {
    [_device setupOutput:NULL];
    [_device release];
    [_outputLock release];
    [_outputs release];
    [super dealloc];
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
    
    if (_settings.enableSideTone) {
        MKAudioOutputSidetone *sidetone = [[MKAudio sharedAudio] sidetoneOutput];
        if ([sidetone needSamples:nsamp]) {
            [mix addObject:[[MKAudio sharedAudio] sidetoneOutput]];
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

	//atuzzi comfort noise generator if samples are all at ZERO
	if(!retVal && _cngEnabled)
	{
		short *outputBuffer = (short *)frames;
		for (i = 0; i < nsamp * _numChannels; ++i)
		{
			float	runningvalue;
			
			_cngRegister1 ^= _cngRegister2;
			runningvalue = (float)_cngRegister2 * _cngAmpliScaler;
			runningvalue += _cngLastSample; //one pole smoother
			runningvalue *= 0.5;			//one pole smoother
			_cngLastSample = runningvalue;
			_cngRegister2 += _cngRegister1;
			
			if (runningvalue > 1.0f) {
				outputBuffer[i] = 32768;
			} else if (runningvalue < -1.0f) {
				outputBuffer[i] = -32768;
			} else {
				outputBuffer[i] = runningvalue * 32768.0f;
			}
		}
		retVal = YES;
	}
	//atuzzi comfort noise generator END

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
