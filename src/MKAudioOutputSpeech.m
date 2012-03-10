/* Copyright (C) 2009-2012 Mikkel Krautz <mikkel@krautz.dk>
   Copyright (C) 2005-2010 Thorvald Natvig <thorvald@natvig.com>
   Copyright (C) 2011, Benjamin Jemlich <pcgod@users.sourceforge.net>

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

#import <MumbleKit/MKVersion.h>
#import "MKPacketDataStream.h"
#import "MKAudioOutputSpeech.h"
#import "MKAudioOutputUserPrivate.h"

#include <pthread.h>

#include <speex/speex.h>
#include <speex/speex_preprocess.h>
#include <speex/speex_echo.h>
#include <speex/speex_resampler.h>
#include <speex/speex_jitter.h>
#include <speex/speex_types.h>
#include <celt.h>
#include <opus.h>

struct MKAudioOutputSpeechPrivate {
    JitterBuffer *jitter;
    CELTMode *celtMode;
    CELTDecoder *celtDecoder;
    SpeexBits speexBits;
    void *speexDecoder;
    SpeexResamplerState *resampler;
};

@interface MKAudioOutputSpeech () {
    struct MKAudioOutputSpeechPrivate *_private;

    OpusDecoder *_opusDecoder;
    
    MKUDPMessageType _msgType;
    NSUInteger bufferOffset;
    NSUInteger bufferFilled;
    NSUInteger outputSize;
    NSUInteger lastConsume;
    NSUInteger frameSize;
    BOOL lastAlive;
    BOOL hasTerminator;

    BOOL       _useStereo;
    NSInteger  _audioBufferSize;
    float      *_resamplerBuffer;
    NSUInteger _sampleRate;
    NSUInteger _freq;
    
    float *fadeIn;
    float *fadeOut;
    
    NSInteger missCount;
    NSInteger missedFrames;
    
    NSMutableArray *frames;
    unsigned char flags;
    
    NSUInteger _userSession;
    float powerMin, powerMax;
    float averageAvailable;
    
    MKTalkState _talkState;
    
    pthread_mutex_t jitterMutex;
}
@end

@implementation MKAudioOutputSpeech

- (id) initWithSession:(NSUInteger)session sampleRate:(NSUInteger)freq messageType:(MKUDPMessageType)type {
    self = [super init];
    if (self == nil)
        return nil;

    _private = malloc(sizeof(struct MKAudioOutputSpeechPrivate));
    _private->jitter = NULL;
    _private->celtMode = NULL;
    _private->celtDecoder = NULL;
    _private->speexDecoder = NULL;
    _private->resampler = NULL;

    _useStereo = NO;
    
    _userSession = session;
    _talkState = MKTalkStatePassive;
    _msgType = type;
    _freq = freq;

    if (type == UDPVoiceOpusMessage) {
        _sampleRate = SAMPLE_RATE;
        frameSize = _sampleRate / 100;
        _audioBufferSize = 12 * frameSize;
        _opusDecoder = opus_decoder_create(_sampleRate, _useStereo ? 2 : 1, NULL);
    } else if (type == UDPVoiceSpeexMessage) {
        _sampleRate = 32000;
        speex_bits_init(&_private->speexBits);
        _private->speexDecoder = speex_decoder_init(speex_lib_get_mode(SPEEX_MODEID_UWB));
        int iArg = 1;
        speex_decoder_ctl(_private->speexDecoder, SPEEX_SET_ENH, &iArg);
        speex_decoder_ctl(_private->speexDecoder, SPEEX_GET_FRAME_SIZE, &frameSize);
        speex_decoder_ctl(_private->speexDecoder, SPEEX_GET_SAMPLING_RATE, &_sampleRate);
        _audioBufferSize = frameSize;
    } else {
        _sampleRate = SAMPLE_RATE;
        frameSize = _sampleRate / 100;
        _private->celtMode = celt_mode_create(SAMPLE_RATE, SAMPLE_RATE/100, NULL);
        _private->celtDecoder = celt_decoder_create(_private->celtMode, 1, NULL);
        _audioBufferSize = frameSize;
    }

    outputSize = (int)(ceilf((float)_audioBufferSize * _freq) / (float)_sampleRate);
    if (_useStereo) {
        _audioBufferSize *= 2;
        outputSize *= 2;
    }

    if (_freq != _sampleRate) {
        int err;
        _private->resampler = speex_resampler_init(_useStereo ? 2 : 1, _sampleRate, _freq, 3, &err);
        _resamplerBuffer = malloc(sizeof(float)*_audioBufferSize);
        NSLog(@"AudioOutputSpeech: Resampling from %i Hz to %d Hz", _sampleRate, _freq);
    }    

    bufferOffset = bufferFilled = lastConsume = 0;

    lastAlive = TRUE;

    missCount = 0;
    missedFrames = 0;

    flags = 0xff;

    _private->jitter = jitter_buffer_init(frameSize);
    int margin = /* g.s.iJitterBufferSize */ 10 * frameSize;
    jitter_buffer_ctl(_private->jitter, JITTER_BUFFER_SET_MARGIN, &margin);

    fadeIn = malloc(sizeof(float)*frameSize);
    fadeOut = malloc(sizeof(float)*frameSize);

    float mul = (float)(M_PI / (2.0 * (float)frameSize));
    NSUInteger i;
    for (i = 0; i < frameSize; ++i) {
        fadeIn[i] = fadeOut[frameSize-i-1] = sinf((float)i * mul);
    }

    frames = [[NSMutableArray alloc] init];

    int err = pthread_mutex_init(&jitterMutex, NULL);
    if (err != 0) {
        NSLog(@"AudioOutputSpeech: pthread_mutex_init() failed.");
        return nil;
    }

    return self;
}

