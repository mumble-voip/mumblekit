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

#import <MumbleKit/MKChannel.h>
#import "MKChannelPrivate.h"

#import <MumbleKit/MKUser.h>
#import "MKUserPrivate.h"

#import "MulticastDelegate.h"

#define STUB \
	NSLog(@"%@: %s", [self class], __FUNCTION__)

@interface MKServerModel (InlinePrivate)

- (void) setSelfMuteDeafenStateForUser:(MKUser *)user fromMessage:(MPUserState *)msg;
- (void) setMuteStateForUser:(MKUser *)user fromMessage:(MPUserState *)msg;
- (void) setPrioritySpeakerStateForUser:(MKUser *)user to:(BOOL)prioritySpeaker;

- (MKUser *) addUserWithSession:(NSUInteger)userSession name:(NSString *)userName;
- (void) renameUser:(MKUser *)user to:(NSString *)newName;
- (void) setIdForUser:(MKUser *)user to:(NSUInteger)newId;
- (void) setHashForUser:(MKUser *)user to:(NSString *)newHash;
- (void) setFriendNameForUser:(MKUser *)user to:(NSString *)newFriendName;
- (void) setCommentForUser:(MKUser *) to:(NSString *)newComment;
- (void) setSeenCommentForUser:(MKUser *)user;
- (void) removeUser:(MKUser *)user;

// Internal channel operations
- (MKChannel *) internalAddChannelWithId:(NSUInteger)chanId name:(NSString *)chanName parent:(MKChannel *)parent;
- (void) internalSetLinks:(NSArray *)links forChannel:(MKChannel *)chan;
- (void) internalAddLinks:(NSArray *)links toChannel:(MKChannel *)chan;
- (void) internalRemoveLinks:(NSArray *)links fromChannel:(MKChannel *)chan;
- (void) internalRenameChannel:(MKChannel *)chan to:(NSString *)newName;
- (void) internalRepositionChannel:(MKChannel *)chan to:(NSInteger)pos;
- (void) internalSetDescriptionForChannel:(MKChannel *)chan to:(NSString *)desc;
- (void) internalSetDescriptionHashForChannel:(MKChannel *)chan to:(NSData *)hash;
- (void) internalMoveChannel:(MKChannel *)chan toChannel:(MKChannel *)newParent;
- (void) internalRemoveChannel:(MKChannel *)chan;

@end

@implementation MKServerModel

- (id) initWithConnection:(MKConnection *)conn {
	if (self = [super init]) {
		_delegate = [[MulticastDelegate alloc] init];

		_userMapLock = [[MKReadWriteLock alloc] init];
		_userMap = [[NSMutableDictionary alloc] init];

		_channelMapLock = [[MKReadWriteLock alloc] init];
		_channelMap = [[NSMutableDictionary alloc] init];

		_rootChannel = [[MKChannel alloc] init];
		[_rootChannel setChannelId:0];
		[_rootChannel setChannelName:@"Root"];

		[_channelMap setObject:_rootChannel forKey:[NSNumber numberWithUnsignedInt:0]];

		_connection = conn;

		[_connection setMessageHandler:self];
		[_connection setVoiceDataHandler:self];
	}
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

#pragma mark -
#pragma mark MKMessageHandler delegate

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
	if (newUser && _connectedUser) {
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
			chan = [self internalAddChannelWithId:[msg channelId] name:[msg name] parent:parent];
			if ([msg hasTemporary]) {
				[chan setTemporary:[msg temporary]];
			}
		} else {
			return;
		}
	}

	if (parent) {
		[self internalMoveChannel:chan toChannel:parent];
	}

	if ([msg hasName]) {
		[self internalRenameChannel:chan to:[msg name]];
	}

	if ([msg hasDescription]) {
		[self internalSetDescriptionForChannel:chan to:[msg description]];
	}

	if ([msg hasDescriptionHash]) {
		[self internalSetDescriptionHashForChannel:chan to:[msg descriptionHash]];
	}

	if ([msg hasPosition]) {
		[self internalRepositionChannel:chan to:[msg position]];
	}

	if ([[msg linksList] count] > 0) {
		[self internalSetLinks:[msg linksList] forChannel:chan];
	}

	if ([[msg linksAddList] count] > 0) {
		[self internalAddLinks:[msg linksAddList] toChannel:chan];
	}

	if ([[msg linksRemoveList] count] > 0) {
		[self internalRemoveLinks:[msg linksRemoveList] fromChannel:chan];
	}

	if (newChannel && _connectedUser) {
		[_delegate serverModel:self channelAdded:chan];
	}
}

