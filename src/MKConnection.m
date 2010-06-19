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

#import <MumbleKit/MKUtils.h>
#import <MumbleKit/MKConnection.h>
#import <MumbleKit/MKConnectionController.h>
#import <MumbleKit/MKPacketDataStream.h>
#import <MumbleKit/MKUser.h>
#import <MumbleKit/MKAudioOutput.h>
#import <MumbleKit/MKVersion.h>

#if TARGET_OS_IPHONE == 1
# import <UIKIt/UIKit.h>
# import <CFNetwork/CFNetwork.h>
#endif

#include <dispatch/dispatch.h>

#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <netinet/tcp.h>

#include <celt.h>

#import "Mumble.pb.h"


/*
 * The SecureTransport.h header is not available on the iPhone, so
 * these constants are lifted from the Mac OS X version of the header.
 */
#define errSSLProtocol             -9800
#define errSSLXCertChainInvalid    -9807
#define errSSLLast                 -9849

@interface MKConnection (Private)
- (void) _setupSsl;
- (void) _pingTimerFired:(NSTimer *)timer;
- (void) _pingResponseFromServer:(MPPing *)pingMessage;
- (void) _versionMessageReceived:(MPVersion *)msg;
- (void) _doCryptSetup:(MPCryptSetup *)cryptSetup;
- (void) _connectionRejected:(MPReject *)rejectMessage;
- (void) _sendMessageWrapper:(NSDictionary *)dict;
- (void) _stopThreadRunLoop:(id)noObject;
@end

@implementation MKConnection

- (id) init {
	self = [super init];
	if (self == nil)
		return nil;

	packetLength = -1;
	_connectionEstablished = NO;
	_socket = -1;
	_ignoreSSLVerification = NO;

	[[MKConnectionController sharedController] addConnection:self];

	return self;
}

- (void) dealloc {
	[[MKConnectionController sharedController] removeConnection:self];
	[self closeStreams];

	[super dealloc];
}

- (void) main {
	NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
	NSLog(@"Launching thread...");

	CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault,
									   (CFStringRef)hostname, port,
									   (CFReadStreamRef *) &_inputStream,
									   (CFWriteStreamRef *) &_outputStream);

	if (_inputStream == nil || _outputStream == nil) {
		NSLog(@"MKConnection: Unable to create stream pair.");
		return;
	}

	[_inputStream setDelegate:self];
	[_outputStream setDelegate:self];

	[_inputStream scheduleInRunLoop:runLoop forMode:NSDefaultRunLoopMode];
	[_outputStream scheduleInRunLoop:runLoop forMode:NSDefaultRunLoopMode];

	[self _setupSsl];

	[_inputStream open];
	[_outputStream open];

	NSLog(@"opened threads...");
	NSLog(@"launching runloop...");

	while (_keepRunning) {
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
	}

	NSLog(@"out of runloop.");

	if (_inputStream) {
		[_inputStream close];
		[_inputStream release];
		_inputStream = nil;
	}

	if (_outputStream) {
		[_outputStream close];
		[_outputStream release];
		_outputStream = nil;
	}

	[_pingTimer invalidate];
	_pingTimer = nil;
}

- (void) _stopThreadRunLoop:(id)noObject {
	CFRunLoopRef runLoop = [[NSRunLoop currentRunLoop] getCFRunLoop];
	CFRunLoopStop(runLoop);
}

- (void) connectToHost:(NSString *)hostName port:(NSUInteger)portNumber {
	packetLength = -1;
	_connectionEstablished = NO;

	hostname = hostName;
	port = portNumber;

	_keepRunning = YES;

	[self start];
}

- (void) closeStreams {
	_keepRunning = NO;
	[self performSelector:@selector(_stopThreadRunLoop:) onThread:self withObject:nil waitUntilDone:NO];
	while (![self isFinished]);
}

- (void) reconnect {
	[self closeStreams];
	NSLog(@"MKConnection: Reconnecting...");
	[self connectToHost:hostname port:port];
}

