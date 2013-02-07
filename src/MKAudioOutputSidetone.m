// Copyright 2005-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKAudio.h>
#import "MKAudioOutputUser.h"
#import "MKAudioOutputUserPrivate.h"
#import "MKAudioOutputSidetone.h"

@interface MKAudioOutputSidetone () {
    NSMutableArray        *_frames;
    NSUInteger            _offset;
    NSUInteger            _filled;
    float                 _volume;
    MKAudioSettings       _settings;
}
@end

@implementation MKAudioOutputSidetone

- (id) initWithSettings:(MKAudioSettings *)settings {
    if ((self = [super init])) {
        memcpy(&_settings, settings, sizeof(MKAudioSettings));
        _frames = [[NSMutableArray alloc] init];
        _filled = 0;
        _offset = 0;
        _volume = _settings.sidetoneVolume;
    }
    return self;
}

- (void) dealloc {
    [_frames release];
    [super dealloc];
}

- (void) addFrame:(NSData *)data {
    @synchronized(_frames) {
        [_frames addObject:data];
    }
}

- (BOOL) needSamples:(NSUInteger)nsamples {    
    [self resizeBuffer:nsamples];

    while (_filled < nsamples) { 
        NSData *frameData = nil;
        @synchronized(_frames) {
            if ([_frames count] > 0) {
                frameData = [_frames objectAtIndex:0];
            }
        }
        if (frameData != nil) {
            NSUInteger frameSize = [frameData length]/2;
            short *input = (short *) [frameData bytes];
            float *output = _buffer+_filled;
            
            NSUInteger maxFrames = frameSize;
            if (_filled+frameSize > nsamples) {
                maxFrames = nsamples - _filled;
            }
            if (_offset > 0) {
                for (NSUInteger i = _offset; i < maxFrames; i++) {
                    output[0] = (input[i] / 32767.0f) * _volume;
                    _filled++;
                    output++;
                }
                _offset = 0;
            } else {
                for (NSUInteger i = 0; i < maxFrames; i++) {
                    output[i] = (input[i] / 32767.0f) * _volume;
                }
                _filled += maxFrames;
            }
            
            if (maxFrames < frameSize) {
                _offset = maxFrames;
            } else {
                @synchronized(_frames) {
                    [_frames removeObjectAtIndex:0];
                }
            }
        } else {
            return NO;
        }
    }
    
    for (NSUInteger i = 0; i < nsamples; i++) {
        if (_buffer[i] > 1.0f)
            _buffer[i] = 1.0f;
        else if (_buffer[i] < -1.0f)
            _buffer[i] = -1.0f;
    }
    
    _filled = 0;
    return YES;
}


@end