- (void) connection:(MKConnection *) handleChannelRemoveMessage:(MPChannelRemove *)msg {
	if (! [msg hasChannelId]) {
		return;
	}

	MKChannel *chan = [self channelWithId:[msg channelId]];
	if (chan && [chan channelId] != 0 && _connectedUser) {
		[self internalRemoveChannel:chan];
	}
}

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

#pragma mark -
#pragma mark MKVoiceDataHandler delegate

- (void) connection:(MKConnection *)conn session:(NSUInteger)session sequence:(NSUInteger)seq type:(MKUDPMessageType)msgType voiceData:(NSMutableData *)data {
	MKUser *speakingUser = [self userWithSession:session];
	[[MKAudio sharedAudio] addFrameToBufferWithUser:speakingUser data:data sequence:seq type:msgType];
	[data release];
}

#pragma mark -

- (MKUser *) connectedUser {
	return _connectedUser;
}

- (MKUser *) addUserWithSession:(NSUInteger)userSession name:(NSString *)userName {
	MKUser *user = [[MKUser alloc] init];
	[user setSession:userSession];
	[user setUserName:userName];

	[_userMapLock writeLock];
	[_userMap setObject:user forKey:[NSNumber numberWithUnsignedInt:userSession]];
	[_userMapLock unlock];

	return user;
}

- (MKUser *) userWithSession:(NSUInteger)session {
	[_userMapLock readLock];
	MKUser *u = [_userMap objectForKey:[NSNumber numberWithUnsignedInt:session]];
	[_userMapLock unlock];
	return u;
}

