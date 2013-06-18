// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <Security/Security.h>

/// @constant The default MKConnection ping interval.
#define MKConnectionPingInterval 5.0f

@class MKConnection;
@class MKPacketDataStream;
@class MKCryptState;
@class MKCertificate;

typedef enum {
    UDPVoiceCELTAlphaMessage = 0,
    UDPPingMessage,
    UDPVoiceSpeexMessage,
    UDPVoiceCELTBetaMessage,
    UDPVoiceOpusMessage,
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
    ContextActionModifyMessage,
    ContextActionMessage,
    UserListMessage,
    VoiceTargetMessage,
    PermissionQueryMessage,
    CodecVersionMessage,
    UserStatsMessage,
    RequestBlobMessage,
    ServerConfigMessage,
} MKMessageType;

/// MKRejectReason is an integer describing the reason for a
/// rejected connection attempt.
typedef enum {
    /// There was no reason.
    MKRejectReasonNone = 0,
    
    /// The client attempted to connect with an unsupported version.
    MKRejectReasonWrongVersion,
    
    /// The specified username is not deemed valid by the remote server.
    MKRejectReasonInvalidUsername,

    /// The given password is an incorrect password for the given username.
    MKRejectReasonWrongUserPassword,

    /// The given password is not the correct server password.
    MKRejectReasonWrongServerPassword,

    /// The username the connection attempted to connect with is already in use
    /// on the server.
    MKRejectReasonUsernameInUse,

    /// The server is full and cannot accept any new clients.
    MKRejectReasonServerIsFull,

    /// The client did not present a certificate, but the server is set up to require
    /// the presence of a client certificate.
    MKRejectReasonNoCertificate
} MKRejectReason;

/// @protocol MKConnectionDelegate MumbleKit/MKConnection.h
///
/// MKConnectionDelegate implements a set of methods that are called on the delegate
/// object of a MKConnection when important connection-related events happen.
@protocol MKConnectionDelegate

/// This method is called once a connection has been established to the remote host, and
/// the TLS handshake has finished.
/// Once the MKConnection has sent this message to its delegate, it is safe to authenticate
/// with the server.
///
/// @param conn  The connection that was opened.
- (void) connectionOpened:(MKConnection *)conn;

/// This method is called if a connection cannot be stablished to the given server.
///
/// @param conn The connection that this occurred in. 
/// @param err  Error describing why the connection could not be established.
- (void) connection:(MKConnection *)conn unableToConnectWithError:(NSError *)err;

/// This method is called whenever the connection is closed, be it by an error, or by
/// disconnection. If the disconnection was caused by an error, the err parameter will
/// be a non-nil value.
///
/// This method can only be called after the connection has been opened. If an error occurs
/// during the connection phase, the method `connection:unableToConnectWithError:` will be
/// called instead.
///
/// @param conn  The connection that was closed.
/// @param err   The error that caused the disconnection. (Nil if not caused by an error)
- (void) connection:(MKConnection *)conn closedWithError:(NSError *)err;

/// This method is called if the MKConnection could not verify the TLS certificate chain
/// of the remote server as trusted.
///
/// To implement support for self-signed certificates, one wold typically save the digest
/// of the leaf certificate of the server's certificate chain somewhere along with host
/// information for the server (hostname:port) that the trust failure happened on.
/// Then, every time a connection attempt is made, the trust failure can then be remedied
/// by setting setIgnoreSSLVerification property on the MKConnection and issuing a
/// reconnect to the MKConnection object.
///
/// @param conn   The connection that the trust failure occurred on.
/// @param chain  The TLS certificate chain of the remote server.
///               (An array of MKCertificate objects)
- (void) connection:(MKConnection *)conn trustFailureInCertificateChain:(NSArray *)chain;