- (void) dealloc {
    if (_private->celtDecoder)
        celt_decoder_destroy(_private->celtDecoder);
    if (_private->celtMode)
        celt_mode_destroy(_private->celtMode);
    if (_private->speexDecoder) {
        speex_bits_destroy(&_private->speexBits);
        speex_decoder_destroy(_private->speexDecoder);
    }
    if (_private->resampler)
        speex_resampler_destroy(_private->resampler);
    if (_private->jitter)
        jitter_buffer_destroy(_private->jitter);
    if (_private)
        free(_private);
    if (_opusDecoder)
        opus_decoder_destroy(_opusDecoder);

    if (fadeIn)
        free(fadeIn);
    if (fadeOut)
        free(fadeOut);
    
    if (_resamplerBuffer)
        free(_resamplerBuffer);

    [frames release];

    [super dealloc];
}

- (NSUInteger) userSession {
    return _userSession;
}

- (MKUDPMessageType) messageType {
    return _msgType;
}

- (void) addFrame:(NSData *)data forSequence:(NSUInteger)seq {    
    int err = pthread_mutex_lock(&jitterMutex);
    if (err != 0) {
        NSLog(@"AudioOutputSpeech: pthread_mutex_lock() failed.");
        return;
    }

    if ([data length] < 2) {
        pthread_mutex_unlock(&jitterMutex);
        return;
    }

    MKPacketDataStream *pds = [[MKPacketDataStream alloc] initWithData:data];
    [pds next];

    int samples = 0;
    if (_msgType == UDPVoiceOpusMessage) {
        int size = [pds getInt];
        if (size > 0) {
            NSData *opusFrames = [pds copyDataBlock:size];
            int nframes = opus_packet_get_nb_frames([opusFrames bytes], size);
            samples = nframes * opus_packet_get_samples_per_frame([opusFrames bytes], SAMPLE_RATE);
            [opusFrames release];
        } else {
            // Prevents a jitter buffer warning for terminator packets.
            samples = 1 * frameSize;
        }
    } else {
        unsigned int header = 0;
        do {
            header = (unsigned int)[pds next];
            samples += frameSize;
            [pds skip:(header & 0x7f)];
        } while ((header & 0x80) && [pds valid]);
    }

    if (! [pds valid]) {
        [pds release];
        NSLog(@"addFrame:: Invalid pds.");
        pthread_mutex_unlock(&jitterMutex);
        return;
    }

    JitterBufferPacket jbp;
    jbp.data = (char *)[data bytes];
    jbp.len = [data length];
    jbp.span = samples;
    jbp.timestamp = frameSize * seq;

    jitter_buffer_put(_private->jitter, &jbp);
    [pds release];
    
    err = pthread_mutex_unlock(&jitterMutex);
    if (err != 0) {
        NSLog(@"AudioOutputSpeech: Unable to unlock() jitter mutex.");
        return;
    }
}

