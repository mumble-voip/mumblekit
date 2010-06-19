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

#import <MumbleKit/MKUser.h>
#import <MumbleKit/MKConnection.h>

@class MKAudioInput;
@class MKAudioOutput;

#define SAMPLE_RATE 48000

typedef enum _MKCodecFormat {
	MKCodecFormatSpeex,
	MKCodecFormatCELT,
} MKCodecFormat;

typedef struct _MKAudioSettings {
	MKCodecFormat	inputCodec;
	MKCodecFormat   outputCodec;
	int             quality;
	int             audioPerPacket;
	int             noiseSuppression;
	float           amplification;
	int             jitterBufferSize;
	float           volume;
	int             outputDelay;
	BOOL            enablePreprocessor;
} MKAudioSettings;

@interface MKAudio : NSObject {
	MKAudioInput *_audioInput;
	MKAudioOutput *_audioOutput;
	MKAudioSettings _audioSettings;
}

+ (MKAudio *) sharedAudio;

- (void) restart;

- (MKAudioSettings *) audioSettings;
- (void) updateAudioSettings:(MKAudioSettings *)settings;

- (void) addFrameToBufferWithUser:(MKUser *)user data:(NSData *)data sequence:(NSUInteger)seq type:(MKMessageType)msgType;

- (BOOL) forceTransmit;
- (void) setForceTransmit:(BOOL)flag;

@end