- (BOOL) connected {
	return _connectionEstablished;
}

#pragma mark Server Information

- (NSString *) serverVersion {
	return _serverVersion;
}

- (NSString *) serverRelease {
	return _serverRelease;
}

- (NSString *) serverOSName {
	return _serverOSName;
}

- (NSString *) serverOSVersion {
	return _serverOSVersion;
}

#pragma mark -

- (void) authenticateWithUsername:(NSString *)userName password:(NSString *)password {
	//
	// Figure out CELT bitstream version
	// fixme(mkrautz): Refactor into a MKCELTManager or the like.
	//
	celt_int32 bitstream;
	CELTMode *mode = celt_mode_create(48000, 100, NULL);
	celt_mode_info(mode, CELT_GET_BITSTREAM_VERSION, &bitstream);
	celt_mode_destroy(mode);

	 NSLog(@"CELT bitstream = 0x%x", bitstream);

	 NSData *data;
	 MPVersion_Builder *version = [MPVersion builder];

	//
	// Query the OS name and version
	//
#if TARGET_OS_IPHONE == 1
	UIDevice *dev = [UIDevice currentDevice];
	[version setOs: [dev systemName]];
	[version setOsVersion: [dev systemVersion]];
#elif TARGET_OS_MAC == 1
	// fixme(mkrautz): Do proper lookup here.
	[version setOs:@"Mac OS X"];
	[version setOsVersion:@"10.6"];
#endif
	
	//
	// Setup MumbleKit version info.
	//
	[version setVersion: [MKVersion hexVersion]];
	[version setRelease: [MKVersion releaseString]];
	data = [[version build] data];
	[self sendMessageWithType:VersionMessage data:data];

	MPAuthenticate_Builder *authenticate = [MPAuthenticate builder];
	[authenticate setUsername:userName];
	if (password) {
		[authenticate setPassword:password];
	}
	[authenticate addCeltVersions:bitstream];
	data = [[authenticate build] data];
	[self sendMessageWithType:AuthenticateMessage data:data];
}

#pragma mark NSStream event handlers

- (void) stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode {
	if (stream == _inputStream) {
		if (eventCode == NSStreamEventHasBytesAvailable)
			[self dataReady];
		return;
	}

	switch (eventCode) {
		case NSStreamEventOpenCompleted: {
			/*
			 * The OpenCompleted is a bad indicator of 'ready to use' for a
			 * TLS socket, since it will fire even before the TLS handshake
			 * has even begun. Instead, we rely on the first CanAcceptBytes
			 * event we receive to determine that a connection was established.
			 *
			 * We only use this event to extract our underlying socket.
			 */
			CFDataRef nativeHandle = CFWriteStreamCopyProperty((CFWriteStreamRef) _outputStream, kCFStreamPropertySocketNativeHandle);
			if (nativeHandle) {
				_socket = *(int *)CFDataGetBytePtr(nativeHandle);
				CFRelease(nativeHandle);
			} else {
				NSLog(@"MKConnection: Unable to get socket file descriptor from stream. Breakage may occur.");
			}

			if (_socket != -1) {
				int val = 1;
				setsockopt(_socket, IPPROTO_TCP, TCP_NODELAY, &val, sizeof(val));
				NSLog(@"MKConnection: TCP_NODELAY=1");
			}
			break;
		}

		case NSStreamEventHasSpaceAvailable: {
			if (! _connectionEstablished) {
				_connectionEstablished = YES;

				/* First, schedule our ping timer. */
				_pingTimer = [NSTimer timerWithTimeInterval:MKConnectionPingInterval target:self selector:@selector(_pingTimerFired:) userInfo:nil repeats:YES];
				[[NSRunLoop currentRunLoop] addTimer:_pingTimer forMode:NSRunLoopCommonModes];

				/* Invoke connectionOpened: on our delegate. */
				if ([_delegate respondsToSelector:@selector(connectionOpened:)]) {
					dispatch_async(dispatch_get_main_queue(), ^{
						[_delegate connectionOpened:self];
					});
				}
			}
			break;
		}

		case NSStreamEventErrorOccurred: {
			NSLog(@"MKConnection: ErrorOccurred");
			NSError *err = [_outputStream streamError];
			[self handleError:err];
			break;
		}

		case NSStreamEventEndEncountered:
			NSLog(@"MKConnection: EndEncountered");
			break;

		default:
			NSLog(@"MKConnection: Unknown event (%u)", eventCode);
			break;
	}
}

