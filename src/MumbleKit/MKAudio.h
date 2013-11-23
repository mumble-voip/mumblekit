// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKUser.h>
#import <MumbleKit/MKConnection.h>

@class MKAudio;
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

    BOOL            preferReceiverOverSpeaker;
    BOOL            opusForceCELTMode;
    BOOL            audioMixerDebug;
} MKAudioSettings;

/// @protocol MKAudioDelegate MKAudio.h MumbleKit/MKAudio.h
///
/// MKAudioDelegate a set of optional methods
/// that helps MKAudio in its operation.
@protocol MKAudioDelegate

// All methods are currently optional.
@optional

/// Called when the MKAudio singleton needs to determine whether it
/// should be running. This is needed because MKAudio abstracts
/// away Audio Session handling on iOS.
///
/// The method should return whether or not MKAudio should be running
/// at the time the method is called. A typical app using MumbleKit
/// will shut down MKAudio when it is backgrounded -- this must be
/// done manually by the app.
///
/// However, Audio Session events can come in at inopportune times.
/// For example, if Siri is acivated while in another app, and your
/// MumbleKit-using app is backgrounded, it is possible that MKAudio's
/// interruption callback on the AudioSession is invoked.
///
/// To properly handle such inopportune requests, MumbleKit will ask
/// this delegate method on how to proceed.
///
/// In 'Mumble for iOS', we do the following:
///
///    - (void) audioShouldBeRunning:(MKAudio *)audio {
///        UIApplication *app = [[UIApplication sharedApplication] applicationState];
///       UIApplicationState state = [app applicationState];
///       switch (state) {
///           case UIApplicationStateActive:
///               // When in the foreground, we always keep MKAudio running.
///               return YES;
///           case UIApplicationStateBackground:
///           case UIApplicationStateInactive:
///               // When backgrounded, only turn on MKAudio if we're connected
///               // to a server.
///               return _connectionActive;
///       }
///       return NO;
///    }
///
/// If this method is not implemented, MKAudio will fall back to
/// a sane default, depending on OS:
///
/// For iOS, audioShouldBeRunning: returns YES if the application state
/// is 'active'.
///
/// For Mac OS X, audioShouldBeRunning: always returns YES.
///
/// Note: This method is only used for internal decisions in
/// MKAudio.  When a MumbleKit client manually cals the start
/// and/or stop methods of MKAudio, this method will not be
/// consulted at all.
///
/// @param audio  The MKAudio singleton instance.
- (BOOL) audioShouldBeRunning:(MKAudio *)audio;
@end

/// @class MKAudio MKAudio.h MumbleKit/MKAudio.h
///
/// MKAudio represents the MumbleKit audio subsystem.
@interface MKAudio : NSObject

///------------------------------------
/// @name Accessing the audio subsystem
///------------------------------------

/// Get a shared copy of the MKAudio object for this process.
///
/// @return Retruns the shared MKAudio object.
+ (MKAudio *) sharedAudio;

///------------------------------------
/// @name Delegate
///------------------------------------

/// Get the MKAudio singleton's delegate.
- (id<MKAudioDelegate>) delegate;

/// Set the MKAudio singleton's delegate.
- (void) setDelegate:(id<MKAudioDelegate>)delegate;

///----------------------------
/// @name Starting and stopping
///----------------------------

/// Returns whether or not the MumbleKit audio subsystem is currently running.
- (BOOL) isRunning;

/// Starts the MumbleKit audio subsytem.
- (void) start;

/// Stops the MumbleKit audio subsystem.
- (void) stop;

/// Restarts MumbleKit's audio subsystem.
- (void) restart;

///---------------
/// @name Settings
///---------------

/// Reads the current configuration of the MumbleKit audio subsystem
/// into settings.
///
/// @param  settings  A pointer to the MKAudioSettings struct the settings should be read into.
- (void) readAudioSettings:(MKAudioSettings *)settings;

/// Updates the MumbleKit audio subsystem with a new configuration.
///
/// @param settings  A pointer to a MKAudioSettings struct with the new audio subsystem settings.
- (void) updateAudioSettings:(MKAudioSettings *)settings;

///-------------------
/// @name Transmission
///-------------------

/// Returns the current transmit type (as set by calling setAudioSettings:.
- (MKTransmitType) transmitType;

/// Returns whether forceTransmit is enabled.
/// Forced-transmit is used to implemented push-to-talk functionality.
- (BOOL) forceTransmit;

/// Sets the current force-transmit state.
///
/// @param enableForceTransmit  Whether or not to enable force-transmit.
- (void) setForceTransmit:(BOOL)enableForceTransmit;

/// Returns whether or not the system's current audio route is
/// suitable for echo cancellation.
- (BOOL) echoCancellationAvailable;

/// Sets the main connection for audio purposes.  This is the connection
/// that the audio input code will use when tramitting produced packets.
///
/// Currently, this method should not be used. It is a future API.
/// Internally, any constructed MKConnection will implicitly register
/// itself as the main connection for audio purposes. In the future,
/// this will be an explicit choice instead, allowing multiple
/// connections to live alongside eachother.
///
/// @param  conn  The MKConnection to set as the main connection
///               for audio purposes.
- (void) setMainConnectionForAudio:(MKConnection *)conn;
- (void) addFrameToBufferWithSession:(NSUInteger)session data:(NSData *)data sequence:(NSUInteger)seq type:(MKUDPMessageType)msgType;
- (MKAudioOutputSidetone *) sidetoneOutput;
- (float) speechProbablity;
- (float) peakCleanMic;

///----------------------------
/// @name Audio Mixer Debugging
///----------------------------

/// Query the MKAudioOutput module for debugging
/// data from its mixer.
///
/// If this method is called without enabling the
/// audioMixerDebug flag in MKSettings, the debug
/// info will be mostly empty, but still valid.
- (NSDictionary *) copyAudioOutputMixerDebugInfo;

@end
