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
#import <MumbleKit/MKReadWriteLock.h>

@class MulticastDelegate;
@class MKServerModel;

@protocol MKServerModelDelegate
// On join
- (void) serverModel:(MKServerModel *)model joinedServerAsUser:(MKUser *)user;

// User changes
- (void) serverModel:(MKServerModel *)model userJoined:(MKUser *)user;
- (void) serverModel:(MKServerModel *)model userTalkStateChanged:(MKUser *)user;
- (void) serverModel:(MKServerModel *)model userRenamed:(MKUser *)user;
- (void) serverModel:(MKServerModel *)model userMoved:(MKUser *)user toChannel:(MKChannel *)chan byUser:(MKUser *)mover;
- (void) serverModel:(MKServerModel *)model userCommentChanged:(MKUser *)user;
- (void) serverModel:(MKServerModel *)model userTextureChanged:(MKUser *)user;

//- (void) serverModel:(MKServerModel *)model textMessageReceived:(MKTextMessage *)msg;

// Self-mute and self-deafen
- (void) serverModel:(MKServerModel *)model userSelfMuted:(MKUser *)user;
- (void) serverModel:(MKServerModel *)model userRemovedSelfMute:(MKUser *)user;
- (void) serverModel:(MKServerModel *)model userSelfMutedAndDeafened:(MKUser *)user;
- (void) serverModel:(MKServerModel *)model userRemovedSelfMuteAndDeafen:(MKUser *)user;
- (void) serverModel:(MKServerModel *)model userSelfMuteDeafenStateChanged:(MKUser *)user;

// Mute, deafen and suppress
- (void) serverModel:(MKServerModel *)model userMutedAndDeafened:(MKUser *)user byUser:(MKUser *)actor;
- (void) serverModel:(MKServerModel *)model userUnmutedAndUndeafened:(MKUser *)user byUser:(MKUser *)actor;
- (void) serverModel:(MKServerModel *)model userMuted:(MKUser *)user byUser:(MKUser *)actor;
- (void) serverModel:(MKServerModel *)model userUnmuted:(MKUser *)user byUser:(MKUser *)actor;
- (void) serverModel:(MKServerModel *)model userDeafened:(MKUser *)user byUser:(MKUser *)actor;
- (void) serverModel:(MKServerModel *)model userUndeafened:(MKUser *)user byUser:(MKUser *)actor;
- (void) serverModel:(MKServerModel *)model userSuppressed:(MKUser *)user byUser:(MKUser *)actor;
- (void) serverModel:(MKServerModel *)model userUnsuppressed:(MKUser *)user byUser:(MKUser *)actor;
- (void) serverModel:(MKServerModel *)model userMuteStateChanged:(MKUser *)user;

// Priority speaker and recording
- (void) serverModel:(MKServerModel *)model userPrioritySpeakerChanged:(MKUser *)user;
- (void) serverModel:(MKServerModel *)model userRecordingStateChanged:(MKUser *)user;

// User leaving
- (void) serverModel:(MKServerModel *)model userBanned:(MKUser *)user byUser:(MKUser *)actor forReason:(NSString *)reason;
- (void) serverModel:(MKServerModel *)model userKicked:(MKUser *)user byUser:(MKUser *)actor forReason:(NSString *)reason;
- (void) serverModel:(MKServerModel *)model userDisconnected:(MKUser *)user;
- (void) serverModel:(MKServerModel *)model userLeft:(MKUser *)user;

// Channel stuff
- (void) serverModel:(MKServerModel *)model channelAdded:(MKChannel *)channel;
- (void) serverModel:(MKServerModel *)model channelRemoved:(MKChannel *)channel;
- (void) serverModel:(MKServerModel *)model channelRenamed:(MKChannel *)chan;
- (void) serverModel:(MKServerModel *)model channelPositionChanged:(MKChannel *)chan;
- (void) serverModel:(MKServerModel *)model channelMoved:(MKChannel *)chan;
- (void) serverModel:(MKServerModel *)model channelDescriptionChanged:(MKChannel *)chan;
- (void) serverModel:(MKServerModel *)model linksSet:(NSArray *)newLinks forChannel:(MKChannel *)chan;
- (void) serverModel:(MKServerModel *)model linksAdded:(NSArray *)newLinks toChannel:(MKChannel *)chan;
- (void) serverModel:(MKServerModel *)model linksRemoved:(NSArray *)removedLinks fromChannel:(MKChannel *)chan;
- (void) serverModel:(MKServerModel *)model linksChangedForChannel:(MKChannel *)chan;
@end

@interface MKServerModel : NSObject {
	MKConnection                              *_connection;
	MKChannel                                 *_rootChannel;
	MKUser                                    *_connectedUser;
	MKReadWriteLock                           *_userMapLock;
	NSMutableDictionary                       *_userMap;
	MKReadWriteLock                           *_channelMapLock;
	NSMutableDictionary                       *_channelMap;
	MulticastDelegate<MKServerModelDelegate>  *_delegate;
}

- (id) initWithConnection:(MKConnection *)conn;
- (void) dealloc;
- (void) addDelegate:(id)delegate;
- (void) removeDelegate:(id)delegate;

#pragma mark -
#pragma mark Users

- (MKUser *) connectedUser;
- (MKUser *) userWithSession:(NSUInteger)session;
- (MKUser *) userWithHash:(NSString *)hash;

#pragma mark -
#pragma mark Channel operations

- (MKChannel *) rootChannel;
- (MKChannel *) channelWithId:(NSUInteger)channelId;
- (void) joinChannel:(MKChannel *)chan;

@end