#pragma mark -

- (void) setDelegate:(id<MKConnectionDelegate>)delegate {
	_delegate = delegate;
}

- (id<MKConnectionDelegate>) delegate {
	return _delegate;
}

- (void) setMessageHandler:(id<MKMessageHandler>)messageHandler {
	_msgHandler = messageHandler;
}

- (id<MKMessageHandler>) messageHandler {
	return _msgHandler;
}

- (void) setVoiceDataHandler:(id<MKVoiceDataHandler>)voiceDataHandler {
	_voiceDataHandler = voiceDataHandler;
}

- (id<MKVoiceDataHandler>) voiceDataHandler {
	return _voiceDataHandler;
}


#pragma mark -

/*
 * Setup our CFStreams for SSL.
 */
- (void) _setupSsl {
	CFMutableDictionaryRef sslDictionary = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,
																	 &kCFTypeDictionaryKeyCallBacks,
																	 &kCFTypeDictionaryValueCallBacks);

	if (sslDictionary) {
		CFDictionaryAddValue(sslDictionary, kCFStreamSSLLevel, kCFStreamSocketSecurityLevelTLSv1);
		CFDictionaryAddValue(sslDictionary, kCFStreamSSLValidatesCertificateChain, _ignoreSSLVerification ? kCFBooleanFalse : kCFBooleanTrue);
	}

	CFWriteStreamSetProperty((CFWriteStreamRef) _outputStream, kCFStreamPropertySSLSettings, sslDictionary);
	CFReadStreamSetProperty((CFReadStreamRef) _inputStream, kCFStreamPropertySSLSettings, sslDictionary);

	CFRelease(sslDictionary);
}

- (void) setIgnoreSSLVerification:(BOOL)flag {
	_ignoreSSLVerification = flag;
}

- (NSArray *) certificates {
	NSArray *certs = (NSArray *) CFWriteStreamCopyProperty((CFWriteStreamRef) _outputStream, kCFStreamPropertySSLPeerCertificates);
	return [certs autorelease];
}

- (void) sendMessageWithType:(MKMessageType)messageType data:(NSData *)data {
	NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
							data, @"data",
							[NSNumber numberWithInt:(int)messageType], @"messageType", nil];
	if ([NSThread currentThread] != self) {
		[self performSelector:@selector(_sendMessageWrapper:) onThread:self withObject:dict waitUntilDone:NO];
	} else {
		[self _sendMessageWrapper:dict];
	}
}

- (void) _sendMessageWrapper:(NSDictionary *)dict {
	NSData *data = [dict objectForKey:@"data"];
	MKMessageType messageType = (MKMessageType)[[dict objectForKey:@"messageType"] intValue];
	const unsigned char *buf = [data bytes];
	NSUInteger len = [data length];

	UInt16 type = CFSwapInt16HostToBig((UInt16)messageType);
	UInt32 length = CFSwapInt32HostToBig(len);

	[_outputStream write:(unsigned char *)&type maxLength:sizeof(UInt16)];
	[_outputStream write:(unsigned char *)&length maxLength:sizeof(UInt32)];
	[_outputStream write:buf maxLength:len];
}


