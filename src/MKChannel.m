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
#import <MumbleKit/MKUser.h>

@implementation MKChannel

static NSInteger stringSort(NSString *str1, NSString *str2, void *reverse) {
	if (reverse)
		return [str2 compare:str1];
	else
		return [str1 compare:str2];
}

static NSInteger channelSort(MKChannel *chan1, MKChannel *chan2, void *reverse) {
	if ([chan1 position] != [chan2 position]) {
		return reverse ? ([chan1 position] > [chan2 position]) : ([chan2 position] > [chan1 position]);
	} else {
		return stringSort([chan1 channelName], [chan2 channelName], reverse);
	}
}

- (id) init {
	self = [super init];
	if (self == nil)
		return nil;

	inheritACL = YES;
	channelList = [[NSMutableArray alloc] init];
	userList = [[NSMutableArray alloc] init];
	ACLList = [[NSMutableArray alloc] init];

	return self;
}

- (void) dealloc {
	[channelName release];

	[userList release];
	[channelList release];
	[ACLList release];

	[super dealloc];
}

#pragma mark -

//
// Add a child channel to this channel.
// Returns the index into the channel's subchannel list that the child was inserted at.
//
- (NSUInteger) addChannel:(MKChannel *)newChild {
	[newChild setParent:self];
	[channelList addObject:newChild];
	[channelList sortUsingFunction:channelSort context:nil];
	return [channelList indexOfObject:newChild];
}

//
// Remove a child channel.
//
- (void) removeChannel:(MKChannel *)chan {
	[chan setParent:nil];
	[channelList removeObject:chan];
}

- (void) addUser:(MKUser *)user {
	MKChannel *chan = [user channel];
	[chan removeUser:user];
	[user setChannel:self];
	[userList addObject:user];
}

- (void) removeUser:(MKUser *)user {
	[userList removeObject:user];
}

#pragma mark -

/*
 * Get a list of children of this channel.
 */
- (NSArray *) subchannels {
	return channelList;
}

/*
 * Get a list of the current users residing in this channel.
 */
- (NSArray *) users {
	return userList;
}

#pragma mark -

- (BOOL) linkedToChannel:(MKChannel *)chan {
	for (MKChannel *c in linkedList) {
		if (c == chan) {
			return YES;
		}
	}
	return NO;
}

- (void) linkToChannel:(MKChannel *)chan {
	if ([self linkedToChannel:chan])
		return;

	[linkedList addObject:chan];
	[chan->linkedList addObject:self];
}

- (void) unlinkFromChannel:(MKChannel *)chan {
	[linkedList removeObject:chan];
	[chan->linkedList removeObject:self];
}

- (void) unlinkAll {
	for (MKChannel *chan in linkedList) {
		[self unlinkFromChannel:chan];
	}
}

#pragma mark -

- (void) setChannelName:(NSString *)name {
	[channelName release];
	channelName = [name copy];
}

- (NSString *) channelName {
	return channelName;
}

- (void) setParent:(MKChannel *)chan {
	channelParent = chan;
}

- (MKChannel *) parent {
	return channelParent;
}

- (void) setChannelId:(NSUInteger)chanId {
	channelId = chanId;
}

- (NSUInteger) channelId {
	return channelId;
}

- (void) setTemporary:(BOOL)flag {
	temporary = flag;
}

- (BOOL) temporary {
	return temporary;
}

- (NSInteger) position {
	return position;
}

- (void) setPosition:(NSInteger)pos {
	position = pos;
}

@end
