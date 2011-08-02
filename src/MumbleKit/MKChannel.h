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

@class MKUser;

/**
 * MKChannel represents a channel on a Mumble server. MKChannel objects are owned
 * by their respective MKServerModel instances.
 *
 * The object's MKServerModel may change properties of the channel at any time, but
 * all changes are serialized to the main thread. 
 *
 * Generally, as a consumer of this API, most accesses to MKChannel happen in response to
 * MKServerModelDelegate callbacks, and all calls to delegate methods of MKServerModel are
 * ensured to happen on the same thread that modifies MKChannle objects.
 * 
 * Thus, if all inspection of the MKChannel's properties happen in response to
 * MKServerModelDelegate callbacks, everything should be OK.
 */
@interface MKChannel : NSObject

/**
 * Returns the channel's channel ID.
 */
- (NSUInteger) channelId;

/**
 * Returns the channel's name.
 */
- (NSString *) channelName;

/**
 * Returns whether or not the channel is temporary.
 *
 * @returns Returns YES if the channel is temporary. Returns NO if the channel is permanent.
 */
- (BOOL) isTemporary;

/**
 * Returns the position of the channel.
 */
- (NSInteger) position;

/**
 * Returns the channel's parent.
 *
 * @returns  The MKChannel object representing the channel's parent.
 *           Returns nil if the current channel is the root channel.
 */
- (MKChannel *) parent;

/**
 * Returns an NSArray of the channel's subchannels represented as MKChannels.
 */
- (NSArray *) channels;

/**
 * Returns an NSArray of all users in the channel. The users are represented as MKUsers.
 */
- (NSArray *) users;

/**
 * Returns an NSArray of all channels linked to this channel.
 */
- (NSArray *) linkedChannels;

/**
 * Checks whether a given channel is linked to the receiving channel.
 *
 * @param channel  The channel whose link status should be checked.
 *
 * @returns  Returns YES if the receiving channel is linked to channel.
 *           Otherwise, returns NO.
 */
- (BOOL) isLinkedToChannel:(MKChannel *)channel;

/**
 * Returns a channel's description hash. (On most server implementations, this
 * is a SHA1 digest).
 */
- (NSData *) channelDescriptionHash;

/**
 * Returns the channel's description.
 */
- (NSString *) channelDescription;

@end
