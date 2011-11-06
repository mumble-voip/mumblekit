/* Copyright (C) 2010 Mikkel Krautz <mikkel@krautz.dk>

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
#import <MumbleKit/MKChannel.h>
#import <MumbleKit/MKConnection.h>

@class MulticastDelegate;
@class MKServerModel;

/**
 * MKServerModelDelegate is the delegate of MKServerModel.
 * It is called to notify any registered delegates of events happening on the server, or
 * of replies to previously sent messages.
 */
@protocol MKServerModelDelegate

// All members are currently optional.
@optional

///------------------------------------------
/// @name Connection and disconnection events
///------------------------------------------

/**
 * Called upon successfully authenticating with a server.
 *
 * @param model  The MKServerModel object in which this event originated.
 * @param user   The MKUser object representing the local user.
 */
- (void) serverModel:(MKServerModel *)model joinedServerAsUser:(MKUser *)user;

/**
 * Called when disconnected from the server (forcefully or not).
 *
 * @param model  The MKServerModel object in which this event originated.
 */
- (void) serverModelDisconnected:(MKServerModel *)model;

///-------------------
/// @name User changes
///-------------------

/**
 * Called when a new user joins the server.
 *
 * @param model  The MKServerModel object in which this event originated.
 * @param user   The user who joined the server.
 */
- (void) serverModel:(MKServerModel *)model userJoined:(MKUser *)user;

/**
 * Called when the talk state of a user changes.
 * This event is fired when the audio subsystem (MKAudio and its minions) notify
 * the MKServerModel that audio data from a user on the connection handled by the
 * server model is being played back.
 *
 * @param model  The MKServerModel object in which this event originated.
 * @param user   The user whose talk state changed.
 */
- (void) serverModel:(MKServerModel *)model userTalkStateChanged:(MKUser *)user;

/**
 * Called when a user is renamed.
 *
 * @param model  The MKServerModel object in which this event originated.
 * @param user   The user that was renamed.
 */
- (void) serverModel:(MKServerModel *)model userRenamed:(MKUser *)user;

/**
 * Called when a user is moved to another channel.
 * This is also called when a user changes the channel he resides in (in which
 * case user is equivalent to mover).
 *
 * In case the server initiated the move, the mover is nil.
 *
 * @param model  The MKServerModel object in which this event originated.
 * @param user   The user that was moved.
 * @param chan   The channel to which user was moved to.
 * @param mover  The user that performed the user move. If the move was
 *               performed by the server, mover is nil.
 *
 */
- (void) serverModel:(MKServerModel *)model userMoved:(MKUser *)user toChannel:(MKChannel *)chan byUser:(MKUser *)mover;

/**
 * Called when a user is moved to another channel.
 * This is also called when a user changes the channel he resides in (in which
 * case user is equivalent to mover).
 *
 * In case the server initiated the move, the mover is nil.
 *
 * @param model     The MKServerModel object in which this event originated.
 * @param user      The user that was moved.
 * @param chan      The channel to which user was moved to.
 * @param prevChan  The channel from which the user was moved. (May be nil)
 * @param mover     The user that performed the user move. If the move was
 *                  performed by the server, mover is nil.
 *
 */
- (void) serverModel:(MKServerModel *)model userMoved:(MKUser *)user toChannel:(MKChannel *)chan fromChannel:(MKChannel *)prevChan byUser:(MKUser *)mover;

/**
 * Called when a user's comment is changed.
 *
 * @param model  The MKServerModel in which this event originated.
 * @param user   The user whose comment was changed.
 */
- (void) serverModel:(MKServerModel *)model userCommentChanged:(MKUser *)user;

/**
 * Called when a user's texture is changed.
 *
 * @param model  The MKServerModel in which this event originated.
 * @param user   The user whose texture was changed.
 */
- (void) serverModel:(MKServerModel *)model userTextureChanged:(MKUser *)user;

///--------------------
/// @name Text messages
///--------------------

/**
 * Called whenever a text message is receieved.
 *
 * @param model  The MKServerModel in which this event originated.
 * @param msg    The MKTextMessage object representing the received text message.
 */
//- (void) serverModel:(MKServerModel *)model textMessageReceived:(MKTextMessage *)msg;