-(void) dataReady {
	unsigned char buffer[6];

	if (! packetBuffer) {
		packetBuffer = [[NSMutableData alloc] initWithLength:0];
	}

	/* We aren't currently retrieveing a packet. */
	if (packetLength == -1) {
		NSInteger availableBytes = [_inputStream read:&buffer[0] maxLength:6];
		if (availableBytes < 6) {
			return;
		}

		packetType = (MKMessageType) CFSwapInt16BigToHost(*(UInt16 *)(&buffer[0]));
		packetLength = (int) CFSwapInt32BigToHost(*(UInt32 *)(&buffer[2]));

		packetBufferOffset = 0;
		[packetBuffer setLength:packetLength];
	}

	/* We're recv'ing a packet. */
	if (packetLength > 0) {
		UInt8 *packetBytes = [packetBuffer mutableBytes];
		if (! packetBytes) {
			NSLog(@"MKConnection: NSMutableData is stubborn.");
			return;
		}

		NSInteger availableBytes = [_inputStream read:packetBytes + packetBufferOffset maxLength:packetLength];
		packetLength -= availableBytes;
		packetBufferOffset += availableBytes;
	}

	/* Done! */
	if (packetLength == 0) {
		[self messageRecieved:packetBuffer];
		[packetBuffer setLength:0]; // fixme(mkrautz): Is this one needed?
		packetLength = -1;
	}
}

/*
 * Ping timer fired.
 */
- (void) _pingTimerFired:(NSTimer *)timer {
	NSData *data;
	MPPing_Builder *ping = [MPPing builder];

	[ping setTimestamp:0];
	[ping setGood:0];
	[ping setLate:0];
	[ping setLost:0];
	[ping setResync:0];

	[ping setUdpPingAvg:0.0f];
	[ping setUdpPingVar:0.0f];
	[ping setUdpPackets:0];
	[ping setTcpPingAvg:0.0f];
	[ping setTcpPingVar:0.0f];
	[ping setTcpPackets:0];

	data = [[ping build] data];
	[self sendMessageWithType:PingMessage data:data];

	NSLog(@"MKConnection: Sent ping message.");
}

- (void) _pingResponseFromServer:(MPPing *)pingMessage {
	NSLog(@"MKConnection: pingResponseFromServer");
}

//
// The server rejected our connection.
//
- (void) _connectionRejected:(MPReject *)rejectMessage {
	MKRejectReason reason = MKRejectReasonNone;
	NSString *explanationString = nil;

	if ([rejectMessage hasType])
		reason = (MKRejectReason) [rejectMessage type];
	if ([rejectMessage hasReason])
		explanationString = [rejectMessage reason];

	if ([_delegate respondsToSelector:@selector(connection:rejectedWithReason:explanation:)]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[_delegate connection:self rejectedWithReason:reason explanation:explanationString];
		});
	}

	[self closeStreams];
}

//
// Handle server crypt setup
//
- (void) _doCryptSetup:(MPCryptSetup *)cryptSetup {
	NSLog(@"MKConnection: CryptSetup ...");
}

//
// Handle incoming version information from the server.
//
- (void) _versionMessageReceived:(MPVersion *)msg {
	if ([msg hasVersion]) {
		int32_t version = [msg version];
		_serverVersion = [[NSString alloc] initWithFormat:@"%i.%i.%i", (version >> 8) & 0xff, (version >> 4) & 0xff, version & 0xff, nil];
	}
	if ([msg hasRelease])
		_serverRelease = [[msg release] copy];
	if ([msg hasOs])
		_serverOSName = [[msg os] copy];
	if ([msg hasOsVersion])
		_serverOSVersion = [[msg osVersion] copy];
}


- (void) handleError:(NSError *)streamError {
	NSInteger errorCode = [streamError code];

	/* Is the error an SSL-related error? (OSStatus errors are negative, so the
	 * greater than and less than signs are sort-of reversed here. */
	if (errorCode <= errSSLProtocol && errorCode > errSSLLast) {
		[self handleSslError:streamError];
	}

	NSLog(@"MKConnection: Error: %@", streamError);
}