- (MKUser *) userWithHash:(NSString *)hash {
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

	if (_connectedUser) {
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

	if (_connectedUser) {
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
	if (_connectedUser)
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

- (void) moveUser:(MKUser *)user toChannel:(MKChannel *)chan byUser:(MKUser *)mover {
	MKChannel *currentChannel = [user channel];
	MKChannel *destChannel = chan;

	[currentChannel removeUser:user];
	[destChannel addUser:user];

	[_delegate serverModel:self userMoved:user toChannel:chan byUser:mover];
}

- (void) removeUser:(MKUser *)user {
	STUB;
}

#pragma mark -

- (MKChannel *) rootChannel {
	return _rootChannel;
}

// Add a new channel to our model
- (MKChannel *) internalAddChannelWithId:(NSUInteger)chanId name:(NSString *)chanName parent:(MKChannel *)parent {
	MKChannel *chan = [[MKChannel alloc] init];
	[chan setChannelId:chanId];
	[chan setChannelName:chanName];
	[chan setParent:parent];

	[_channelMapLock writeLock];
	[_channelMap setObject:chan forKey:[NSNumber numberWithUnsignedInt:chanId]];
	[_channelMapLock unlock];

	[parent addChannel:chan];

	return chan;
}

// Handle the 'links' list from a ChannelState message
- (void) internalSetLinks:(NSArray *)links forChannel:(MKChannel *)chan {
	[chan unlinkAll];
	NSMutableArray *channels = [[NSMutableArray alloc] initWithCapacity:[links count]];
	for (NSNumber *number in links) {
		NSUInteger channelId = [number unsignedIntegerValue];
		MKChannel *linkedChan = [self channelWithId:channelId];
		[channels addObject:linkedChan];

		[chan linkToChannel:linkedChan];
	}

	if (_connectedUser) {
		[_delegate serverModel:self linksSet:channels forChannel:chan];
		[_delegate serverModel:self linksChangedForChannel:chan];
	}

	[channels release];
}

// Handle the 'links_add' list from a ChannelState message
- (void) internalAddLinks:(NSArray *)links toChannel:(MKChannel *)chan {
	NSMutableArray *channels = [[NSMutableArray alloc] initWithCapacity:[links count]];
	for (NSNumber *number in links) {
		NSUInteger channelId = [number unsignedIntegerValue];
		MKChannel *linkedChan = [self channelWithId:channelId];
		[channels addObject:linkedChan];

		[chan linkToChannel:linkedChan];
	}

	if (_connectedUser) {
		[_delegate serverModel:self linksAdded:channels toChannel:chan];
		[_delegate serverModel:self linksChangedForChannel:chan];
	}

	[channels release];
}

// Handle the 'links_remove' list from a ChannelState message
- (void) internalRemoveLinks:(NSArray *)links fromChannel:(MKChannel *)chan {
	NSMutableArray *channels = [[NSMutableArray alloc] initWithCapacity:[links count]];
	for (NSNumber *number in links) {
		NSUInteger channelId = [number unsignedIntegerValue];
		MKChannel *linkedChan = [self channelWithId:channelId];
		[channels addObject:linkedChan];

		[chan unlinkFromChannel:chan];
	}

	if (_connectedUser) {
		[_delegate serverModel:self linksRemoved:channels fromChannel:chan];
		[_delegate serverModel:self linksChangedForChannel:chan];
	}

	[channels release];
}


// Handle a channel rename (from a ChannelState message)
- (void) internalRenameChannel:(MKChannel *)chan to:(NSString *)newName {
	[chan setChannelName:newName];

	if (_connectedUser) {
		[_delegate serverModel:self channelRenamed:chan];
	}
}

// Handle a channel position change (from a ChannelState message)
- (void) internalRepositionChannel:(MKChannel *)chan to:(NSInteger)pos {
	[chan setPosition:pos];

	if (_connectedUser) {
		[_delegate serverModel:self channelPositionChanged:chan];
	}
}

// Handle a description set in a ChannelState message.
- (void) internalSetDescriptionForChannel:(MKChannel *)chan to:(NSString *)desc {
	[chan setChannelDescription:desc];

	if (_connectedUser) {
		[_delegate serverModel:self channelDescriptionChanged:chan];
	}
}

// Handle a description hash set in a ChannelState message.
- (void) internalSetDescriptionHashForChannel:(MKChannel *)chan to:(NSData *)hash {
	[chan setChannelDescriptionHash:hash];

	if (_connectedUser) {
		[_delegate serverModel:self channelDescriptionChanged:chan];
	}
}

// Handle a channel move (from a ChannelState message)
- (void) internalMoveChannel:(MKChannel *)chan toChannel:(MKChannel *)newParent {
	MKChannel *p = newParent;

	// Don't allow channel to be moved into itself.
	while (p) {
		if (p == chan)
			return;
		p = [p parent];
	}

	[chan setParent:newParent];

	if (_connectedUser) {
		[_delegate serverModel:self channelMoved:(MKChannel *)chan];
	}
}

// Handle a channel remove (from a ChannelState message)
- (void) internalRemoveChannel:(MKChannel *)chan {
	if (_connectedUser) {
		[_delegate serverModel:self channelRemoved:chan];
	}

	[_channelMapLock writeLock];
	[_channelMap removeObjectForKey:[NSNumber numberWithInteger:[chan channelId]]];
	[_channelMapLock unlock];

	// todo(mkrautz): Remove model object also.
}

#pragma mark -
#pragma mark Channel operations

// Lookup a channel by its channelId.
- (MKChannel *) channelWithId:(NSUInteger)channelId {
	[_channelMapLock readLock];
	MKChannel *c = [_channelMap objectForKey:[NSNumber numberWithUnsignedInt:channelId]];
	[_channelMapLock unlock];
	return c;
}

// Request to join a channel.
- (void) joinChannel:(MKChannel *)chan {
	MPUserState_Builder *userState = [MPUserState builder];
	[userState setSession:[[self connectedUser] session]];
	[userState setChannelId:[chan channelId]];

	NSData *data = [[userState build] data];
	[_connection sendMessageWithType:UserStateMessage data:data];
}

@end