/// The connection attempt was rejected. This could, for example, be an authentication failure.
///
/// @param conn         The MKConnection object whose connection was rejected.
/// @param reason       The reason for the rejected connection attempt. (See MKRejectReason).
/// @param explanation  A textual description of the reason for rejection.
- (void) connection:(MKConnection *)conn rejectedWithReason:(MKRejectReason)reason explanation:(NSString *)explanation;
@end

/// @protocol MKMessageHandler MKConnection.h MumbleKit/MKConnection.h
///
/// MKMessageHandler implements a set of methods that are called on the messageHandler
/// object of a MKConnection when new control channel messages arrive. Only messages that
/// the MKConnection itself does not know how to handle are delegated to the messageHandler.
///
/// Typically, a consumer of MKConnection does not directly set a MKMessage handler, but instead
/// wrap the MKConnection in a MKServerModel object which 
@protocol MKMessageHandler

/// Called whenever a ban list message is received. (See MKMessageType's
/// BanListMessage value).
///
/// @param conn  The connection that received the message.
/// @param msg   An internal representation of a ban list message.
- (void) connection:(MKConnection *)conn handleBanListMessage: /* MPBanList */ (id)msg;

/// Called whenever a server sync message is received. (See MKMessageType's
/// ServerSyncMessage value).
///
/// @param conn  The connection that received the message.
/// @param msg   An internal representation of a server sync message.
- (void) connection:(MKConnection *)conn handleServerSyncMessage: /* MPServerSync */ (id)msg;

/// Called whenever a permission denied message is received. (See MKMessageType's
/// PermissionDeniedMessage value).
///
/// @param conn  The connection that received the message.
/// @param msg   An internal representation of a permission denied message.
- (void) connection:(MKConnection *)conn handlePermissionDeniedMessage: /* MPPermissionDenied */ (id)msg;

/// Called whenever a user state message is receieved. (See MKMessageType's
/// UserStateMessage value).
///
/// @param conn  The connection that received the message.
/// @param msg   An internal representation of a user state message.
- (void) connection:(MKConnection *)conn handleUserStateMessage: /* MPUserState */ (id)msg;

/// Called whenever a user remove message is received. (See MKMessageType's
/// UserRemoveMessage value).
///
/// @param conn  The connection that received the message.
/// @param msg   An internal representation of a user remove message.
- (void) connection:(MKConnection *)conn handleUserRemoveMessage: /* MPUserRemove */ (id)msg;

/// Called whenever a channel state message is recieved. (See MKMessageType's
/// ChannelStateMessage value).
///
/// @param conn  The connection that received the message.
/// @param msg   An internal representation of a channel state message.
- (void) connection:(MKConnection *)conn handleChannelStateMessage: /* MPChannelState */ (id)msg;

/// Called whenever a channel remove message is received (See MKMessageType's
/// ChannelRemoveMessage value).
///
/// @param conn  The connection that received the message.
/// @param msg   An internal representation of a channel remove message.
- (void) connection:(MKConnection *)conn handleChannelRemoveMessage: /* MPChannelRemove */ (id)msg;

/// Called whenever a text message message is recieved. (See MKMessageType's
/// TextMessageMessage value).
///
/// @param conn  The connection that received the message.
/// @param msg   An internal representation of a text message message.
- (void) connection:(MKConnection *)conn handleTextMessageMessage: /* MPTextMessage */ (id)msg;

/// Called whenever an ACL message is receieved. (See MKMessageType's ACLMessage value).
///
/// @param conn  The connection that received the message.
/// @param msg   An internal representation of an ACL message.
- (void) connection:(MKConnection *)conn handleACLMessage: /* MPACL */ (id)msg;

/// Called whenver a query users message is received. (See MKMessageType's
/// QueryUsersMessage value).
///
/// @param conn  The connection that received the message.
/// @param msg   An internal representation of a query users message.
- (void) connection:(MKConnection *)conn handleQueryUsersMessage: /* MPQueryUsers */ (id)msg;

