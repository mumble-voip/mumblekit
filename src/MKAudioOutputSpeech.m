// Copyright 2005-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKVersion.h>
#import "MKPacketDataStream.h"
#import "MKAudioOutputSpeech.h"
#import "MKAudioOutputUserPrivate.h"

#include <speex/speex.h>
#include <speex/speex_preprocess.h>
#include <speex/speex_echo.h>
#include <speex/speex_resampler.h>
#include <speex/speex_jitter.h>
#include <speex/speex_types.h>
#include <celt.h>
#include <opus.h>

@interface MKAudioOutputSpeech () {
    OpusDecoder          *_opusDecoder;

    CELTDecoder          *_celtDecoder;
    CELTMode             *_celtMode;

    void                 *_speexDecoder;
    SpeexBits             _speexBits;

    NSLock               *_jitterLock;
    JitterBuffer         *_jitter;

    SpeexResamplerState  *_resampler;
    
    MKUDPMessageType      _msgType;
    NSUInteger            _bufferOffset;
    NSUInteger            _bufferFilled;
    NSUInteger            _outputSize;
    NSUInteger            _lastConsume;
    NSUInteger            _frameSize;
    BOOL                  _lastAlive;
    BOOL                  _hasTerminator;

    BOOL                  _useStereo;
    NSInteger             _audioBufferSize;
    float                *_resamplerBuffer;
    NSUInteger            _sampleRate;
    NSUInteger            _freq;
    
    float                *_fadeIn;
    float                *_fadeOut;
    
    NSInteger             _missCount;
    NSInteger             _missedFrames;
    
    NSMutableArray       *_frames;
    unsigned char         _flags;
    
    NSUInteger            _userSession;
    float                 _powerMin;
    float                 _powerMax;
    float                 _averageAvailable;
    
    MKTalkState           _talkState;
}
@end

@implementation MKAudioOutputSpeech

