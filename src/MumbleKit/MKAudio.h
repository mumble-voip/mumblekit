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

typedef enum _MKTransmitType {
    MKTransmitTypeVAD,
    MKTransmitTypeToggle,
    MKTransmitTypeContinuous,
} MKTransmitType;

typedef struct _MKAudioSettings {
	MKCodecFormat   codec;
    MKTransmitType  transmitType;
	int             quality;
	int             audioPerPacket;
	int             noiseSuppression;
	float           amplification;
	int             jitterBufferSize;
	float           volume;
	int             outputDelay;
	BOOL            enablePreprocessor;
	BOOL            enableBenchmark;
} MKAudioSettings;

typedef struct _MKAudioBenchmark {
	signed long  avgPreprocessorRuntime;
} MKAudioBenchmark;


/**
 * MKAudio represents the MumbleKit audio subsystem.
 */
@interface MKAudio : NSObject

///------------------------------------
/// @name Accessing the audio subsystem
///------------------------------------

/**
 * Get a shared copy of the MKAudio object for this process.
 *
 * @return Retruns the shared MKAudio object.
 */
+ (MKAudio *) sharedAudio;

///----------------------------
/// @name Starting and stopping
///----------------------------

/**
 * Returns whether or not the MumbleKit audio subsystem is currently running.
 */
- (BOOL) isRunning;

/**
 * Starts the MumbleKit audio subsytem.
 */
- (void) start;

/**
 * Stops the MumbleKit audio subsystem.
 */
- (void) stop;

/**
 * Restarts MumbleKit's audio subsystem.
 */
- (void) restart;

///---------------
/// @name Settings
///---------------

/**
 * Returns the current configuration of the MumbleKit audio subsystem.
 */
- (MKAudioSettings *) audioSettings;

/**
 * Updates the MumbleKit audio subsystem with a new configuration.
 *
 * @param settings A pointer to a MKAudioSettings struct with the new audio subsystem settings.
 */
- (void) updateAudioSettings:(MKAudioSettings *)settings;

- (void) addFrameToBufferWithSession:(NSUInteger)session data:(NSData *)data sequence:(NSUInteger)seq type:(MKUDPMessageType)msgType;

///-------------------
/// @name Transmission
///-------------------

/**
 * Returns the current transmit type (as set by calling setAudioSettings:.
 */
- (MKTransmitType) transmitType;

/**
 * Returns whether forceTransmit is enabled.
 * Forced-transmit is used to implemented push-to-talk functionality.
 */
- (BOOL) forceTransmit;

/**
 * Sets the current force-transmit state.
 * 
 * @param enableForceTransmit  Whether or not to enable force-transmit.
 */
- (void) setForceTransmit:(BOOL)enableForceTransmit;

///----------------
/// @name Benchmark
///----------------

/**
 * Fills a MKAudioBenchmark struct with the current benchmark data.
 *
 * @param bench The struct to fill out with benchmark data. Should point to a MKAudioBenchmark struct.
 */
- (void) getBenchmarkData:(MKAudioBenchmark *)bench;

- (NSString *) currentAudioRoute;

@end
