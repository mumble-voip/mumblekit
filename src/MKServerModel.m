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
#import <MumbleKit/MKAudio.h>
#import "MKPacketDataStream.h"
#import "MKUtils.h"
#import "Mumble.pb.h"

#import <MumbleKit/MKChannel.h>
#import "MKChannelPrivate.h"

#import <MumbleKit/MKUser.h>
#import "MKUserPrivate.h"

#import "MulticastDelegate.h"

@interface MKServerModel () {
    MKConnection                              *_connection;
    MKChannel                                 *_rootChannel;
    MKUser                                    *_connectedUser;
    NSMutableDictionary                       *_userMap;
    NSMutableDictionary                       *_channelMap;
    MulticastDelegate<MKServerModelDelegate>  *_delegate;    
}

// Notifications
- (void) notificationUserTalkStateChanged:(NSNotification *)notification;

// Internal user operations
- (MKUser *) internalAddUserWithSession:(NSUInteger)userSession name:(NSString *)userName;
- (void) internalMoveUser:(MKUser *)user toChannel:(MKChannel *)chan byUser:(MKUser *)actor;
- (void) internalSetSelfMuteDeafenStateForUser:(MKUser *)user fromMessage:(MPUserState *)msg;
- (void) internalSetMuteStateForUser:(MKUser *)user fromMessage:(MPUserState *)msg;
- (void) internalSetPrioritySpeakerStateForUser:(MKUser *)user to:(BOOL)prioritySpeaker;
- (void) internalSetRecordingStateForUser:(MKUser *)user to:(BOOL)flag;
- (void) internalRenameUser:(MKUser *)user to:(NSString *)name;
- (void) internalSetCommentForUser:(MKUser *)user to:(NSString *)comment;
- (void) internalSetCommentHashForUser:(MKUser *)user to:(NSData *)hash;
- (void) internalSetTextureForUser:(MKUser *)user to:(NSData *)texture;
- (void) internalSetTextureHashForUser:(MKUser *)user to:(NSData *)hash;
- (void) internalRemoveUserWithMessage:(MPUserRemove *)msg;

// Internal channel operations
- (MKChannel *) internalAddChannelWithId:(NSUInteger)chanId name:(NSString *)chanName parent:(MKChannel *)parent;
- (void) internalSetLinks:(PBArray *)links forChannel:(MKChannel *)chan;
- (void) internalAddLinks:(PBArray *)links toChannel:(MKChannel *)chan;
- (void) internalRemoveLinks:(PBArray *)links fromChannel:(MKChannel *)chan;
- (void) internalRenameChannel:(MKChannel *)chan to:(NSString *)newName;
- (void) internalRepositionChannel:(MKChannel *)chan to:(NSInteger)pos;
- (void) internalSetDescriptionForChannel:(MKChannel *)chan to:(NSString *)desc;
- (void) internalSetDescriptionHashForChannel:(MKChannel *)chan to:(NSData *)hash;
- (void) internalMoveChannel:(MKChannel *)chan toChannel:(MKChannel *)newParent;
- (void) internalRemoveChannel:(MKChannel *)chan;

- (void) removeAllUsersFromChannel:(MKChannel *)channel;
- (void) removeAllChannels;
@end

@implementation MKServerModel

- (id) initWithConnection:(MKConnection *)conn {
    if (self = [super init]) {
        _delegate = [[MulticastDelegate alloc] init];

        _userMap = [[NSMutableDictionary alloc] init];
        _channelMap = [[NSMutableDictionary alloc] init];

        _rootChannel = [[MKChannel alloc] init];
        [_rootChannel setChannelId:0];
        [_rootChannel setChannelName:@"Root"];

        [_channelMap setObject:_rootChannel forKey:[NSNumber numberWithUnsignedInteger:0]];

        _connection = [conn retain];
        [_connection setMessageHandler:self];

        // Listens to notifications form MKAudioOutput and MKAudioInput
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(notificationUserTalkStateChanged:) name:@"MKAudioUserTalkStateChanged" object:nil];
    }
    return self;
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"MKAudioUserTalkStateChanged" object:nil];

    [_connection setMessageHandler:nil];

    [_delegate release];

    [self removeAllUsersFromChannel:_rootChannel];
    [_userMap release];

    [self removeAllChannels];
    [_channelMap release];

    [_rootChannel release];

    [_connection release];

    [super dealloc];
}

