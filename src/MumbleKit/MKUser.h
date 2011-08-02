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

typedef enum {
	MKTalkStatePassive = 0,
	MKTalkStateTalking,
	MKTalkStateWhispering,
	MKTalkStateShouting,
} MKTalkState;

@class MKChannel;

/**
 * MKUser represents a user on a Mumble server. A user always resides in a channel, which is
 * represented by the MKChannel object. MKChannel objects are owned by their respective MKServerModel
 * instances.
 *
 * The object's MKServerModel may change properties of the user at any time, but
 * all changes are serialized to the main thread. 
 *
 * Generally, as a consumer of this API, most accesses to MKUser happen in response to
 * MKServerModelDelegate callbacks, and all calls to delegate methods of MKServerModel are
 * ensured to happen on the same thread that modifies MKChannle objects.
 * 
 * Thus, if all inspection of the MKChannel's properties happen in response to
 * MKServerModelDelegate callbacks, everything should be OK.
 */
@interface MKUser : NSObject

/**
 * Returns a user's user ID. Only registered users have user IDs.
 * For non-registered users, this ID will be negative.
 * A user ID of 0 signals that the user is the SuperUser.
 */
- (NSInteger) userId;

/**
 * Returns the user's session ID.
 * The session ID is mostly an implementation detail -- it is an identifier that
 * uniquely identifies a user on a server, regardless of whether or not that user
 * is registered with the server.
 */
- (NSUInteger) session;

/**
 * Returns the user's username.
 */
- (NSString *) userName;

/**
 * Returns the user's hash. Typically, the the hash is the SHA1 digest of the user's X.509
 * certificate, but could be any unique hash that identifies the user.
 */
- (NSString *) userHash;

/**
 * Returns the user's current talk state. See MKTalkState for more information.
 */
- (MKTalkState) talkState;

/**
 * Returns whether or not the user is authenticated.
 */
- (BOOL) isAuthenticated;

/**
 * Returns whether or not the receiving user is a friend.
 */
- (BOOL) isFriend;

/**
 * Returns whether or not the receiving user is muted.
 */
- (BOOL) isMuted;

/**
 * Returns whether or not the receiving user is deafened.
 */
- (BOOL) isDeafened;

/**
 * Returns whether or not the receiving user is suppressed by the server.
 */
- (BOOL) isSuppressed;

/**
 * Returns whether or not the receiving user is muted by the local client.
 */
- (BOOL) isLocalMuted;

/**
 * Returns whether or not the receiving user is self-muted.
 */
- (BOOL) isSelfMuted;

/**
 * Returns whether or not the receiving user is self-deafened.
 */
- (BOOL) isSelfDeafened;

/**
 * Returns whether or not the receiving user has the priority speaker flag.
 */
- (BOOL) isPrioritySpeaker;

/**
 * Returns whether or not the receiving user has the recording flag.
 */
- (BOOL) isRecording;

/**
 * Returns the channel that the receiving user is currently residing in.
 */
- (MKChannel *) channel;

/**
 * Returns the server's hash of the contents of the user's current comment.
 */
- (NSData *) commentHash;

/**
 * Return the user's current comment as an NSString.
 */
- (NSString *) comment;

/**
 * Returns the server's hash of the user's current texture.
 */
- (NSData *) textureHash;

/**
 * Returns the user's texture as an NSData object. The NSData object
 * contains the binary representation of the user's texture as an image
 * in either JPEG, PNG or ARGB32 format.
 */
- (NSData *) texture;

@end
