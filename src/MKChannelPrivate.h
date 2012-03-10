// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

@interface MKChannel (PrivateMethods)
- (void) removeFromParent;

- (void) setChannelId:(NSUInteger)channelId;
- (void) setChannelName:(NSString *)name;
- (void) setTemporary:(BOOL)flag;
- (void) setPosition:(NSInteger)pos;

- (void) setParent:(MKChannel *)chan;
- (void) addChannel:(MKChannel *)child;
- (void) removeChannel:(MKChannel *)child;

- (void) addUser:(MKUser *)user;
- (void) removeUser:(MKUser *)user;
- (void) removeAllUsers;

- (void) linkToChannel:(MKChannel *)chan;
- (void) unlinkFromChannel:(MKChannel *)chan;
- (void) unlinkAll;

- (void) setChannelDescriptionHash:(NSData *)hash;
- (void) setChannelDescription:(NSString *)desc;
@end

