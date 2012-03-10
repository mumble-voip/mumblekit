// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

@interface MKUser (PrivateMethods)
- (void) removeFromChannel;
- (void) setSession:(NSUInteger)session;
- (void) setUserName:(NSString *)name;
- (void) setUserId:(NSInteger)userId;
- (void) setUserHash:(NSString *)hash;
- (void) setTalkState:(MKTalkState)val;
- (void) setFriend:(BOOL)flag;
- (void) setMuted:(BOOL)flag;
- (void) setDeafened:(BOOL)flag;
- (void) setSuppressed:(BOOL)flag;
- (void) setLocalMuted:(BOOL)flag;
- (void) setSelfMuted:(BOOL)flag;
- (void) setSelfDeafened:(BOOL)flag;
- (void) setPrioritySpeaker:(BOOL)flag;
- (void) setRecording:(BOOL)flag;
- (void) setChannel:(MKChannel *)chan;
- (void) setCommentHash:(NSData *)hash;
- (void) setComment:(NSString *)comment;
- (void) setTextureHash:(NSData *)hash;
- (void) setTexture:(NSData *)texture;
@end