- (NSString *) hostname {
    return [_connection hostname];
}

- (NSInteger) port {
    return [_connection port];
}

// Remove all users from their channels.
// Must be called before removing channels.
- (void) removeAllUsersFromChannel:(MKChannel *)channel {
    [channel removeAllUsers];
    for (MKChannel *subchannel in [channel channels]) {
        [self removeAllUsersFromChannel:subchannel];
    }
}

// Removes all channels, correctly unchaining the mess. (Subchannels retain their parents,
// and parent channels retain their children implicitly by storing them in an NSArray).
- (void) removeAllChannels {
    int nparents;
    do {
        nparents = 0;
        for (MKChannel *channel in _channelMap.allValues) {
            if ([channel parent] != nil) {
                if ([[channel channels] count] > 0) {
                    ++nparents;
                } else {
                    [channel removeFromParent];
                }
            }
        }
    } while (nparents > 0);
}

- (void) addDelegate:(id)delegate {
    [(MulticastDelegate *)_delegate addDelegate:delegate];
}

- (void) removeDelegate:(id)delegate {
    [(MulticastDelegate *)_delegate removeDelegate:delegate];
}

#pragma mark -
#pragma mark MKConnection delegate

- (void) connectionClosed:(MKConnection *)conn {
    [_delegate serverModelDisconnected:self];
}

#pragma mark -
#pragma mark MKMessageHandler delegate

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
            user = [self internalAddUserWithSession:session name:[msg name]];
            newUser = YES;
        } else {
            return;
        }
    }

    if ([msg hasUserId]) {
        [user setUserId:[msg userId]];
    }
    if ([msg hasCertHash]) {
        [user setUserHash:[msg certHash]];
    }

    // The user just connected. Tell our delegate listeners.
    if (newUser && _connectedUser) {
        [_delegate serverModel:self userJoined:user];
    }

    if ([msg hasRecording]) {
        [self internalSetRecordingStateForUser:user to:[msg recording]];
    }

    if ([msg hasSelfDeaf] || [msg hasSelfMute]) {
        [self internalSetSelfMuteDeafenStateForUser:user fromMessage:msg];
    }

    if ([msg hasPrioritySpeaker]) {
        [self internalSetPrioritySpeakerStateForUser:user to:[msg prioritySpeaker]];
    }

    if ([msg hasDeaf] || [msg hasMute] || [msg hasSuppress]) {
        [self internalSetMuteStateForUser:user fromMessage:msg];
    }

    if ([msg hasChannelId]) {
        MKChannel *chan = [self channelWithId:[msg channelId]];
        MKChannel *oldChan = [user channel];
        MKUser *actor = nil;
        if ([msg hasActor]) {
            actor = [self userWithSession:[msg actor]];
        }
        if (chan != oldChan) {
            [self internalMoveUser:user toChannel:chan fromChannel:oldChan byUser:actor];
        }

    // The user has no channel id set, and is a newly connected user.
    // This means the user's residing in the root channel.
    } else if (newUser) {
        [self internalMoveUser:user toChannel:_rootChannel fromChannel:nil byUser:nil];
    }

    if ([msg hasName]) {
        [self internalRenameUser:user to:[msg name]];
    }

    if ([msg hasTexture]) {
        [self internalSetTextureForUser:user to:[msg texture]];
    }

    if ([msg hasTextureHash]) {
        [self internalSetTextureHashForUser:user to:[msg textureHash]];
    }

    if ([msg hasComment]) {
        [self internalSetCommentForUser:user to:[msg comment]];
    }

    if ([msg hasCommentHash]) {
        [self internalSetCommentHashForUser:user to:[msg commentHash]];
    }
}

- (void) connection:(MKConnection *)conn handleUserRemoveMessage:(MPUserRemove *)msg {
    if (! [msg hasSession]) {
        return;
    }

    [self internalRemoveUserWithMessage:msg];
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

    if ([[msg links] count] > 0) {
        [self internalSetLinks:[msg links] forChannel:chan];
    }

    if ([[msg linksAdd] count] > 0) {
        [self internalAddLinks:[msg linksAdd] toChannel:chan];
    }

    if ([[msg linksRemove] count] > 0) {
        [self internalRemoveLinks:[msg linksRemove] fromChannel:chan];
    }

    if (newChannel && _connectedUser) {
        [_delegate serverModel:self channelAdded:chan];
    }
}