- (BOOL) needSamples:(NSUInteger)nsamples {
    NSUInteger i;
    
    for (i = lastConsume; i < bufferFilled; ++i) {
        buffer[i-lastConsume] = buffer[i];
    }
    bufferFilled -= lastConsume;

    lastConsume = nsamples;

    if (bufferFilled >= nsamples) {
        return lastAlive;
    }

    float *output = NULL;
    BOOL nextAlive = lastAlive;
    
    while (bufferFilled < nsamples) {
        int decodedSamples = frameSize;
        [self resizeBuffer:(bufferFilled + outputSize)];

        if (_private->resampler) {
            output = _resamplerBuffer;
        } else {
            output = buffer + bufferFilled;
        }   

        if (! lastAlive) {
            memset(output, 0, frameSize * sizeof(float));
        } else {
            int avail = 0;
            int ts = jitter_buffer_get_pointer_timestamp(_private->jitter);
            jitter_buffer_ctl(_private->jitter, JITTER_BUFFER_GET_AVAILABLE_COUNT, &avail);
            
            if (ts == 0) {
                int want = (int)averageAvailable; // fixme(mkrautz): Was iroundf.
                if (avail < want) {
                    ++missCount;
                    if (missCount < 20) {
                        memset(output, 0, frameSize * sizeof(float));
                        goto nextframe;
                    }
                }
            }

            if ([frames count] == 0) {
                int err = pthread_mutex_lock(&jitterMutex);
                if (err != 0) {
                    NSLog(@"AudioOutputSpeech: unable to lock() mutex.");
                }

                char data[4096];

                JitterBufferPacket jbp;
                jbp.data = data;
                jbp.len = 4096;

                spx_int32_t startofs = 0;

                int jerr = jitter_buffer_get(_private->jitter, &jbp, frameSize, &startofs);
                if (jerr == JITTER_BUFFER_OK) {
                    MKPacketDataStream *pds = [[MKPacketDataStream alloc] initWithBuffer:(unsigned char *)jbp.data length:jbp.len];

                    missCount = 0;
                    flags = (unsigned char)[pds next];
                    hasTerminator = NO;
                    
                    if (_msgType == UDPVoiceOpusMessage) {
                        int size = [pds getInt];
                        if (size > 0) {
                            NSData *block = [pds copyDataBlock:size];
                            [frames addObject:block];
                            [block release];
                        } else {
                            hasTerminator = YES;
                        }
                    } else {
                        unsigned int header = 0;
                        do {
                            header = (unsigned int)[pds next];
                            if (header) {
                                NSData *block = [pds copyDataBlock:(header & 0x7f)];
                                [frames addObject:block];
                                [block release];
                            } else {
                                hasTerminator = YES;
                            }
                        } while ((header & 0x80) && [pds valid]);
                    }

                    if ([pds left]) {
                        pos[0] = [pds getFloat];
                        pos[1] = [pds getFloat];
                        pos[2] = [pds getFloat];
                    } else {
                        pos[0] = pos[1] = pos[2] = 0.0f;
                    }

                    [pds release];

                    float a = (float) avail;
                    if (a >= averageAvailable) {
                        averageAvailable = a;
                    } else {
                        averageAvailable *= 0.99f;
                    }
                } else {                    
                    jitter_buffer_update_delay(_private->jitter, &jbp, NULL);

                    ++missCount;
                    if (missCount > 10) {
                        nextAlive = NO;
                    }
                }

                err = pthread_mutex_unlock(&jitterMutex);
                if (err != 0) {
                    NSLog(@"AudioOutputSpeech: Unable to unlock mutex.");
                }
            }

            if ([frames count] > 0) {
                NSData *frameData = [frames objectAtIndex:0];

                if (_msgType == UDPVoiceOpusMessage) {
                    decodedSamples = opus_decode_float(_opusDecoder, [frameData bytes], [frameData length], output, _audioBufferSize, 0);
                    outputSize = (int)(ceilf((float)decodedSamples * _freq) / (float)_sampleRate);
                    [self resizeBuffer:bufferFilled + outputSize];
                } else if (_msgType == UDPVoiceSpeexMessage) {
                    if ([frameData length] == 0) {
                        speex_decode(_private->speexDecoder, NULL, output);
                    } else {
                        speex_bits_read_from(&_private->speexBits, [frameData bytes], [frameData length]);
                        speex_decode(_private->speexDecoder, &_private->speexBits, output);
                    }
                    for (unsigned int i=0; i < frameSize; i++)
                        output[i] *= (1.0f / 32767.0f);
                } else {
                    if ([frameData length] != 0) {
                        celt_decode_float(_private->celtDecoder, [frameData bytes], [frameData length], output);
                    } else {
                        celt_decode_float(_private->celtDecoder, NULL, 0, output);
                    }
                }

                [frames removeObjectAtIndex:0];

                BOOL update = YES;

                float pow = 0.0f;
                for (i = 0; i < decodedSamples; ++i) {
                    pow += output[i] * output[i];
                }
                pow = sqrtf(pow / decodedSamples);
                if (pow > powerMax) {
                    powerMax = pow;
                } else {
                    if (pow <= powerMin) {
                        powerMin = pow;
                    } else {
                        powerMax = 0.99f * powerMax;
                        powerMin += 0.0001f * pow;
                    }
                }

                update = (pow < (powerMin + 0.01f * (powerMax - powerMin)));

                if ([frames count] == 0 && update) {
                    jitter_buffer_update_delay(_private->jitter, NULL, NULL);
                }

                if ([frames count] == 0 && hasTerminator) {
                    nextAlive = NO;
                }
            } else {
                if (_msgType == UDPVoiceOpusMessage) {
                    opus_decode_float(_opusDecoder, NULL, 0, output, frameSize, 0);
                } else if (_msgType == UDPVoiceSpeexMessage) {
                    speex_decode(_private->speexDecoder, NULL, output);
                    for (unsigned int i = 0; i < frameSize; i++)
                        output[i] *= (1.0f / 32767.0f);
                } else {
                    celt_decode_float(_private->celtDecoder, NULL, 0, output);
                }
            }

            if (! nextAlive) {
                for (i = 0; i < frameSize; i++) {
                    output[i] *= fadeOut[i];
                }
            } else if (ts == 0) {
                for (i = 0; i < frameSize; i++) {
                    output[i] *= fadeIn[i];
                }
            }

            int j;
            for (j = decodedSamples / frameSize; j > 0; j--)
                jitter_buffer_tick(_private->jitter);
        }
        
        if (! nextAlive)
            flags = 0xff;

        MKTalkState prevTalkState = _talkState;
        switch (flags) {
            case 0:
                _talkState = MKTalkStateTalking;
                break;
            case 1:
                _talkState = MKTalkStateShouting;
                break;
            case 0xff:
                _talkState = MKTalkStatePassive;
                break;
            default:
                _talkState = MKTalkStateWhispering;
                break;
        }

        if (prevTalkState != _talkState) {
            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
            NSDictionary *talkStateDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                                [NSNumber numberWithUnsignedInteger:_talkState], @"talkState",
                                                [NSNumber numberWithUnsignedInteger:_userSession], @"userSession",
                                           nil];
            NSNotification *talkNotification = [NSNotification notificationWithName:@"MKAudioUserTalkStateChanged" object:talkStateDict];
            [center performSelectorOnMainThread:@selector(postNotification:) withObject:talkNotification waitUntilDone:NO];
        }

nextframe:
        {
            spx_uint32_t inlen = decodedSamples;
            spx_uint32_t outlen = outputSize;
            if (_private->resampler && lastAlive) {
                speex_resampler_process_float(_private->resampler, 0, _resamplerBuffer, &inlen, buffer + bufferFilled, &outlen);
            }
            bufferFilled += outlen;
        }
    }
    
    BOOL tmp = lastAlive;
    lastAlive = nextAlive;
    return tmp;
}

@end
