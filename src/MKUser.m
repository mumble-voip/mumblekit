// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKUser.h>
#import "MKUserPrivate.h"

#import <MumbleKit/MKChannel.h>
#import "MKChannelPrivate.h"

@interface MKUser () {
    BOOL         _muted;
    BOOL         _deafened;
    BOOL         _suppressed;
    BOOL         _localMuted;
    BOOL         _selfMuted;
    BOOL         _selfDeafened;
    BOOL         _friend;
    BOOL         _prioritySpeaker;
    BOOL         _recording;
    MKTalkState  _talkState;
    NSUInteger   _session;
    NSInteger    _userId;
    NSString     *_userHash;
    NSString     *_username;
    MKChannel    *_channel;
    NSString     *_comment;
    NSData       *_commentHash;
    NSData       *_texture;
    NSData       *_textureHash;
}
@end

@implementation MKUser

- (id) init {
    if (self = [super init]) {
        _userId = -1;
    }
    return self;
}
- (void) dealloc {
    [_channel removeUser:self];
    [_username release];

    [super dealloc];
}

#pragma mark -

- (void) removeFromChannel {
    [_channel removeUser:self];
}

- (void) setSession:(NSUInteger)session {
    _session = session;
}

- (NSUInteger) session {
    return _session;
}

- (void) setUserName:(NSString *)name {
    [_username release];
    _username = [name copy];
}

- (NSString *) userName {
    return _username;
}

- (void) setUserId:(NSInteger)userId {
    _userId = userId;
}

- (NSInteger) userId {
    return _userId;
}

- (void) setUserHash:(NSString *)hash {
    [_userHash release];
    _userHash = [hash copy];
}

- (NSString *) userHash {
    return _userHash;
}

- (void) setTalkState:(MKTalkState)val {
    _talkState = val;
}

- (MKTalkState) talkState {
    return _talkState;
}

- (BOOL) isAuthenticated {
    return _userId >= 0;
}

- (void) setFriend:(BOOL)flag {
    _friend = flag;
}

- (BOOL) isFriend {
    return _friend;
}

- (void) setMuted:(BOOL)flag {
    _muted = flag;
    if (! flag)
        _deafened = NO;
}

- (BOOL) isMuted {
    return _muted;
}

- (void) setDeafened:(BOOL)flag {
    _deafened = flag;
    if (flag)
        _muted = YES;
}

- (BOOL) isDeafened {
    return _deafened;
}

- (void) setSuppressed:(BOOL)flag {
    _suppressed = flag;
}

- (BOOL) isSuppressed {
    return _suppressed;
}

- (void) setLocalMuted:(BOOL)flag {
    _localMuted = flag;
}

- (BOOL) isLocalMuted {
    return _localMuted;
}

- (void) setSelfMuted:(BOOL)flag {
    _selfMuted = flag;
    if (! flag)
        _selfDeafened = NO;
}

- (BOOL) isSelfMuted {
    return _selfMuted;
}

- (void) setSelfDeafened:(BOOL)flag {
    _selfDeafened = flag;
    if (flag)
        _selfMuted = YES;
}

- (BOOL) isSelfDeafened {
    return _selfDeafened;
}

- (void) setPrioritySpeaker:(BOOL)flag {
    _prioritySpeaker = flag;
}

- (BOOL) isPrioritySpeaker {
    return _prioritySpeaker;
}

- (void) setRecording:(BOOL)flag {
    _recording = flag;
}

- (BOOL) isRecording {
    return _recording;
}

- (void) setChannel:(MKChannel *)chan {
    _channel = chan;
}

- (MKChannel *) channel {
    return _channel;
}

- (void) setCommentHash:(NSData *)hash {
    [_commentHash release];
    _commentHash = [hash copy];
}

- (NSData *) commentHash {
    return _commentHash;
}

- (void) setComment:(NSString *)comment {
    [_comment release];
    _comment = [comment copy];
}

- (NSString *) comment {
    return _comment;
}

- (void) setTextureHash:(NSData *)hash {
    [_textureHash release];
    _textureHash = [hash copy];
}

- (NSData *) textureHash {
    return _textureHash;
}

- (void) setTexture:(NSData *)texture {
    [_texture release];
    _texture = [texture copy];
}

- (NSData *) texture {
    return _texture;
}

@end