- (id) initWithSession:(NSUInteger)session sampleRate:(NSUInteger)freq messageType:(MKUDPMessageType)type {
    if ((self = [super init])) {
        _jitter = NULL;
        _celtMode = NULL;
        _celtDecoder = NULL;
        _speexDecoder = NULL;
        _resampler = NULL;

        _useStereo = NO;
    
        _userSession = session;
        _talkState = MKTalkStatePassive;
        _msgType = type;
        _freq = freq;

        if (_msgType == UDPVoiceOpusMessage) {
            _sampleRate = SAMPLE_RATE;
            _frameSize = _sampleRate / 100;
            _audioBufferSize = 12 * _frameSize;
            _opusDecoder = opus_decoder_create((opus_int32)_sampleRate, _useStereo ? 2 : 1, NULL);
        } else if (type == UDPVoiceSpeexMessage) {
            _sampleRate = 32000;
            speex_bits_init(&_speexBits);
            _speexDecoder = speex_decoder_init(speex_lib_get_mode(SPEEX_MODEID_UWB));
            int iArg = 1;
            speex_decoder_ctl(_speexDecoder, SPEEX_SET_ENH, &iArg);
            speex_decoder_ctl(_speexDecoder, SPEEX_GET_FRAME_SIZE, &_frameSize);
            speex_decoder_ctl(_speexDecoder, SPEEX_GET_SAMPLING_RATE, &_sampleRate);
            _audioBufferSize = _frameSize;
        } else {
            _sampleRate = SAMPLE_RATE;
            _frameSize = _sampleRate / 100;
            _celtMode = celt_mode_create(SAMPLE_RATE, SAMPLE_RATE/100, NULL);
            _celtDecoder = celt_decoder_create(_celtMode, 1, NULL);
            _audioBufferSize = _frameSize;
        }

        _outputSize = (int)(ceilf((float)_audioBufferSize * _freq) / (float)_sampleRate);
        if (_useStereo) {
            _audioBufferSize *= 2;
            _outputSize *= 2;
        }

        if (_freq != _sampleRate) {
            int err;
            _resampler = speex_resampler_init(_useStereo ? 2 : 1, (spx_uint32_t)_sampleRate, (spx_uint32_t)_freq, 3, &err);
            _resamplerBuffer = malloc(sizeof(float)*_audioBufferSize);
            NSLog(@"AudioOutputSpeech: Resampling from %lu Hz to %lu Hz", (unsigned long)_sampleRate, (unsigned long)_freq);
        }    

        _bufferOffset = 0;
        _bufferFilled = 0;
        _lastConsume = 0;

        _lastAlive = TRUE;

        _missCount = 0;
        _missedFrames = 0;

        _flags = 0xff;

        _jitterLock = [[NSLock alloc] init];
        _jitter = jitter_buffer_init((int)_frameSize);
    
        int margin = /* g.s.iJitterBufferSize */ 10 * (int)_frameSize;
        jitter_buffer_ctl(_jitter, JITTER_BUFFER_SET_MARGIN, &margin);

        _fadeIn = malloc(sizeof(float) * _frameSize);
        _fadeOut = malloc(sizeof(float) * _frameSize);

        float mul = (float)(M_PI / (2.0 * (float)_frameSize));
        NSUInteger i;
        for (i = 0; i < _frameSize; ++i) {
            _fadeIn[i] = _fadeOut[_frameSize-i-1] = sinf((float)i * mul);
        }

        _frames = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void) dealloc {
    if (_celtDecoder)
        celt_decoder_destroy(_celtDecoder);
    if (_celtMode)
        celt_mode_destroy(_celtMode);
    if (_speexDecoder) {
        speex_decoder_destroy(_speexDecoder);
        speex_bits_destroy(&_speexBits);
    }
    if (_resampler)
        speex_resampler_destroy(_resampler);
    if (_jitter)
        jitter_buffer_destroy(_jitter);
    if (_opusDecoder)
        opus_decoder_destroy(_opusDecoder);

    if (_fadeIn)
        free(_fadeIn);
    if (_fadeOut)
        free(_fadeOut);
    
    if (_resamplerBuffer)
        free(_resamplerBuffer);

    [_jitterLock release];
    [_frames release];

    [super dealloc];
}

- (NSUInteger) userSession {
    return _userSession;
}

- (MKUDPMessageType) messageType {
    return _msgType;
}

- (void) addFrame:(NSData *)data forSequence:(NSUInteger)seq {
    [_jitterLock lock];

    if ([data length] < 2) {
        [_jitterLock unlock];
        return;
    }

    MKPacketDataStream *pds = [[MKPacketDataStream alloc] initWithData:data];
    [pds next];

    NSUInteger samples = 0;
    if (_msgType == UDPVoiceOpusMessage) {
        uint64_t header = [pds getVarint];
        opus_uint32 size = (header & ((1 << 13) - 1));
        if (size > 0) {
            NSData *opusFrames = [pds copyDataBlock:size];
            if ([opusFrames length] != (NSUInteger)size || ![pds valid]) {
                [pds release];
                [_jitterLock unlock];
                return;
            }
            int nframes = opus_packet_get_nb_frames([opusFrames bytes], size);
            samples = nframes * opus_packet_get_samples_per_frame([opusFrames bytes], SAMPLE_RATE);
            [opusFrames release];
        } else {
            // Prevents a jitter buffer warning for terminator packets.
            samples = 1 * _frameSize;
        }
    } else {
        unsigned int header = 0;
        do {
            header = (unsigned int)[pds next];
            samples += _frameSize;
            [pds skip:(header & 0x7f)];
        } while ((header & 0x80) && [pds valid]);
    }

    if (! [pds valid]) {
        [pds release];
        NSLog(@"addFrame:: Invalid pds.");
        [_jitterLock unlock];
        return;
    }

    if ([data length] <= UINT32_MAX) {
        JitterBufferPacket jbp;
        jbp.data = (char *)[data bytes];
        jbp.len = (spx_uint32_t)[data length];
        jbp.span = (spx_uint32_t)samples;
        jbp.timestamp = (spx_uint32_t)_frameSize * (spx_uint32_t)seq;

        jitter_buffer_put(_jitter, &jbp);
    }

    [pds release];
    
    [_jitterLock unlock];
}

- (BOOL) needSamples:(NSUInteger)nsamples {
    NSUInteger i;
    
    for (i = _lastConsume; i < _bufferFilled; ++i) {
        _buffer[i-_lastConsume] = _buffer[i];
    }
    _bufferFilled -= _lastConsume;

    _lastConsume = nsamples;

    if (_bufferFilled >= nsamples) {
        return _lastAlive;
    }

    float *output = NULL;
    BOOL nextAlive = _lastAlive;
    
    while (_bufferFilled < nsamples) {
        int decodedSamples = (int)_frameSize;
        [self resizeBuffer:(_bufferFilled + _outputSize)];

        if (_resampler) {
            output = _resamplerBuffer;
        } else {
            output = _buffer + _bufferFilled;
        }   

        if (!_lastAlive) {
            memset(output, 0, _frameSize * sizeof(float));
        } else {
            int avail = 0;
            
            [_jitterLock lock];
            int ts = jitter_buffer_get_pointer_timestamp(_jitter);
            jitter_buffer_ctl(_jitter, JITTER_BUFFER_GET_AVAILABLE_COUNT, &avail);
            [_jitterLock unlock];
            
            if (ts == 0) {
                int want = (int) _averageAvailable;
                if (avail < want) {
                    _missCount++;
                    if (_missCount < 20) {
                        memset(output, 0, _frameSize * sizeof(float));
                        goto nextframe;
                    }
                }
            }

            if ([_frames count] == 0) {
                [_jitterLock lock];

                char data[4096];

                JitterBufferPacket jbp;
                jbp.data = data;
                jbp.len = 4096;

                spx_int32_t startofs = 0;

                if (jitter_buffer_get(_jitter, &jbp, (spx_int32_t)_frameSize, &startofs) == JITTER_BUFFER_OK) {
                    MKPacketDataStream *pds = [[MKPacketDataStream alloc] initWithBuffer:(unsigned char *)jbp.data length:jbp.len];

                    _missCount = 0;
                    _flags = (unsigned char) [pds next];
                    _hasTerminator = NO;
                    
                    if (_msgType == UDPVoiceOpusMessage) {
                        uint64_t header = [pds getVarint];
                        NSUInteger size = (header & ((1 << 13) - 1));
                        _hasTerminator = header & (1 << 13);
                        if (size > 0) {
                            NSData *block = [pds copyDataBlock:size];
                            if (block != nil) {
                                [_frames addObject:block];
                                [block release];
                            }
                        }
                    } else {
                        unsigned int header = 0;
                        do {
                            header = (unsigned int)[pds next];
                            if (header) {
                                NSData *block = [pds copyDataBlock:(header & 0x7f)];
                                if (block != nil) {
                                    [_frames addObject:block];
                                    [block release];
                                }
                            } else {
                                _hasTerminator = YES;
                            }
                        } while ((header & 0x80) && [pds valid]);
                    }

                    if ([pds left]) {
                        _pos[0] = [pds getFloat];
                        _pos[1] = [pds getFloat];
                        _pos[2] = [pds getFloat];
                    } else {
                        _pos[0] = 0.0f;
                        _pos[1] = 0.0f;
                        _pos[2] = 0.0f;
                    }

                    [pds release];

                    float a = (float) avail;
                    if (a >= _averageAvailable) {
                        _averageAvailable = a;
                    } else {
                        _averageAvailable *= 0.99f;
                    }
                } else {                    
                    jitter_buffer_update_delay(_jitter, &jbp, NULL);

                    _missCount++;
                    if (_missCount > 10) {
                        nextAlive = NO;
                    }
                }

                [_jitterLock unlock];
            }

            if ([_frames count] > 0) {
                NSData *frameData = [_frames objectAtIndex:0];

                if (_msgType == UDPVoiceOpusMessage) {
                    if ([frameData length] <= INT_MAX) {
                        decodedSamples = opus_decode_float(_opusDecoder, [frameData bytes], (int)[frameData length], output, (int)_audioBufferSize, 0);
                        if (decodedSamples < 0) {
                            decodedSamples = (int)_frameSize;
                            memset(output, 0, _frameSize * sizeof(float));
                        }
                    } else {
                        decodedSamples = (int)_frameSize;
                        memset(output, 0, _frameSize * sizeof(float));
                    }
                } else if (_msgType == UDPVoiceSpeexMessage) {
                    if ([frameData length] > 0 && [frameData length] <= INT_MAX) {
                        speex_bits_read_from(&_speexBits, [frameData bytes], (int)[frameData length]);
                        speex_decode(_speexDecoder, &_speexBits, output);
                    } else {
                        speex_decode(_speexDecoder, NULL, output);
                    }
                    for (unsigned int i=0; i < _frameSize; i++) {
                        output[i] *= (1.0f / 32767.0f);
                    }
                } else {
                    if ([frameData length] > 0 && [frameData length] <= INT_MAX) {
                        celt_decode_float(_celtDecoder, [frameData bytes], (int)[frameData length], output);
                    } else {
                        celt_decode_float(_celtDecoder, NULL, 0, output);
                    }
                }

                [_frames removeObjectAtIndex:0];

                BOOL update = YES;

                float pow = 0.0f;
                for (i = 0; i < decodedSamples; ++i) {
                    pow += output[i] * output[i];
                }
                pow = sqrtf(pow / decodedSamples);
                if (pow > _powerMax) {
                    _powerMax = pow;
                } else {
                    if (pow <= _powerMin) {
                        _powerMin = pow;
                    } else {
                        _powerMax = 0.99f * _powerMax;
                        _powerMin += 0.0001f * pow;
                    }
                }

                update = (pow < (_powerMin + 0.01f * (_powerMax - _powerMin)));

                if ([_frames count] == 0 && update) {
                    [_jitterLock lock];
                    jitter_buffer_update_delay(_jitter, NULL, NULL);
                    [_jitterLock unlock];
                }

                if ([_frames count] == 0 && _hasTerminator) {
                    nextAlive = NO;
                }
            } else {
                if (_msgType == UDPVoiceOpusMessage) {
                    decodedSamples = opus_decode_float(_opusDecoder, NULL, 0, output, (int)_frameSize, 0);
                } else if (_msgType == UDPVoiceSpeexMessage) {
                    speex_decode(_speexDecoder, NULL, output);
                    for (unsigned int i = 0; i < _frameSize; i++)
                        output[i] *= (1.0f / 32767.0f);
                } else {
                    celt_decode_float(_celtDecoder, NULL, 0, output);
                }
            }

            if (! nextAlive) {
                for (i = 0; i < _frameSize; i++) {
                    output[i] *= _fadeOut[i];
                }
            } else if (ts == 0) {
                for (i = 0; i < _frameSize; i++) {
                    output[i] *= _fadeIn[i];
                }
            }

            [_jitterLock lock];
            int j;
            for (j = decodedSamples / _frameSize; j > 0; j--)
                jitter_buffer_tick(_jitter);
            [_jitterLock unlock];
        }
        
        if (! nextAlive)
            _flags = 0xff;

        MKTalkState prevTalkState = _talkState;
        switch (_flags) {
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
            spx_uint32_t outlen = (spx_uint32_t) (ceilf((float)(decodedSamples * _freq) / (float)_sampleRate));
            
            if (_resampler && _lastAlive) {
                speex_resampler_process_float(_resampler, 0, _resamplerBuffer, &inlen, _buffer + _bufferFilled, &outlen);
            }
            _bufferFilled += outlen;
        }
    }
    
    BOOL tmp = _lastAlive;
    _lastAlive = nextAlive;
    return tmp;
}

@end