/// Called whenever a context action message is receieved. (See MKMessageType's
/// ContextActionMessage value).
///
/// @param conn  The connection that received the message.
/// @param msg   An internal representation of a context action message.
- (void) connection:(MKConnection *)conn handleContextActionMessage: /* MPContextAction */ (id)msg;

/// Called whenever a context action add message is received. (See MKMessageType's
/// ContextActionModify value).
///
/// @param conn  The connection that received the message.
/// @param msg   An internal representation of a context action add message.
- (void) connection:(MKConnection *)conn handleContextActionModifyMessage: /* MPContextActionModify */ (id)msg;

/// Called whenever a user list message is received. (See MKMessageType's
/// UserListMessage value).
///
/// @param conn  The connection that received the message.
/// @param msg   An internal representation of a user list message.
- (void) connection:(MKConnection *)conn handleUserListMessage: /* MPUserList */ (id)msg;

/// Called whenever a voice target message is receieved. (See MKMessageType's
/// VoiceTargetMessage value).
///
/// @param conn  The connection that received the message.
/// @param msg   An internal representation of a voice target message.
- (void) connection:(MKConnection *)conn handleVoiceTargetMessage: /* MPVoiceTarget */ (id)msg;

/// Called whenever a permission query message is receieved.
///
/// @param conn  The connection that received the message.
/// @param msg   An internal representation of a permission query message.
- (void) connection:(MKConnection *)conn handlePermissionQueryMessage: /* MPPermissionQuery */ (id)msg;
@end

/// @class MKConnection MKConnection.h MumbleKit/MKConnection.h
///
/// MKConnection represents a connection to a Mumble server.
/// It is mostly used together with MKServerModel which translates the wire protocol
/// to Objective-C delegate callbacks.
@interface MKConnection : NSThread <NSStreamDelegate>

/// Initialize a new MKConnection object.
- (id) init;

/// Deallocate a MKConnection object.
- (void) dealloc;

#pragma mark -

/// Establish a connection to the given host and port.
///
/// @param hostName  The hostname to connect to.
/// @param port      The port on hostname to connect to.
- (void) connectToHost:(NSString *)hostName port:(NSUInteger)port;

/// Re-establish the connection. This is often used together with the
/// setIgnoreSSLVerification: method to implement an "Are You Sure?" dialog
/// for self-signed certificates.
- (void) reconnect;

/// Disconnect from the server.
- (void) disconnect;

/// The current status of the connection.
///
/// @returns Returns YES if the MKConnection is currently connected to a server.
///          Returns NO otherwise.
- (BOOL) connected;

/// The hostname that the MKConnection is currently connected to.
- (NSString *) hostname;

/// The port number on the host that the MKConnection is currently connected to.
- (NSUInteger) port;

/// Set a certificate chain to be used for the MKConnection. This property is only
/// used during connection establishment, and as such, chaning this value while the
/// MKConnection object is a conncted to a server has no effect.
///
/// @param chain A NSArray containing a SecIdentityRef as its first item, and SecCertificateRefs subsequently.
- (void) setCertificateChain:(NSArray *)chain;

/// Returns the certificate chain that is to be presented to the server during the next connection attempt.
- (NSArray *) certificateChain;

#pragma mark Server Info

/// A textual description of the version number of the Mumble server that the MKConnection
/// object is currently connected to.
- (NSString *) serverVersion;

/// A textual description of the release name of the Mumble server that the MKConnection
/// object is currently connected to.
- (NSString *) serverRelease;

/// A textual description of the operating system that powers the Mumble server that the
/// MKConnection object is currently connected to.
- (NSString *) serverOSName;

/// A textual description of the version of the operating system that powers the Mumble
/// server that the MKConnection object is currently connected to.
- (NSString *) serverOSVersion;

///-------------------------------------
/// @name Authenticating with the server
///-------------------------------------

