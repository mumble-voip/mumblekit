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
	NSAssert([_users count] == 0, @"Attempt to remove channel with users in it");
	NSAssert([_channels count] == 0, @"Attempt to remove channel with subchannels.");
	[_channelName release];
	[_channels release];
	[_users release];
	[_linked release];
	[super dealloc];
}

#pragma mark -

- (void) removeFromParent {
	[_parent removeChannel:self];
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
	_parent = chan;
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