- (void) handleSslError:(NSError *)streamError {

	if ([streamError code] == errSSLXCertChainInvalid) {
		SecTrustRef trust = (SecTrustRef) CFWriteStreamCopyProperty((CFWriteStreamRef) _outputStream, kCFStreamPropertySSLPeerTrust);
		SecTrustResultType trustResult;
		if (SecTrustEvaluate(trust, &trustResult) != noErr) {
			/* Unable to evaluate trust. */
		}

		switch (trustResult) {
			/* Invalid setting or result. Indicates the SecTrustEvaluate() did not finish completely. */
			case kSecTrustResultInvalid:
			/* May be trusted for the purposes designated. ('Always Trust' in Keychain) */
			case kSecTrustResultProceed:
			/* User confirmation is required before proceeding. ('Ask Permission' in Keychain) */
			case kSecTrustResultConfirm:
			/* This certificate is not trusted. ('Never Trust' in Keychain) */
			case kSecTrustResultDeny:
			/* No trust setting specified. ('Use System Policy' in Keychain) */
			case kSecTrustResultUnspecified:
			/* Fatal trust failure. Trust cannot be established without replacing the certificate.
			 * This error is thrown when the certificate is corrupt. */
			case kSecTrustResultFatalTrustFailure:
			/* A non-trust related error. Possibly internal error in SecTrustEvaluate(). */
			case kSecTrustResultOtherError:
				break;

			/* A recoverable trust failure. */
			case kSecTrustResultRecoverableTrustFailure: {
				if ([_delegate respondsToSelector:@selector(connection:trustFailureInCertificateChain:)]) {
					dispatch_async(dispatch_get_main_queue(), ^{
						[_delegate connection:self trustFailureInCertificateChain:[self certificates]];
					});
				}
			}
		}

		CFRelease(trust);
	}
}

