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

#import <MumbleKit/MKServerModel.h>
#import <MumbleKit/MKConnection.h>
#import <MumbleKit/MKPacketDataStream.h>
#import <MumbleKit/MKUtils.h>
#import <MumbleKit/MKAudio.h>
#import "Mumble.pb.h"

#import "MulticastDelegate.h"

#define STUB \
	NSLog(@"%@: %s", [self class], __FUNCTION__)

@interface MKServerModel (InlinePrivate)
- (void) setSelfMuteDeafenStateForUser:(MKUser *)user fromMessage:(MPUserState *)msg;
- (void) setMuteStateForUser:(MKUser *)user fromMessage:(MPUserState *)msg;
- (void) setPrioritySpeakerStateForUser:(MKUser *)user to:(BOOL)prioritySpeaker;
@end

@implementation MKServerModel

- (id) initWithConnection:(MKConnection *)conn {
	self = [super init];
	if (self == nil)
		return nil;

	_delegate = [[MulticastDelegate alloc] init];

	userMapLock = [[MKReadWriteLock alloc] init];
	userMap = [[NSMutableDictionary alloc] init];

	channelMapLock = [[MKReadWriteLock alloc] init];
	channelMap = [[NSMutableDictionary alloc] init];

	_rootChannel = [[MKChannel alloc] init];
	[_rootChannel setChannelId:0];
	[_rootChannel setChannelName:@"Root"];
	[channelMap setObject:_rootChannel forKey:[NSNumber numberWithUnsignedInt:0]];

	_connection = conn;

	// Set us up to handle messages from the connection.
	[_connection setMessageHandler:self];
	// And also as the voice data handler.
	[_connection setVoiceDataHandler:self];

	return self;
}

- (void) dealloc {
	[super dealloc];
}

- (void) addDelegate:(id)delegate {
	[(MulticastDelegate *)_delegate addDelegate:delegate];
}

- (void) removeDelegate:(id)delegate {
	[(MulticastDelegate *)_delegate removeDelegate:delegate];
}

- (BOOL) serverInfoSynced {
	return _connectedUser != nil;
}

#pragma mark MKMessageHandler methods

-(void) connection:(MKConnection *)conn handleCodecVersionMessage:(MPCodecVersion *)codec {
	NSLog(@"MKServerModel: Received CodecVersion message");

	if ([codec hasAlpha])
		NSLog(@"alpha = 0x%x", [codec alpha]);
	if ([codec hasBeta])
		NSLog(@"beta = 0x%x", [codec beta]);
	if ([codec hasPreferAlpha])
		NSLog(@"preferAlpha = %i", [codec preferAlpha]);
}

- (void) connection:(MKConnection *)conn handleUserStateMessage:(MPUserState *)msg {
	BOOL newUser = NO;

	if (! [msg hasSession]) {
		return;
	}

	NSUInteger session = [msg session];
	MKUser *user = [self userWithSession:session];

	// Is this an existing user? Or should we create a new user object?
	if (user == nil) {
		if ([msg hasName]) {
			user = [self addUserWithSession:session name:[msg name]];
			newUser = YES;
		} else {
			return;
		}
	}

	if ([msg hasUserId]) {
		[self setIdForUser:user to:[msg userId]];
	}

	if ([msg hasHash]) {
		[self setHashForUser:user to:[msg hash]];
		/* Check if user is a friend? */
	}

	if ([msg hasSelfDeaf] || [msg hasSelfMute]) {
		[self setSelfMuteDeafenStateForUser:user fromMessage:msg];
	}

	if ([msg hasPrioritySpeaker]) {
		[self setPrioritySpeakerStateForUser:user to:[msg prioritySpeaker]];
	}

	if ([msg hasDeaf] || [msg hasMute] || [msg hasSuppress]) {
		[self setMuteStateForUser:user fromMessage:msg];
	}

	// The user just connected. Tell our delegate listeners.
	if (newUser && [self serverInfoSynced]) {
		[_delegate serverModel:self userJoined:user];
	}

	if ([msg hasChannelId]) {
		MKChannel *chan = [self channelWithId:[msg channelId]];
		if (chan == nil) {
			NSLog(@"MKServerModel: UserState with invalid channelId.");
		}
		MKChannel *oldChan = [user channel];
		if (chan != oldChan) {
			[self moveUser:user toChannel:chan byUser:nil];
			NSLog(@"Moved user '%@' to channel '%@'", [user userName], [chan channelName]);
		}

	// The user has no channel id set, and is a newly connected user.
	// This means the user's residing in the root channel.
	} else if (newUser) {
		[self moveUser:user toChannel:_rootChannel byUser:nil];
	}

	if ([msg hasName]) {
		[self renameUser:user to:[msg name]];
	}

	if ([msg hasTexture]) {
		NSLog(@"MKServerModel: User has texture.. Discarding.");
	}

	if ([msg hasComment]) {
		NSLog(@"MKServerModel: User has comment... Discarding.");
	}
}