///--------------------------------
/// @name Self-mute and self-deafen
///--------------------------------

/**
 * Called when a user self-mutes himself.
 *
 * @param model  The MKServerModel object in which this event originated.
 * @param user   The user who self-muted himself.
 */
- (void) serverModel:(MKServerModel *)model userSelfMuted:(MKUser *)user;

/**
 * Called when a user removes his self-mute status.
 *
 * @param model  The MKServerModel object in which this event originated.
 * @param user   The user who removed his self-mute status.
 */
- (void) serverModel:(MKServerModel *)model userRemovedSelfMute:(MKUser *)user;

/**
 * Called when a user self-mute-deafens himself.
 *
 * @param model  The MKServerModel in which this event originated.
 * @param user   The user who self-muted and self-deafened himself.
 */
- (void) serverModel:(MKServerModel *)model userSelfMutedAndDeafened:(MKUser *)user;

/**
 * Called when a user removes his self-mute-deafen status.
 *
 * @param model  The MKServerModel in which this event originated.
 * @param user   The user who removed his self-mute-deafen status.
 */
- (void) serverModel:(MKServerModel *)model userRemovedSelfMuteAndDeafen:(MKUser *)user;

/**
 * Called by the MKServerModel when a user's self-mute-deafen status changes.
 *
 * @param model  The MKServerModel in which this event originated.
 * @param user   The user whose self-mute-deafen status changed.
 */
- (void) serverModel:(MKServerModel *)model userSelfMuteDeafenStateChanged:(MKUser *)user;

///----------------------------------------
/// @name Muting, deafening and suppressing
///----------------------------------------

/**
 * Called when a user mutes-deafens another user.
 *
 * @param model  The MKServerModel in which this event originated.
 * @param user   The user who was mute-deafened.
 * @param actor  The user who initiated the mute-deafen action on the other user.
 *               May be nil if the server mute-deafened the user. 
 */
- (void) serverModel:(MKServerModel *)model userMutedAndDeafened:(MKUser *)user byUser:(MKUser *)actor;

/**
 * Called when a user removes mute-deafen status from another user.
 *
 * @param model  The MKServerModel in which this event originated.
 * @param user   The user whose mute-deafen status was removed.
 * @param actor  The user who iniated the removal of the other user's mute-deafen status.
 *               May be nil if the server removed the mute-deafen status.
 */
- (void) serverModel:(MKServerModel *)model userUnmutedAndUndeafened:(MKUser *)user byUser:(MKUser *)actor;

/**
 * Called when a user is muted by another user.
 *
 * @param model  The MKServerModel in which this event originated.
 * @param user   The user who was muted.
 * @param actor  The user who muted the other user. May be nil if the user was muted by
 *               the server.
 */
- (void) serverModel:(MKServerModel *)model userMuted:(MKUser *)user byUser:(MKUser *)actor;

/**
 * Called when a user is unmuted by another user.
 *
 * @param model  The MKServerModel in which this event originated.
 * @param user   The user who was unmuted.
 * @param actor  The user who unmuted the other user. May be nil if the user was unmuted by the
 *               server.
 */
- (void) serverModel:(MKServerModel *)model userUnmuted:(MKUser *)user byUser:(MKUser *)actor;

/**
 * Called when a user is deafened by another user.
 *
 * @param model  The MKServerModel in which this event originated.
 * @param user   The user who was deafened.
 * @param actor  The user who deafened the other user. May be nil if the user was deafened by
 *               the server.
 */
- (void) serverModel:(MKServerModel *)model userDeafened:(MKUser *)user byUser:(MKUser *)actor;

/**
 * Called when a user is undeafened by another user.
 *
 * @param model  The MKServerModel in which this event originated.
 * @param user   The user who was undeafened.
 * @param actor  The user who undeafened the other user. May be nil if the user was undeafened
 *               by the server.
 */
- (void) serverModel:(MKServerModel *)model userUndeafened:(MKUser *)user byUser:(MKUser *)actor;

/**
 * Called when a user is suppressed by another user.
 *
 * @param model  The MKServerModel in which this event originated.
 * @param user   The user who was suppressed.
 * @param actor  The user who suppressed the other user. May be nil if the user was
 *               suppressed by the server.
 */
