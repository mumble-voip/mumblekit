// Copyright 2010-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKChannel.h>
#import "MKChannelPrivate.h"

#import <MumbleKit/MKUser.h>
#import "MKUserPrivate.h"

@interface MKChannel () {
    MKChannel        *_parent;
    NSUInteger       _channelId;
    NSString         *_channelName;
    BOOL             _temporary;
    NSInteger        _position;
    NSMutableArray   *_channels;
    NSMutableArray   *_users;
    NSMutableArray   *_linked;
    NSData           *_channelDescriptionHash;
    NSString         *_channelDescription;
}
@end

@implementation MKChannel

- (id) init {
    if (self = [super init]) {
        _channels = [[NSMutableArray alloc] init];
        _users = [[NSMutableArray alloc] init];
        _linked = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void) dealloc {
    [self removeFromParent];
    [self removeAllUsers];

    [_channelName release];

    [_channels release];
    [_users release];
    [_linked release];

    [super dealloc];
}

#pragma mark -

- (void) removeFromParent {
    [_parent removeChannel:self];
    [_parent release];
    _parent = nil;
}

- (void) addChannel:(MKChannel *)child {
    [child setParent:self];
    [_channels addObject:child];
}

- (void) removeChannel:(MKChannel *)child {
    [child setParent:nil];
    [_channels removeObject:child];
}

- (void) addUser:(MKUser *)user {
    MKChannel *chan = [user channel];
    [chan removeUser:user];
    [user setChannel:self];
    [_users addObject:user];
}

- (void) removeUser:(MKUser *)user {
    [user setChannel:nil];
    [_users removeObject:user];
}

- (void) removeAllUsers {
    for (MKUser *user in _users) {
        [user setChannel:nil];
    }
    [_users removeAllObjects];
}

- (NSArray *) channels {
    return _channels;
}

- (NSArray *) users {
    return _users;
}

- (NSArray *) linkedChannels {
    return _linked;
}

- (BOOL) isLinkedToChannel:(MKChannel*)chan {
    return [_linked containsObject:chan];
}

- (void) linkToChannel:(MKChannel *)chan {
    if ([self isLinkedToChannel:chan])
        return;

    [_linked addObject:chan];
    [chan linkToChannel:self];
}

- (void) unlinkFromChannel:(MKChannel *)chan {
    if ([self isLinkedToChannel:chan]) {
        [_linked removeObject:chan];
        [chan unlinkFromChannel:self];
    }
}

- (void) unlinkAll {
    NSArray *linkedChannels = [[_linked copy] autorelease];
    for (MKChannel *chan in linkedChannels) {
        [self unlinkFromChannel:chan];
    }
}

- (void) setChannelName:(NSString *)name {
    [_channelName release];
    _channelName = [name copy];
}

- (NSString *) channelName {
    return _channelName;
}

- (void) setParent:(MKChannel *)chan {
    _parent = [chan retain];
}

- (MKChannel *) parent {
    return _parent;
}

- (void) setChannelId:(NSUInteger)channelId {
    _channelId = channelId;
}

- (NSUInteger) channelId {
    return _channelId;
}

- (void) setTemporary:(BOOL)flag {
    _temporary = flag;
}

- (BOOL) isTemporary {
    return _temporary;
}

- (void) setPosition:(NSInteger)pos {
    _position = pos;
}

- (NSInteger) position {
    return _position;
}

- (void) setChannelDescriptionHash:(NSData *)hash {
    [_channelDescriptionHash release];
    _channelDescriptionHash = [hash copy];
}

- (NSData *) channelDescriptionHash {
    return _channelDescriptionHash;
}

- (void) setChannelDescription:(NSString *)desc {
    [_channelDescription release];
    _channelDescription = [desc copy];
}

- (NSString *) channelDescription {
    return _channelDescription;
}

@end