- (void) connection:(MKConnection *)conn handleUserRemoveMessage:(MPUserRemove *)msg {
	if (! [msg hasSession]) {
		return;
	}

	MKUser *user = [self userWithSession:[msg session]];
	[_delegate serverModel:self userLeft:user];

	[self removeUser:user];
}

- (void) connection:(MKConnection *)conn handleChannelStateMessage:(MPChannelState *)msg {
	BOOL newChannel = NO;

	if (! [msg hasChannelId]) {
		return;
	}

	MKChannel *chan = [self channelWithId:[msg channelId]];
	MKChannel *parent = [msg hasParent] ? [self channelWithId:[msg parent]] : nil;

	if (!chan) {
		if ([msg hasParent] && [msg hasName]) {
			NSLog(@"MKServerModel: Adding new channel....");
			chan = [self addChannelWithId:[msg channelId] name:[msg name] parent:parent];
			if ([msg hasTemporary]) {
				[chan setTemporary:[msg temporary]];
			}
		} else {
			return;
		}
	}

	if (parent) {
		NSLog(@"MKServerModel: Moving %@ to %@", [chan channelName], [parent channelName]);
		[self moveChannel:chan toChannel:parent];
	}

	if ([msg hasName]) {
		[self renameChannel:chan to:[msg name]];
	}

	if ([msg hasDescription]) {
		[self setCommentForChannel:chan to:[msg description]];
	}

	if ([msg hasPosition]) {
		[self repositionChannel:chan to:[msg position]];
	}

	if (newChannel && [self serverInfoSynced]) {
		[_delegate serverModel:self channelCreated:chan];
	}
}

- (void) connection:(MKConnection *) handleChannelRemoveMessage:(MPChannelRemove *)msg {
	if (! [msg hasChannelId]) {
		return;
	}

	MKChannel *chan = [self channelWithId:[msg channelId]];
	if (chan && [chan channelId] != 0 && [self serverInfoSynced]) {
		[_delegate serverModel:self channelRemoved:chan];
		[self removeChannel:chan];
	}
}

//
// All server information synced.
//
- (void) connection:(MKConnection *)conn handleServerSyncMessage:(MPServerSync *)msg {

	MKUser *user = [self userWithSession:[msg session]];
	_connectedUser = user;

	[_delegate serverModel:self joinedServerAsUser:user];
}

- (void) connection:(MKConnection *)conn handleBanListMessage: (MPBanList *)msg {
}

- (void) connection:(MKConnection *)conn handlePermissionDeniedMessage: (MPPermissionDenied *)msg {
}

- (void) connection:(MKConnection *)conn handleTextMessageMessage: (MPTextMessage *)msg {
}

- (void) connection:(MKConnection *)conn handleACLMessage: (MPACL *)msg {
}

- (void) connection:(MKConnection *)conn handleQueryUsersMessage: (MPQueryUsers *)msg {
}

- (void) connection:(MKConnection *)conn handleContextActionMessage: (MPContextAction *)msg {
}

- (void) connection:(MKConnection *)conn handleContextActionAddMessage: (MPContextActionAdd *)add {
}

- (void) connection:(MKConnection *)conn handleUserListMessage: (MPUserList *)msg {
}

- (void) connection:(MKConnection *)conn handleVoiceTargetMessage: (MPVoiceTarget *)msg {
}

