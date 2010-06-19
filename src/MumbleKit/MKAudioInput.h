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

#import <MumbleKit/MKAudio.h>
#import <MumbleKit/MKConnection.h>
#import <AudioUnit/AudioUnit.h>
#import <AudioUnit/AUComponent.h>
#import <AudioToolbox/AudioToolbox.h>

struct MKAudioInputPrivate;

@interface MKAudioInput : NSObject {
	@private
		struct MKAudioInputPrivate *_private;

	@public
		AudioUnit audioUnit;
		AudioBufferList buflist;
		int micSampleSize;
		int numMicChannels;

	@protected
		MKAudioSettings _settings;

		int frameSize;
		int micFrequency;
		int sampleRate;

		int micFilled;
		int micLength;
		BOOL previousVoice;
		int bitrate;
		int frameCounter;

		BOOL doResetPreprocessor;

		short *psMic;
		short *psOut;

		MKUDPMessageType udpMessageType;
		NSMutableArray *frameList;
	
		MKCodecFormat _codecFormat;
		BOOL _doTransmit;
		BOOL _forceTransmit;
		BOOL _lastTransmit;
}

- (id) initWithSettings:(MKAudioSettings *)settings;
- (void) dealloc;

- (BOOL) setupDevice;
- (BOOL) teardownDevice;

- (void) initializeMixer;

- (void) resetPreprocessor;
- (void) addMicrophoneDataWithBuffer:(short *)input amount:(NSUInteger)nsamp;
- (void) encodeAudioFrame;
- (void) flushCheck:(NSData *)outputBuffer terminator:(BOOL)terminator;

- (void) setForceTransmit:(BOOL)flag;
- (BOOL) forceTransmit;


@end
