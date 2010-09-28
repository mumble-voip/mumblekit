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

#import <Security/Security.h>

#define MKConnectionPingInterval 5.0f

@class MKConnection;
@class MKPacketDataStream;
@class MKCryptState;
@class MKCertificate;

typedef enum {
	UDPVoiceCELTAlphaMessage = 0,
	UDPPingMessage,
	UDPVoiceSpeexMessage,
	UDPVoiceCELTBetaMessage
} MKUDPMessageType;

typedef enum {
	VersionMessage = 0,
	UDPTunnelMessage,
	AuthenticateMessage,
	PingMessage,
	RejectMessage,
	ServerSyncMessage,
	ChannelRemoveMessage,
	ChannelStateMessage,
	UserRemoveMessage,
	UserStateMessage,
	BanListMessage,
	TextMessageMessage,
	PermissionDeniedMessage,
	ACLMessage,
	QueryUsersMessage,
	CryptSetupMessage,
	ContextActionAddMessage,
	ContextActionMessage,
	UserListMessage,
	VoiceTargetMessage,
	PermissionQueryMessage,
	CodecVersionMessage,
	UserStatsMessage,
	RequestBlobMessage,
	ServerConfigMessage,
} MKMessageType;

typedef enum {
	MKRejectReasonNone = 0,
	MKRejectReasonWrongVersion,
	MKRejectReasonInvalidUsername,
	MKRejectReasonWrongUserPassword,
	MKRejectReasonWrongServerPassword,
	MKRejectReasonUsernameInUse,
	MKRejectReasonServerIsFull,
	MKRejectReasonNoCertificate
} MKRejectReason;

/*
 * MKConnectionDelegate
 */
@protocol MKConnectionDelegate
- (void) connectionOpened:(MKConnection *)conn;
- (void) connectionClosed:(MKConnection *)conn;
- (void) connection:(MKConnection *)conn trustFailureInCertificateChain:(NSArray *)chain;
- (void) connection:(MKConnection *)conn rejectedWithReason:(MKRejectReason)reason explanation:(NSString *)explanation;
@end

/*
 * MKMessageHandler
 */
@protocol MKMessageHandler
- (void) connection:(MKConnection *)conn handleAuthenticateMessage: /* MPAuthenticate */ (id)msg;
- (void) connection:(MKConnection *)conn handleBanListMessage: /* MPBanList */ (id)msg;
- (void) connection:(MKConnection *)conn handleServerSyncMessage: /* MPServerSync */ (id)msg;
- (void) connection:(MKConnection *)conn handlePermissionDeniedMessage: /* MPPermissionDenied */ (id)msg;
- (void) connection:(MKConnection *)conn handleUserStateMessage: /* MPUserState */ (id)msg;
- (void) connection:(MKConnection *)conn handleUserRemoveMessage: /* MPUserRemove */ (id)msg;
- (void) connection:(MKConnection *)conn handleChannelStateMessage: /* MPChannelState */ (id)msg;
- (void) connection:(MKConnection *)conn handleChannelRemoveMessage: /* MPChannelRemove */ (id)msg;
- (void) connection:(MKConnection *)conn handleTextMessageMessage: /* MPTextMessage */ (id)msg;
- (void) connection:(MKConnection *)conn handleACLMessage: /* MPACL */ (id)msg;
- (void) connection:(MKConnection *)conn handleQueryUsersMessage: /* MPQueryUsers */ (id)msg;
- (void) connection:(MKConnection *)conn handleContextActionMessage: /* MPContextAction */ (id)msg;
- (void) connection:(MKConnection *)conn handleContextActionAddMessage: /* MPContextActionAdd */ (id)add;
- (void) connection:(MKConnection *)conn handleUserListMessage: /* MPUserList */ (id)msg;
- (void) connection:(MKConnection *)conn handleVoiceTargetMessage: /* MPVoiceTarget */ (id)msg;
- (void) connection:(MKConnection *)conn handlePermissionQueryMessage: /* MPPermissionQuery */ (id)msg;
- (void) connection:(MKConnection *)conn handleCodecVersionMessage: /* MPCodecVersion */ (id)msg;
@end

/*
 * MKVoiceDataHandler
 */
@protocol MKVoiceDataHandler
- (void) connection:(MKConnection *)conn session:(NSUInteger)session sequence:(NSUInteger)seq type:(MKUDPMessageType)msgType voiceData:(NSMutableData *)data;
@end

@interface MKConnection : NSThread <NSStreamDelegate> {
	MKCryptState   *_crypt;

	MKMessageType  packetType;
	int            packetLength;
	int            packetBufferOffset;
	NSMutableData  *packetBuffer;
	NSString       *_hostname;
	NSUInteger     _port;
	BOOL           _keepRunning;
	BOOL           _reconnect;

	BOOL           _forceTCP;
	BOOL           _udpAvailable;
	unsigned long  _connTime;
	NSTimer        *_pingTimer;
	NSOutputStream *_outputStream;
	NSInputStream  *_inputStream;
	BOOL           _connectionEstablished;
	BOOL           _ignoreSSLVerification;
	id             _voiceDataHandler;
	id             _msgHandler;
	id             _delegate;
	int            _socket;
	CFSocketRef    _udpSock;
	SecIdentityRef _clientIdentity;

	// Server info.
	NSString       *_serverVersion;
	NSString       *_serverRelease;
	NSString       *_serverOSName;
	NSString       *_serverOSVersion;
	NSMutableArray *_peerCertificates;
}

- (id) init;
- (void) dealloc;

#pragma mark -

- (void) connectToHost:(NSString *)hostName port:(NSUInteger)port;
- (void) reconnect;
- (void) disconnect;
- (BOOL) connected;
- (NSString *) hostname;
- (NSUInteger) port;

- (void) setClientIdentity:(SecIdentityRef)secIdentity;
- (SecIdentityRef) clientIdentity;

#pragma mark Server Info

- (NSString *) serverVersion;
- (NSString *) serverRelease;
- (NSString *) serverOSName;
- (NSString *) serverOSVersion;
#pragma mark -

- (void) authenticateWithUsername:(NSString *)user password:(NSString *)pass;

#pragma mark -

- (void) setVoiceDataHandler: (id<MKVoiceDataHandler>)voiceDataHandler;
- (id) voiceDataHandler;
- (void) setMessageHandler: (id<MKMessageHandler>)messageHandler;
- (id) messageHandler;
- (void) setDelegate: (id<MKConnectionDelegate>)delegate;
- (id) delegate;

#pragma mark -

- (void) setIgnoreSSLVerification:(BOOL)flag;
- (NSArray *) peerCertificates;

- (void) setForceTCP:(BOOL)flag;
- (BOOL) forceTCP;

- (void) sendMessageWithType:(MKMessageType)messageType data:(NSData *)data;
- (void) sendVoiceData:(NSData *)data;

@end