- (void) connection:(MKConnection *)conn handlePermissionQueryMessage: (MPPermissionQuery *)msg {
}

#pragma mark MKVoiceDataHandler

- (void) connection:(MKConnection *)conn session:(NSUInteger)session sequence:(NSUInteger)seq type:(MKUDPMessageType)msgType voiceData:(NSMutableData *)data {
	MKUser *speakingUser = [self userWithSession:session];
	[[MKAudio sharedAudio] addFrameToBufferWithUser:speakingUser data:data sequence:seq type:msgType];
	[data release];
}

#pragma mark -

- (MKUser *) connectedUser {
	return _connectedUser;
}

/*
 * Add a new user.
 *
 * @param  userSession   The session of the new user.
 * @param  userName      The username of the new user.
 *
 * @return
 * Returns the allocated User on success. Returns nil on failure. The returned User
 * is owned by the User module itself, and should not be retained or otherwise fiddled
 * with.
 */
- (MKUser *) addUserWithSession:(NSUInteger)userSession name:(NSString *)userName {
	MKUser *user = [[MKUser alloc] init];
	[user setSession:userSession];
	[user setUserName:userName];

	[userMapLock writeLock];
	[userMap setObject:user forKey:[NSNumber numberWithUnsignedInt:userSession]];
	[userMapLock unlock];

	return user;
}

- (MKUser *) userWithSession:(NSUInteger)session {
	[userMapLock readLock];
	MKUser *u = [userMap objectForKey:[NSNumber numberWithUnsignedInt:session]];
	[userMapLock unlock];
	return u;
}

- (MKUser *) userWithHash:(NSString *)hash {
	NSLog(@"userWithHash: notimpl.");
	return nil;
}

- (void) renameUser:(MKUser *)user to:(NSString *)newName {
	STUB;
}

- (void) setIdForUser:(MKUser *)user to:(NSUInteger)newId {
	[user setUserId:newId];
}

- (void) setSelfMuteDeafenStateForUser:(MKUser *)user fromMessage:(MPUserState *)msg {
	if ([msg hasSelfMute]) {
		[user setSelfMuted:[msg selfMute]];
	}
	if ([msg hasSelfDeaf]) {
		[user setSelfDeafened:[msg selfDeaf]];
	}

	if ([self serverInfoSynced]) {
		// This is what the desktop client does.  There's no state for
		// 'user unmuted and undeafened'.
		if ([user isSelfMuted] && [user isSelfDeafened]) {
			[_delegate serverModel:self userSelfMutedAndDeafened:user];
		} else if ([user isSelfMuted]) {
			[_delegate serverModel:self userSelfMuted:user];
		} else {
			[_delegate serverModel:self userRemovedSelfMute:user];
		}

		[_delegate serverModel:self userSelfMuteDeafenStateChanged:user];
	}
}

- (void) setMuteStateForUser:(MKUser *)user fromMessage:(MPUserState *)msg {
	if ([msg hasMute])
		[user setMuted:[msg mute]];
	if ([msg hasDeaf])
		[user setDeafened:[msg deaf]];
	if ([msg hasSuppress])
		[user setSuppressed:[msg suppress]];

	if (![msg hasSession] && ![msg hasActor]) {
		NSLog(@"Missing session and actor.");
		return;
	}

	MKUser *actor = [self userWithSession:[msg actor]];

	if ([self serverInfoSynced]) {
		if ([msg hasMute] && [msg hasDeaf] && [user isMuted] && [user isDeafened]) {
			[_delegate serverModel:self userMutedAndDeafened:user byUser:actor];
		} else if ([msg hasMute] && [msg hasDeaf] && ![user isMuted] && ![user isDeafened]) {
			[_delegate serverModel:self userUnmutedAndUndeafened:user byUser:actor];
		} else {
			if ([msg hasMute]) {
				if ([user isMuted]) {
					[_delegate serverModel:self userMuted:user byUser:actor];
				} else {
					[_delegate serverModel:self userUnmuted:user byUser:actor];
				}
			}
			if ([msg hasDeaf]) {
				if ([user isDeafened]) {
					[_delegate serverModel:self userDeafened:user byUser:actor];
				} else {
					[_delegate serverModel:self userUndeafened:user byUser:actor];
				}
			}
		}
		if ([msg hasSuppress]) {
			if (user == [self connectedUser]) {
				if ([user isSuppressed]) {
					[_delegate serverModel:self userSuppressed:user byUser:nil];
				} else if ([msg hasChannelId]) {
					[_delegate serverModel:self userUnsuppressed:user byUser:nil];
				}
			} else if (![msg hasChannelId]) {
				if ([user isSuppressed]) {
					[_delegate serverModel:self userSuppressed:user byUser:actor];
				} else {
					[_delegate serverModel:self userUnsuppressed:user byUser:actor];
				}
			}
		}

		[_delegate serverModel:self userMuteStateChanged:user];
	}
}

