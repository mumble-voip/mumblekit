/* Copyright (C) 2009-2010 Mikkel Krautz <mikkel@krautz.dk>

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
#import <MumbleKit/MKReadWriteLock.h>
#import <MumbleKit/MKChannel.h>

@implementation MKUser

- (id) init {
	if (self = [super init]) {
		_userId = -1;
	}
	return self;
}

- (void) dealloc {
	[_username release];
	[super dealloc];
}

#pragma mark -

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

- (void) setMute:(BOOL)flag {
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

- (void) setChannel:(MKChannel *)chan {
	_channel = chan;
}

- (MKChannel *) channel {
	return _channel;
}

@end