- (void) serverModel:(MKServerModel *)model userSuppressed:(MKUser *)user byUser:(MKUser *)actor;

/**
 * Called when a user is unsuppressed by another user. 
 *
 * @param model  The MKServerModel in which this event originated.
 * @param user   The user who was unsuppressed.
 * @param actor  The user who unsuppresed the other user. May be nil if the user was
 *               unsupressed by the server.
 */
- (void) serverModel:(MKServerModel *)model userUnsuppressed:(MKUser *)user byUser:(MKUser *)actor;

/**
 * Called when a user's mute state changes.
 *
 * @param model  The MKServerModel in which this event originated.
 * @param user   The user whose mute state changed.
 */
- (void) serverModel:(MKServerModel *)model userMuteStateChanged:(MKUser *)user;

///-------------------------------------
/// @name Priority speaker and recording
///-------------------------------------

/**
 * Called when a user's priorty speaker flag changes.
 *
 * @param model  The MKServerModel in which this event originated.
 * @param user   The user whose priority speaker flag changed.
 */
- (void) serverModel:(MKServerModel *)model userPrioritySpeakerChanged:(MKUser *)user;

/**
 * Called when a user's recording flag changes.
 *
 * @param model   The MKServerModle in which this event originated.
 * @param user    The user whose recording flag changed.
 */
- (void) serverModel:(MKServerModel *)model userRecordingStateChanged:(MKUser *)user;

///--------------------
/// @name Leaving users
///--------------------

/**
 * Called when a user is banned by another user (or the server).
 * When a user is banned, he is also kicked from the server at the
 * same time.
 *
 * @param model   The MKServerModel in which this event originated.
 * @param user    The user that was banned.
 * @param actor   The user that banned the other user. May be nil if the
 *                ban was initiated by the server.
 * @param reason  The reason for the ban.
 */
- (void) serverModel:(MKServerModel *)model userBanned:(MKUser *)user byUser:(MKUser *)actor forReason:(NSString *)reason;

/**
 * Called when a user is kicked by another user (or the server).
 *
 * @param model   The MKServerModel in which this event originated.
 * @param user    The user that was kicked.
 * @param actor   The user that kicked the other user. May be nil if the
 *                server initiated the kick.
 * @param reason  The reason for kicking the user off the server.
 */
- (void) serverModel:(MKServerModel *)model userKicked:(MKUser *)user byUser:(MKUser *)actor forReason:(NSString *)reason;

/**
 * Called when a user disconnects from the server.
 *
 * @param model   The MKServerModel in which this event originated.
 * @param user    The user that disconnected.
 */
- (void) serverModel:(MKServerModel *)model userDisconnected:(MKUser *)user;

/**
 * Called when a user leaves the server.
 *
 * @param model   The MKServerModel in which this event originated.
 * @param user    The user that left the server.
 */
- (void) serverModel:(MKServerModel *)model userLeft:(MKUser *)user;

///-----------------------------
/// @name Channel-related events
///-----------------------------

/**
 * Called when a new channel is added.
 *
 * @param model    The MKserverModel in which this event originated.
 * @param channel  The channel that was added.
 */
- (void) serverModel:(MKServerModel *)model channelAdded:(MKChannel *)channel;

/**
 * Called when a channel is removed from the server.
 *
 * @param model    The MKServerModel in which this event originated.
 * @param channel  The channel that was removed.
 */
- (void) serverModel:(MKServerModel *)model channelRemoved:(MKChannel *)channel;

/**
 * Called when a channel is renamed.
 *
 * @param model    The MKServerModel in which this event originated.
 * @param channel  The channel that was renamed.
 */
- (void) serverModel:(MKServerModel *)model channelRenamed:(MKChannel *)channel;

/**
 * Called when a channel's position is changed.
 *
 * @param model    The MKServerModel in which this event originated.
 * @param channel  The channel whose position was changed.
 */
- (void) serverModel:(MKServerModel *)model channelPositionChanged:(MKChannel *)channel;