- (void) setPrioritySpeakerStateForUser:(MKUser *)user to:(BOOL)prioritySpeaker {
	[user setPrioritySpeaker:prioritySpeaker];
	if ([self serverInfoSynced])
		[_delegate serverModel:self userPrioritySpeakerChanged:user];
}

- (void) setHashForUser:(MKUser *)user to:(NSString *)newHash {
	STUB;
}

- (void) setFriendNameForUser:(MKUser *)user to:(NSString *)newFriendName {
	STUB;
}

- (void) setCommentForUser:(MKUser *) to:(NSString *)newComment {
	STUB;
}

- (void) setSeenCommentForUser:(MKUser *)user {
	STUB;
}

//
// Move a user to a channel.
//
- (void) moveUser:(MKUser *)user toChannel:(MKChannel *)chan byUser:(MKUser *)mover {
	MKChannel *currentChannel = [user channel];
	MKChannel *destChannel = chan;

	[currentChannel removeUser:user];
	[destChannel addUser:user];

	[_delegate serverModel:self userMoved:user toChannel:chan byUser:mover];
}

//
// Remove a user from the model.
//
- (void) removeUser:(MKUser *)user {
	STUB;
}

#pragma mark -

- (MKChannel *) rootChannel {
	return _rootChannel;
}

/*
 * Add a channel.
 */
- (MKChannel *) addChannelWithId:(NSUInteger)chanId name:(NSString *)chanName parent:(MKChannel *)parent {

	MKChannel *chan = [[MKChannel alloc] init];
	[chan setChannelId:chanId];
	[chan setChannelName:chanName];
	[chan setParent:parent];

	[channelMapLock writeLock];
	[channelMap setObject:chan forKey:[NSNumber numberWithUnsignedInt:chanId]];
	[channelMapLock unlock];

	[parent addChannel:chan];

	return chan;
}

- (MKChannel *) channelWithId:(NSUInteger)chanId {
	[channelMapLock readLock];
	MKChannel *c = [channelMap objectForKey:[NSNumber numberWithUnsignedInt:chanId]];
	[channelMapLock unlock];
	return c;
}

- (void) renameChannel:(MKChannel *)chan to:(NSString *)newName {
	STUB;
}

- (void) repositionChannel:(MKChannel *)chan to:(NSInteger)pos {
	STUB;
}

- (void) setCommentForChannel:(MKChannel *)chan to:(NSString *)newComment {
	STUB;
}

- (void) moveChannel:(MKChannel *)chan toChannel:(MKChannel *)newParent {
	STUB;
}

- (void) removeChannel:(MKChannel *)chan {
	STUB;
}

- (void) linkChannel:(MKChannel *)chan withChannels:(NSArray *)channelLinks {
	STUB;
}

- (void) unlinkChannel:(MKChannel *)chan fromChannels:(NSArray *)channelLinks {
	STUB;
}

- (void) unlinkAllFromChannel:(MKChannel *)chan {
	STUB;
}

#pragma mark -

- (void) joinChannel:(MKChannel *)chan {
	MPUserState_Builder *userState = [MPUserState builder];
	[userState setSession:[[self connectedUser] session]];
	[userState setChannelId:[chan channelId]];

	NSData *data = [[userState build] data];
	[_connection sendMessageWithType:UserStateMessage data:data];

	NSLog(@"requested to join channel %i", [chan channelId]);
}

@end