- (void) connection:(MKConnection *)conn handleChannelRemoveMessage:(MPChannelRemove *)msg {
    if (! [msg hasChannelId]) {
        return;
    }

    MKChannel *chan = [self channelWithId:[msg channelId]];
    if (chan && [chan channelId] != 0) {
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

- (void) connection:(MKConnection *)conn handleContextActionModifyMessage: (MPContextActionModify *)add {
}

- (void) connection:(MKConnection *)conn handleUserListMessage: (MPUserList *)msg {
}

- (void) connection:(MKConnection *)conn handleVoiceTargetMessage: (MPVoiceTarget *)msg {
}

- (void) connection:(MKConnection *)conn handlePermissionQueryMessage: (MPPermissionQuery *)msg {
}

#pragma mark -
#pragma mark MKAudio notification

- (void) notificationUserTalkStateChanged:(NSNotification *)notification {
    NSDictionary *infoDict = [notification object];
    NSNumber *session = [infoDict objectForKey:@"userSession"];
    NSNumber *talkState = [infoDict objectForKey:@"talkState"];
    MKUser *user = nil;
    
    if (talkState) {
        // An infoDict with a missing userSession means that our own talkState changed.
        if (session == nil) {
            user = _connectedUser;
        } else {
            user = [self userWithSession:[session unsignedIntegerValue]];
        }
        [user setTalkState:(MKTalkState)[talkState unsignedIntValue]];
    }
    if (_connectedUser && user) {
        [_delegate serverModel:self userTalkStateChanged:user];
    }
}

#pragma mark -
#pragma mark Internal handlers for state change messages

- (MKUser *) internalAddUserWithSession:(NSUInteger)userSession name:(NSString *)userName {
    MKUser *user = [[MKUser alloc] init];
    [user setSession:userSession];
    [user setUserName:userName];
    [_userMap setObject:user forKey:[NSNumber numberWithUnsignedInt:userSession]];
    [user release];

    return user;
}

- (void) internalRenameUser:(MKUser *)user to:(NSString *)newName {
    [user setUserName:newName];

    if (_connectedUser) {
        [_delegate serverModel:self userRenamed:user];
    }
}

- (void) internalSetRecordingStateForUser:(MKUser *)user to:(BOOL)flag {
    [user setRecording:flag];

    if (_connectedUser) {
        [_delegate serverModel:self userRecordingStateChanged:user];
    }
}

- (void) internalSetSelfMuteDeafenStateForUser:(MKUser *)user fromMessage:(MPUserState *)msg {
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

- (void) internalSetMuteStateForUser:(MKUser *)user fromMessage:(MPUserState *)msg {
    if ([msg hasMute])
        [user setMuted:[msg mute]];
    if ([msg hasDeaf])
        [user setDeafened:[msg deaf]];
    if ([msg hasSuppress])
        [user setSuppressed:[msg suppress]];

    if (![msg hasSession] && ![msg hasActor]) {
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

- (void) internalSetPrioritySpeakerStateForUser:(MKUser *)user to:(BOOL)prioritySpeaker {
    [user setPrioritySpeaker:prioritySpeaker];
    if (_connectedUser)
        [_delegate serverModel:self userPrioritySpeakerChanged:user];
}

- (void) internalSetCommentForUser:(MKUser *)user to:(NSString *)comment {
    [user setComment:comment];

    if (_connectedUser) {
        [_delegate serverModel:self userCommentChanged:user];
    }
}

- (void) internalSetCommentHashForUser:(MKUser *)user to:(NSData *)hash {
    [user setCommentHash:hash];

    if (_connectedUser) {
        [_delegate serverModel:self userCommentChanged:user];
    }
}

- (void) internalSetTextureForUser:(MKUser *)user to:(NSData *)texture {
    [user setTexture:texture];

    if (_connectedUser) {
        [_delegate serverModel:self userTextureChanged:user];
    }
}

- (void) internalSetTextureHashForUser:(MKUser *)user to:(NSData *)hash {
    [user setTextureHash:hash];

    if (_connectedUser) {
        [_delegate serverModel:self userTextureChanged:user];
    }
}

- (void) internalMoveUser:(MKUser *)user toChannel:(MKChannel *)chan fromChannel:(MKChannel *)prevChan byUser:(MKUser *)mover {
    [chan addUser:user];

    if (_connectedUser) {
        [_delegate serverModel:self userMoved:user toChannel:chan byUser:mover];
        [_delegate serverModel:self userMoved:user toChannel:chan fromChannel:prevChan byUser:mover];
    }
}

- (void) internalRemoveUserWithMessage:(MPUserRemove *)msg {
    MKUser *user = [self userWithSession:[msg session]];
    MKUser *actor = [msg hasActor] ? [self userWithSession:[msg actor]] : nil;
    BOOL ban = [msg hasBan] ? [msg ban] : NO;
    NSString *reason = [msg hasReason] ? [msg reason] : nil;

    if (_connectedUser) {
        if (actor) {
            if (ban) {
                [_delegate serverModel:self userBanned:user byUser:actor forReason:reason];
            } else {
                [_delegate serverModel:self userKicked:user byUser:actor forReason:reason];
            }
        } else {
            [_delegate serverModel:self userDisconnected:user];
        }

        [_delegate serverModel:self userLeft:user];
    }

    [_userMap removeObjectForKey:[NSNumber numberWithUnsignedInteger:[msg session]]];
    [user removeFromChannel];
}

#pragma mark -

// Add a new channel to our model
- (MKChannel *) internalAddChannelWithId:(NSUInteger)chanId name:(NSString *)chanName parent:(MKChannel *)parent {
    MKChannel *chan = [[MKChannel alloc] init];
    [chan setChannelId:chanId];
    [chan setChannelName:chanName];
    [chan setParent:parent];

    [_channelMap setObject:chan forKey:[NSNumber numberWithUnsignedInt:chanId]];
    [parent addChannel:chan];
    [chan release];

    return chan;
}

// Handle the 'links' list from a ChannelState message
- (void) internalSetLinks:(PBArray *)links forChannel:(MKChannel *)chan {
    [chan unlinkAll];

    int numLinks = [links count];
    NSMutableArray *channels = [[NSMutableArray alloc] initWithCapacity:numLinks];
    for (int i = 0; i < numLinks; i++) {
        MKChannel *linkedChan = [self channelWithId:(NSUInteger)[links uint32AtIndex:i]];
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
- (void) internalAddLinks:(PBArray *)links toChannel:(MKChannel *)chan {
    int i, numLinks = [links count];
    NSMutableArray *channels = [[NSMutableArray alloc] initWithCapacity:numLinks];
    for (i = 0; i < numLinks; i++) {
        MKChannel *linkedChan = [self channelWithId:(NSUInteger)[links uint32AtIndex:i]];
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
- (void) internalRemoveLinks:(PBArray *)links fromChannel:(MKChannel *)chan {
    int i, numLinks = [links count];
    NSMutableArray *channels = [[NSMutableArray alloc] initWithCapacity:numLinks];
    for (i = 0; i < numLinks; i++) {
        MKChannel *linkedChan = [self channelWithId:(NSUInteger)[links uint32AtIndex:i]];
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

    [_channelMap removeObjectForKey:[NSNumber numberWithUnsignedInt:[chan channelId]]];
    [chan removeFromParent];
}

#pragma mark -
#pragma mark Channel operations

- (MKChannel *) rootChannel {
    return _rootChannel;
}

- (MKUser *) connectedUser {
    return _connectedUser;
}

- (MKUser *) userWithSession:(NSUInteger)session {
    return [_userMap objectForKey:[NSNumber numberWithUnsignedInt:session]];
}

- (MKUser *) userWithHash:(NSString *)hash {
    return nil;
}

// Lookup a channel by its channelId.
- (MKChannel *) channelWithId:(NSUInteger)channelId {
    return [_channelMap objectForKey:[NSNumber numberWithUnsignedInt:channelId]];
}

// Request to join a channel.
- (void) joinChannel:(MKChannel *)chan {
    MPUserState_Builder *userState = [MPUserState builder];
    [userState setSession:[[self connectedUser] session]];
    [userState setChannelId:[chan channelId]];

    NSData *data = [[userState build] data];
    [_connection sendMessageWithType:UserStateMessage data:data];
}

#pragma mark -
#pragma mark Server operations

- (void) setAccessTokens:(NSArray *)tokens {
    MPAuthenticate_Builder *authenticate = [MPAuthenticate builder];
    [authenticate setTokensArray:tokens];

    NSData *data = [[authenticate build] data];
    [_connection sendMessageWithType:AuthenticateMessage data:data];
}

@end
