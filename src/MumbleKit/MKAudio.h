// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKUser.h>
#import <MumbleKit/MKConnection.h>

@class MKAudioInput;
@class MKAudioOutput;
@class MKAudioOutputSidetone;

#define SAMPLE_RATE 48000

extern NSString *MKAudioDidRestartNotification;

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
    BOOL            enableEchoCancellation;
    BOOL            enableSideTone;
    float           sidetoneVolume;

    BOOL            enableComfortNoise;
    float           comfortNoiseLevel;
    BOOL            enableVadGate;
    double          vadGateTimeSeconds;
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
 * Reads the current configuration of the MumbleKit audio subsystem
 * into settings.
 *
 * @param  settings  A pointer to the MKAudioSettings struct the settings should be read into.
 */
- (void) readAudioSettings:(MKAudioSettings *)settings;

/**
 * Updates the MumbleKit audio subsystem with a new configuration.
 *
 * @param settings  A pointer to a MKAudioSettings struct with the new audio subsystem settings.
 */
- (void) updateAudioSettings:(MKAudioSettings *)settings;

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

/**
 * Returns whether or not the system's current audio route is
 * suitable for echo cancellation.
 */
- (BOOL) echoCancellationAvailable;

/**
 * Sets the main connection for audio purposes.  This is the connection
 * that the audio input code will use when tramitting produced packets.
 *
 * Currently, this method should not be used. It is a future API.
 * Internally, any constructed MKConnection will implicitly register
 * itself as the main connection for audio purposes. In the future,
 * this will be an explicit choice instead, allowing multiple
 * connections to live alongside eachother.
 *
 * @param  conn  The MKConnection to set as the main connection
 *               for audio purposes.
 */
- (void) setMainConnectionForAudio:(MKConnection *)conn;
- (void) addFrameToBufferWithSession:(NSUInteger)session data:(NSData *)data sequence:(NSUInteger)seq type:(MKUDPMessageType)msgType;
- (MKAudioOutputSidetone *) sidetoneOutput;
- (float) speechProbablity;
- (float) peakCleanMic;

@end