/// Once a connection has been established (that is, once the connectionOpened: delegate
/// method has been called), this method must be used to authenticate with the remote
/// Mumble server.
///
/// @param user The username of the user that the MKConnection should authenticate
///             itself as. This can be a registered user, or a new user that is currently
///             not registered.
///
/// @param pass The password to authenticate with. If the specified username is that
///             of a registered user, the password will be treated as a user password.
///             Otherwise, it will be treated as a server password.
///
/// @param tokens The initial set of access tokens for the user we are connecting as, in
///               the form of an NSArray of NSStrings.
///               This parameter may be nil if the user does not have any access tokens.
- (void) authenticateWithUsername:(NSString *)user password:(NSString *)pass accessTokens:(NSArray *)tokens;

///----------------------
/// @name Message Handler
///----------------------

- (void) setMessageHandler: (id<MKMessageHandler>)messageHandler;
- (id) messageHandler;

///----------------------
/// @name Delegate
///----------------------

- (void) setDelegate: (id<MKConnectionDelegate>)delegate;
- (id) delegate;

///---------------------------
/// @name TLS connection state
///---------------------------

/// Signals to the MKConnection that it should ignore most verification
/// errors that happen while verifying the server's certificate chain
/// during the TLS handshake.
///
/// This is used to implement user trust of servers with self-signed
/// (or perhaps shady) certificates.
///
/// @param shouldIgnoreVerification Should be YES if the connection should
///                                 ignore TLS certificate chain verification
///                                 errors. By default this is set to NO.
- (void) setIgnoreSSLVerification:(BOOL)shouldIgnoreVerification;

/// Once a connection is established, this method returns an array
/// containing the TLS certificate chain of the remote server.
///
/// Certificates in the chain are represented by MKCertificate objects.
- (NSArray *) peerCertificates;

/// Once a connection is established, this method returns the system's
/// trust status of the server's certificate chain. This trust is based
/// on the system's list of root certificate authorities.
- (BOOL) peerCertificateChainTrusted;

///----------------------
/// @name Forced TCP mode
///----------------------

/// Set whether or not the server should force all UDP trafic to be tunelled
/// through TCP. If at all possible, this should be kept as NO (which is also
/// the default value).
///
/// @param shouldForceTCP  Should be YES if the connection shall tunnel all UDP
///                        trafic through TCP.
- (void) setForceTCP:(BOOL)shouldForceTCP;

/// Returns the current Forced-TCP status of the MKConnection object.
///
/// @returns Returns YES if all UDP trafic to and from the remote server
///          is being tunelled through a TCP connection. Returns NO otherwise.
- (BOOL) forceTCP;

///----------------------------------------
/// @name Sending data to the remote server
///----------------------------------------

/// Transmits a blob of data (presumed to be a message encoded as expected by
/// the Mumble server) using the given messageType as the token used for identifying
/// how the contents of the message are to be handled by the remote server.
///
/// @param messageType  A MKMessageType describing the kind of message that is to be
///                     transmitted.
///
/// @param data  The raw data to be sent to the remote server. This is presumed to be
///              a message encoded as expected by the remote server. (That is,
///              MKConnection will not attempt to serialize the passed-in data).
- (void) sendMessageWithType:(MKMessageType)messageType data:(NSData *)data;

/// Send a voice packet to the remote server.
/// The voice packet will be transported to the server using UDP, unless
/// the forceTCP property has been changed to force all UDP trafic to be
/// tunelled through TCP.
///
/// @param data  A raw Mumble voice packet.
- (void) sendVoiceData:(NSData *)data;

///------------------------
/// @name Codec Information
///------------------------

/// The current elected alpha codec, as determined by the server through a mojority vote.
- (NSUInteger) alphaCodec;

/// The currently elected beta codec, as determined by the server through a majority vote.
- (NSUInteger) betaCodec;

/// Returns whether or not clients should prefer the alpha codec over the beta codec (if at
/// all possible).
- (BOOL) preferAlphaCodec;

/// Returns whether ot not the connected client should use the Opus codec.
- (BOOL) shouldUseOpus;

@end