/**
 * Called when a channel (and all of its subchannels, and users) is re-parented.
 *
 * @param model    The MKServerModel in which this event originated.
 * @param channel  The channel that was moved.
 */
- (void) serverModel:(MKServerModel *)model channelMoved:(MKChannel *)channel;

/**
 * Called when a channel description is changed.
 *
 * @param model    The MKServerModel in which this event originated.
 * @param channel  The channel whose description was changed.
 */
- (void) serverModel:(MKServerModel *)model channelDescriptionChanged:(MKChannel *)channel;

/**
 * Called when a complete list of links for a channel is receieved. (This happens
 * mostly during initial connect).
 *
 * @param model     The MKServerModel in which this event originated.
 * @param newLinks  An array of channels whose links were changed.
 * @param channel   The channel for which newLinks were set for.
 */
- (void) serverModel:(MKServerModel *)model linksSet:(NSArray *)newLinks forChannel:(MKChannel *)channel;

/**
 * Called when new channels links are added to a channel.
 *
 * @param model     The MKServerModel in which this event originated.
 * @param newLinks  An array of channels that the channel was linked to.
 * @param channel   The channel that the links were added to.
 */
- (void) serverModel:(MKServerModel *)model linksAdded:(NSArray *)newLinks toChannel:(MKChannel *)channel;

/**
 * Called when channel links are removed from a channel.
 *
 * @param model         The MKServerModel in which this event originated.
 * @param removedLinks  An array of channels that were unlinked from the channel.
 * @param channel       The channel that the links were removed from.
 */
- (void) serverModel:(MKServerModel *)model linksRemoved:(NSArray *)removedLinks fromChannel:(MKChannel *)channel;

/**
 * Called when a channel's links change.
 *
 * @param model    The MKServerModel in which this event originated.
 * @param channel  The channel whose links changed.
 */
- (void) serverModel:(MKServerModel *)model linksChangedForChannel:(MKChannel *)channel;
@end

/**
 * MKServerModel wraps an MKConnection and acts as its message handler. It provides an
 * easy to use interface for interacting with a Mumble server.
 */
@interface MKServerModel : NSObject <MKMessageHandler>

///---------------------
/// @name Initialization
///---------------------

/**
 * Initialize a MKServerModel with the given connection.
 *
 * @param connection  The connection that the MKServerModel should handle.
 */
- (id) initWithConnection:(MKConnection *)connection;

///-------------------------
/// @name Handling delegates
///-------------------------

/**
 * Add a delegate. The delegate may only implement parts of the MKServerModelDelegate protocol.
 *
 * @param delegate  The delegate to add.
 */
- (void) addDelegate:(id)delegate;

/**
 * Remove a delegate from the MKServerModel.
 *
 * @param delegate  The delegate to remove.
 */
- (void) removeDelegate:(id)delegate;

///-----------------------
/// @name Users operations
///-----------------------

/**
 * Returns the connected user. The connected user is the user that 
 */
- (MKUser *) connectedUser;

/**
 * Look up a user by session ID.
 *
 * @param session  The session ID to look up.
 *
 * @returns  Returns the user with the given session ID. Returns nil
 *           if the user does not exist on the server.
 *
 */
- (MKUser *) userWithSession:(NSUInteger)session;

/**
 * Look up a user by hash. Most commonly, the hash of a user is the SHA1 digest
 * of their X.509 certificate.
 *
 * @param hash  The hash to look up. (Typically a hex-encoded SHA1 digest).
 *
 * @returns  Returns the user with the given hash. Returns nil if the user
 *           does not exist on the server.
 */
- (MKUser *) userWithHash:(NSString *)hash;

///-------------------------
/// @name Channel operations
///-------------------------

/**
 * Get the root channel of the server the underlying MKConnection is currently
 * connected to.
 *
 * @returns  Returns a MKChannel object pointing to the root channel.
 */
- (MKChannel *) rootChannel;

/**
 * Look up a channel by its channel ID.
 *
 * @param channelId  The channel ID to look up.
 */
- (MKChannel *) channelWithId:(NSUInteger)channelId;

/**
 * Ask the underlying connection to join the given channel.
 *
 * @param channel  The channel to join.
 */
- (void) joinChannel:(MKChannel *)channel;

@end