- (void) messageRecieved: (NSData *)data {
	dispatch_queue_t main_queue = dispatch_get_main_queue();
	
	/* No message handler has been assigned. Don't propagate. */
	if (! _msgHandler)
		return;

	switch (packetType) {
		case AuthenticateMessage: {
			MPAuthenticate *auth = [MPAuthenticate parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(handleAuthenticateMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handleAuthenticateMessage:auth];
				});
			}
			break;
		}
		case ServerSyncMessage: {
			MPServerSync *serverSync = [MPServerSync parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(connection:handleServerSyncMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handleServerSyncMessage:serverSync];
				});
			}
			break;
		}
		case ChannelRemoveMessage: {
			MPChannelRemove *channelRemove = [MPChannelRemove parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(connection:handleChannelRemoveMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handleChannelRemoveMessage:channelRemove];
				});
			}
			break;
		}
		case ChannelStateMessage: {
			MPChannelState *channelState = [MPChannelState parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(connection:handleChannelStateMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handleChannelStateMessage:channelState];
				});
			}
			break;
		}
		case UserRemoveMessage: {
			MPUserRemove *userRemove = [MPUserRemove parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(connection:handleUserRemoveMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handleUserRemoveMessage:userRemove];
				});
			}
			break;
		}
		case UserStateMessage: {
			MPUserState *userState = [MPUserState parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(connection:handleUserStateMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handleUserStateMessage:userState];
				});
			}
			break;
		}
		case BanListMessage: {
			MPBanList *banList = [MPBanList parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(connection:handleBanListMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handleBanListMessage:banList];
				 });
			}
			break;
		}
		case TextMessageMessage: {
			MPTextMessage *textMessage = [MPTextMessage parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(connection:handleTextMessageMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handleTextMessageMessage:textMessage];
				});
			}
			break;
		}
		case PermissionDeniedMessage: {
			MPPermissionDenied *permissionDenied = [MPPermissionDenied parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(connection:handlePermissionDeniedMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handlePermissionDeniedMessage:permissionDenied];
				});
			}
			break;
		}
		case ACLMessage: {
			MPACL *aclMessage = [MPACL parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(connection:handleACLMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handleACLMessage:aclMessage];
				});
			}
			break;
		}
		case QueryUsersMessage: {
			MPQueryUsers *queryUsers = [MPQueryUsers parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(connection:handleQueryUsersMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handleQueryUsersMessage:queryUsers];
				});
			}
			break;
		}
		case ContextActionAddMessage: {
			MPContextActionAdd *contextActionAdd = [MPContextActionAdd parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(connection:handleContextActionAddMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handleContextActionAddMessage:contextActionAdd];
				});
			}
			break;
		}
		case ContextActionMessage: {
			MPContextAction *contextAction = [MPContextAction parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(connection:handleContextActionMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handleContextActionMessage:contextAction];
				});
			}
			break;
		}
		case UserListMessage: {
			MPUserList *userList = [MPUserList parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(connection:handleUserListMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handleUserListMessage:userList];
				});
			}
			break;
		}
		case VoiceTargetMessage: {
			MPVoiceTarget *voiceTarget = [MPVoiceTarget parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(handleVoiceTargetMessage:)]) {
				dispatch_async(dispatch_get_main_queue(), ^{
					[_msgHandler connection:self handleVoiceTargetMessage:voiceTarget];
				});
			}
			break;
		}
		case PermissionQueryMessage: {
			MPPermissionQuery *permissionQuery = [MPPermissionQuery parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(connection:handlePermissionQueryMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handlePermissionQueryMessage:permissionQuery];
				});
			}
			break;
		}
		case CodecVersionMessage: {
			MPCodecVersion *codecVersion = [MPCodecVersion parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(connection:handleCodecVersionMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handleCodecVersionMessage:codecVersion];
				});
			}
			break;
		}

		//
		// Internally handled packets.
		//

		case VersionMessage: {
			MPVersion *v = [MPVersion parseFromData:data];
			[self _versionMessageReceived:v];
			break;
		}
		case PingMessage: {
			MPPing *p = [MPPing parseFromData:data];
			[self _pingResponseFromServer:p];
			break;
		}
		case RejectMessage: {
			MPReject *r = [MPReject parseFromData:data];
			[self _connectionRejected:r];
			break;
		}
		case CryptSetupMessage: {
			MPCryptSetup *cs = [MPCryptSetup parseFromData:data];
			[self _doCryptSetup:cs];
			break;
		}
		case UDPTunnelMessage: {
			unsigned char *buf = (unsigned char *)[data bytes];
			MKUDPMessageType messageType = ((buf[0] >> 5) & 0x7);
			unsigned int messageFlags = buf[0] & 0x1f;
			MKPacketDataStream *pds = [[MKPacketDataStream alloc] initWithBuffer:buf+1 length:[data length]-1]; // fixme(-1)?

			switch (messageType) {
				case UDPVoiceCELTAlphaMessage:
				case UDPVoiceCELTBetaMessage:
				case UDPVoiceSpeexMessage:
					//
					// Call VoiceDataHandler.
					//
					NSLog(@"MKConnection: conn=%p, msgType=%u, msgFlags=%u, voiceData=%p", self, messageType, messageFlags, pds);
					{
						MK_UNUSED NSUInteger session = [pds getUnsignedInt];
						NSUInteger seq = [pds getUnsignedInt];

						NSMutableData *voicePacketData = [[NSMutableData alloc] initWithCapacity:[pds left]+1];
						[voicePacketData setLength:[pds left]+1];

						unsigned char *bytes = [voicePacketData mutableBytes];
						bytes[0] = (unsigned char)messageFlags;
						memcpy(bytes+1, [pds dataPtr], [pds left]);

						if ([_voiceDataHandler respondsToSelector:@selector(connection:session:sequence:type:voiceData:)]) {
							dispatch_async(main_queue, ^{
								[_voiceDataHandler connection:self session:session sequence:seq type:messageType voiceData:voicePacketData];
							});
						}
					}
					break;
				default:
					NSLog(@"MKConnection: Unknown UDPTunnel packet received. Discarding...");
					break;
			}

			[pds release];
			break;
		}

		default: {
			NSLog(@"MKConnection: Unknown packet type recieved. Discarding. (type=%u)", packetType);
			break;
		}
	}
}

@end
