// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKUser.h>
#import <MumbleKit/MKConnection.h>

@class MKAudioInput;
@class MKAudioOutput;

#define SAMPLE_RATE 48000

typedef enum _MKCodecFormat {
    MKCodecFormatSpeex,
    MKCodecFormatCELT,
    MKCodecFormatOpus,
} MKCodecFormat;

typedef enum _MKTransmitType {
    MKTransmitTypeVAD,
    MKTransmitTypeToggle,
    MKTransmitTypeContinuous,
} MKTransmitType;

typedef enum _MKVADKind {
    MKVADKindSignalToNoise,
    MKVADKindAmplitude,
} MKVADKind;

typedef struct _MKAudioSettings {
    MKCodecFormat   codec;
    MKTransmitType  transmitType;
    MKVADKind       vadKind;
    float           vadMax;
    float           vadMin;
    int             quality;
    int             audioPerPacket;
    int             noiseSuppression;
    float           amplification;
    int             jitterBufferSize;
    float           volume;
    int             outputDelay;
    float           micBoost;
    BOOL            enablePreprocessor;
} MKAudioSettings;

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

- (NSString *) currentAudioRoute;
- (float) speechProbablity;
- (float) peakCleanMic;

@end
