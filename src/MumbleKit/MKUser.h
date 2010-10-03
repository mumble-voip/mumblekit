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

#import <MumbleKit/MKServerModelObject.h>

typedef enum {
	MKTalkStatePassive = 0,
	MKTalkStateTalking,
	MKTalkStateWhispering,
	MKTalkStateShouting,
} MKTalkState;

@class MKChannel;

@interface MKUser : MKServerModelObject {
	BOOL         _muted;
	BOOL         _deafened;
	BOOL         _suppressed;
	BOOL         _localMuted;
	BOOL         _selfMuted;
	BOOL         _selfDeafened;
	BOOL         _friend;
	BOOL         _prioritySpeaker;
	MKTalkState  _talkState;
	NSUInteger   _session;
	NSInteger    _userId;
	NSString     *_username;
	MKChannel    *_channel;
}

- (id) init;
- (void) dealloc;

#pragma mark -

- (void) setSession:(NSUInteger)session;
- (NSUInteger) session;

- (void) setUserName:(NSString *)name;
- (NSString *) userName;

- (void) setUserId:(NSInteger)userId;
- (NSInteger) userId;

- (void) setTalkState:(MKTalkState)val;
- (MKTalkState) talkState;

- (BOOL) isAuthenticated;

- (void) setFriend:(BOOL)flag;
- (BOOL) isFriend;

- (void) setMuted:(BOOL)flag;
- (BOOL) isMuted;

- (void) setDeafened:(BOOL)flag;
- (BOOL) isDeafened;

- (void) setSuppressed:(BOOL)flag;
- (BOOL) isSuppressed;

- (void) setLocalMuted:(BOOL)flag;
- (BOOL) isLocalMuted;

- (void) setSelfMuted:(BOOL)flag;
- (BOOL) isSelfMuted;

- (void) setSelfDeafened:(BOOL)flag;
- (BOOL) isSelfDeafened;

- (void) setPrioritySpeaker:(BOOL)flag;
- (BOOL) isPrioritySpeaker;

- (void) setChannel:(MKChannel *)chan;
- (MKChannel *) channel;

@end
