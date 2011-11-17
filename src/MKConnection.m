/* Copyright (C) 2009-2011 Mikkel Krautz <mikkel@krautz.dk>

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

#import <MumbleKit/MKConnection.h>
#import <MumbleKit/MKConnectionController.h>
#import <MumbleKit/MKUser.h>
#import <MumbleKit/MKVersion.h>
#import <MumbleKit/MKCertificate.h>
#import "MKUtils.h"
#import "MKAudioOutput.h"
#import "MKCryptState.h"
#import "MKPacketDataStream.h"

#include <dispatch/dispatch.h>

#if TARGET_OS_IPHONE == 1
# import <UIKIt/UIKit.h>
# import <CFNetwork/CFNetwork.h>
# import <CoreFoundation/CoreFoundation.h>
#endif

#include <sys/socket.h>
#include <sys/types.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <netinet/tcp.h>

#include <celt.h>

#import "Mumble.pb.h"


// The SecureTransport.h header is not available on the iPhone, so
// these constants are lifted from the Mac OS X version of the header.
#define errSSLProtocol             -9800
#define errSSLXCertChainInvalid    -9807
#define errSSLUnknownRootCert      -9812
#define errSSLLast                 -9849

@interface MKConnection (Private)
- (void) _stopThreadRunLoop:(id)noObject;
- (uint64_t) _currentTimeStamp;

- (void) _setupSsl;
- (void) _pingTimerFired:(NSTimer *)timer;
- (void) _pingResponseFromServer:(MPPing *)pingMessage;
- (void) _versionMessageReceived:(MPVersion *)msg;
- (void) _doCryptSetup:(MPCryptSetup *)cryptSetup;
- (void) _connectionRejected:(MPReject *)rejectMessage;
- (void) _codecChange:(MPCodecVersion *)codecVersion;

// TCP
- (void) _sendMessageHelper:(NSDictionary *)dict;
- (void) _dataReady;
- (void) _messageRecieved:(NSData *)data;

// UDP
- (void) _setupUdpSock;
- (void) _teardownUdpSock;
- (void) _udpDataReady:(NSData *)data;
- (void) _udpMessageReceived:(NSData *)data;
- (void) _sendUDPMessage:(NSData *)data;

// Error handling
- (void) _handleError:(NSError *)streamError;
- (void) _handleSslError:(NSError *)streamError;
@end

// CFSocket UDP callback.  This is called by MKConnection's UDP CFSocket whenever
// there is new data available (it only uses the kCFSocketDataCallback callback mode).
static void MKConnectionUDPCallback(CFSocketRef sock, CFSocketCallBackType type,
									CFDataRef addr, const void *data, void *udata) {
	if (type != kCFSocketDataCallBack || !udata || !data)
		return;
	MKConnection *conn = (MKConnection *)udata;
	[conn _udpDataReady:(NSData *)data];
}

@interface MKConnection () {
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
    BOOL           _readyVoice;
	id             _msgHandler;
	id             _delegate;
	int            _socket;
	CFSocketRef    _udpSock;
	SecIdentityRef _clientIdentity;

	// Codec info
	NSInteger      _alphaCodec;
	NSInteger      _betaCodec;
	BOOL           _preferAlpha;

	// Server info.
	NSString       *_serverVersion;
	NSString       *_serverRelease;
	NSString       *_serverOSName;
	NSString       *_serverOSVersion;
	NSMutableArray *_peerCertificates;
}
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

	_crypt = [[MKCryptState alloc] init];

	return self;
}

- (void) dealloc {
	[self disconnect];

	[_crypt release];
	[_peerCertificates release];

	if (_clientIdentity)
		CFRelease(_clientIdentity);

	[super dealloc];
}

- (void) main {
	NSRunLoop *runLoop = [NSRunLoop currentRunLoop];

	do {
		if (_reconnect) {
			NSLog(@"MKConnection: Reconnecting...");
			_reconnect = NO;
            _readyVoice = NO;
		}

		CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault,
										   (CFStringRef)_hostname, _port,
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

		while (_keepRunning) {
			if (_reconnect)
				break;
			[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
		}

		if (_udpSock) {
			[self _teardownUdpSock];
		}

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

		// Tell our delegate that we've been disconnected from the server.
		if ([_delegate respondsToSelector:@selector(connectionClosed:)]) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[_delegate connectionClosed:self];
			});
		}
	} while (_reconnect);

	[NSThread exit];
}

- (void) _wakeRunLoopHelper:(id)noObject {
	CFRunLoopRef runLoop = [[NSRunLoop currentRunLoop] getCFRunLoop];
	CFRunLoopWakeUp(runLoop);
}

- (void) _wakeRunLoop {
	[self performSelector:@selector(_wakeRunLoopHelper:) onThread:self withObject:nil waitUntilDone:NO];
}

- (void) connectToHost:(NSString *)hostName port:(NSUInteger)portNumber {
	NSAssert(![self isExecuting], @"Thread is currently executing. Can't start another one.");

	packetLength = -1;
	_connectionEstablished = NO;
	_hostname = hostName;
	_port = portNumber;
	_keepRunning = YES;
    _readyVoice = NO;

    [[MKConnectionController sharedController] addConnection:self];

	[self start];
}

- (void) disconnect {
    [[MKConnectionController sharedController] removeConnection:self];

	if (![self isExecuting])
		return;
	_keepRunning = NO;
	[self _wakeRunLoop];
	while ([self isExecuting] && ![self isFinished]) {
		// Wait for the thread to be done...
	}
}

- (void) reconnect {
	_reconnect = YES;
	[self _wakeRunLoop];
}

- (BOOL) connected {
	return _connectionEstablished;
}

// Get the hostname the MKConnection is connected to.
- (NSString *) hostname {
	return _hostname;
}

// Get the port number the MKConnection is connected to.
- (NSUInteger) port {
	return _port;
}

// Sets the SecIdentityRef the client should use for authenticating
// with the server.
- (void) setClientIdentity:(SecIdentityRef)secIdentity {
	_clientIdentity = (SecIdentityRef)CFRetain(secIdentity);
}

// Returns the current clientIdentity.
- (SecIdentityRef) clientIdentity {
	return _clientIdentity;
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
	// Exception for incoming messages.
	if (stream == _inputStream) {
		if (eventCode == NSStreamEventHasBytesAvailable)
			[self _dataReady];
		return;
	}

	switch (eventCode) {
		// The OpenCompleted event is a bad indicator of 'ready to use' for a TLS
		// socket, since it will be fired before the TLS handshake. Thus, we only
		// use this event for grabbing a native handle to our socket and for establishing
		// an UDP connection (for voice) to the server.  For an indication of a finished
		// TLS handshake, we use the NSStreamEventHasSpaceAvailable instead.
		case NSStreamEventOpenCompleted: {

			// Fetch a native handle to our socket
			CFDataRef nativeHandle = CFWriteStreamCopyProperty((CFWriteStreamRef) _outputStream, kCFStreamPropertySocketNativeHandle);
			if (nativeHandle) {
				_socket = *(int *)CFDataGetBytePtr(nativeHandle);
				CFRelease(nativeHandle);
			} else {
				NSLog(@"MKConnection: Unable to get socket file descriptor from stream. Breakage may occur.");
			}

			// Set our connTime to the timestamp at connect-time.
			_connTime = [self _currentTimeStamp];

			// Disable Nagle's algorithm
			if (_socket != -1) {
				int val = 1;
				setsockopt(_socket, IPPROTO_TCP, TCP_NODELAY, &val, sizeof(val));
				NSLog(@"MKConnection: TCP_NODELAY=1");
			}

			// Setup UDP connection
			[self _setupUdpSock];

			break;
		}

		case NSStreamEventHasSpaceAvailable: {
			// The first time we're called with NSStreamHasSpaceAvailable, we can
			// be sure that the TLS handshake has finished successfully.  In here
			// we setup our ping timer and tell our delegate that we've successfully
			// opened a connection to the server.
			if (! _connectionEstablished) {
				_connectionEstablished = YES;

				// Schedule our ping timer.
				_pingTimer = [NSTimer timerWithTimeInterval:MKConnectionPingInterval target:self selector:@selector(_pingTimerFired:) userInfo:nil repeats:YES];
				[[NSRunLoop currentRunLoop] addTimer:_pingTimer forMode:NSRunLoopCommonModes];

				// Tell our delegate that we're connected to the server.
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
			[self _handleError:err];
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
		if (_clientIdentity) {
			CFArrayRef array = CFArrayCreate(kCFAllocatorDefault, (const void **)&_clientIdentity, 1, NULL);
			CFDictionaryAddValue(sslDictionary, kCFStreamSSLCertificates, array);
			CFRelease(array);
		}

		CFWriteStreamSetProperty((CFWriteStreamRef) _outputStream, kCFStreamPropertySSLSettings, sslDictionary);
		CFReadStreamSetProperty((CFReadStreamRef) _inputStream, kCFStreamPropertySSLSettings, sslDictionary);
		CFRelease(sslDictionary);
	}
}

// Initialize the UDP connection-part of an MKConnection.
//
// Must be called after a TCP connection is already in place
// (since it assembles the address it connects to by querying
// the address of the TCP socket.)
//
// Must also be called from the MKConnection thread, because
// the function adds the UDP socket to the thread's runloop.
- (void) _setupUdpSock {
	CFSocketContext udpctx;
	memset(&udpctx, 0, sizeof(CFSocketContext));
	udpctx.info = self;

	_udpSock = CFSocketCreate(NULL, PF_INET, SOCK_DGRAM, IPPROTO_UDP,
								  kCFSocketDataCallBack, MKConnectionUDPCallback,
								  &udpctx);
	if (! _udpSock) {
		NSLog(@"MKConnection: Failed to create UDP socket.");
		return;
	}

	// Add the UDP socket to the runloop of the MKConnection thread.
	CFRunLoopSourceRef src = CFSocketCreateRunLoopSource(NULL, _udpSock, 0);
	CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopDefaultMode);
    CFRelease(src);

	// Get the peer address of the TCP socket (i.e. the host)
	struct sockaddr sa;
	socklen_t sl = sizeof(struct sockaddr);
	if (getpeername(_socket, &sa, &sl) == -1) {
		NSLog(@"MKConnection: Unable to query TCP socket for address.");
		return;
	}

	NSData *_udpAddr = [[[NSData alloc] initWithBytes:&sa length:(NSUInteger)sl] autorelease];
	CFSocketError err = CFSocketConnectToAddress(_udpSock, (CFDataRef)_udpAddr, -1);
	if (err == kCFSocketError) {
		NSLog(@"MKConnection: Unable to CFSocketConnectToAddress()");
		return;
	}
}

// Tear down the UDP connection-part of an MKConnection.
//
// Can only be called if _setupUdpSock has successfully created
// a UDP socket. (_udpSock != nil)
- (void) _teardownUdpSock {
	CFSocketInvalidate(_udpSock);
	CFRelease(_udpSock);
}

// Force the connection to ignore any SSL errors that occur.  This is a
// dirty hack forced upon us by Apple's NSStream/CFStream SSL API on
// iOS.  There's no real way to hook into the TLS handshake process,
// so to be able to connect to servers that use a self-signed certificate
// we have to set this flag.
//
// The use case for this is that a program using the MKConnection class will
// connect to the server, and if the connection fails because of TLS handshake
// error, it will fetch the server's certificate chain through a call to
// peerCertificates. It will then compare the returned certificate chain with a
// cached certificate chain for the server (if the client has connected to the
// server before) or cache the server's certificate chain.
// If the certificate chain matches what's already on file we're good to go and
// can do something like:
//
//   [conn setIgnoreSSLVerification:YES];
//   [conn reconnect];
//
// Then, before any Mumble messages go over the wire the client can check that the
// certificate given to it by the server matches what's on file again, just to make
// sure everything matches up.
//
// Ideally, one would be able to trust certain self-signed certificates and be done
// with it, but instead one has to go through this hassle of manually checking the
// certificates each time.
- (void) setIgnoreSSLVerification:(BOOL)flag {
	_ignoreSSLVerification = flag;
}

// Returns the certificates of the peer of connection. That is, the server's certificate chain.
- (NSArray *) peerCertificates {
	if (_peerCertificates != nil) {
		return _peerCertificates;
	}

	NSArray *secCerts = (NSArray *) CFWriteStreamCopyProperty((CFWriteStreamRef) _outputStream, kCFStreamPropertySSLPeerCertificates);
	_peerCertificates = [[NSMutableArray alloc] initWithCapacity:[secCerts count]];
	[secCerts enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		NSData *data = (NSData *) SecCertificateCopyData((SecCertificateRef)obj);
		[_peerCertificates addObject:[MKCertificate certificateWithCertificate:data privateKey:nil]];
		[data release];
	}];
    [secCerts release];

	return _peerCertificates;
}

// Force the MKConnection into TCP mode, forcing all voice data to
// be tunelled through TCP instead of being transmitted via UDP.
- (void) setForceTCP:(BOOL)flag {
	_forceTCP = flag;
}

// Return the current TCP mode status
- (BOOL) forceTCP {
	return _forceTCP;
}

// Send a UDP message.  This method encrypts the message using the connection's
// current CryptState before sending it to the server.
// Message identity information is stored as part of the first byte of 'data'.
- (void) _sendUDPMessage:(NSData *)data {
	// We need a valid CryptState and a valid UDP socket to send UDP datagrams.
	if (![_crypt valid] || !CFSocketIsValid(_udpSock)) {
		NSLog(@"MKConnection: Invalid CryptState or CFSocket.");
		return;
	}

	NSData *crypted = [_crypt encryptData:data];
	CFSocketError err = CFSocketSendData(_udpSock, NULL, (CFDataRef)crypted, -1.0f);
	if (err != kCFSocketSuccess) {
		NSLog(@"MKConnection: CFSocketSendData failed with err=%i", (int)err);
	}
}

// Send a control-channel message to the server.  This may be called from any thread,
// but will be synchronized onto MKConnection's own thread in the end.
- (void) sendMessageWithType:(MKMessageType)messageType data:(NSData *)data {
	NSDictionary *dict = [[NSDictionary alloc] initWithObjectsAndKeys:
							data, @"data",
							[NSNumber numberWithInt:(int)messageType], @"messageType",
							nil];

	// Were we called from another thread? Synchronize onto the MKConnection thread.
	if ([NSThread currentThread] != self) {
		[self performSelector:@selector(_sendMessageHelper:) onThread:self withObject:dict waitUntilDone:NO];

	// If we were called from our own thread, just call the wrapper directly.
	} else {
		[self _sendMessageHelper:dict];
	}

	[dict release];
}

// This is a helper function for dispatching a sendMessageWithType:data: method call
// onto MKConnection's own thread.  This method is called by sendMessageWithType:data:,
// passing in its two arguments in a dictionary with the keys "data" and "messageType".
//
// This message should only be called from MKConnection's own thread.
- (void) _sendMessageHelper:(NSDictionary *)dict {
	NSData *data = [dict objectForKey:@"data"];
	MKMessageType messageType = (MKMessageType)[[dict objectForKey:@"messageType"] intValue];
    
	UInt16 type = CFSwapInt16HostToBig((UInt16)messageType);
	UInt32 length = CFSwapInt32HostToBig([data length]);

	NSUInteger expectedLength = sizeof(UInt16) + sizeof(UInt32) + [data length];
	NSMutableData *msg = [[NSMutableData alloc] initWithCapacity:expectedLength];
	[msg appendBytes:&type length:sizeof(UInt16)];
	[msg appendBytes:&length length:sizeof(UInt32)];
	[msg appendData:data];

	NSInteger nwritten = [_outputStream write:[msg bytes] maxLength:[msg length]];
    if (nwritten != expectedLength) {
		NSLog(@"MKConnection: write error, wrote %li, expected %u", nwritten, expectedLength);
    }
	[msg release];
}

// Send a voice packet to the server.  The method will automagically figure
// out whether it should be sent via UDP or TCP depending on the current
// connection conditions.
- (void) sendVoiceData:(NSData *)data {
    if (!_readyVoice)
        return;
	if (!_forceTCP && _udpAvailable) {
		[self _sendUDPMessage:data];
	} else {
		[self sendMessageWithType:UDPTunnelMessage data:data];
	}
}

// New UDP packet received.  This method is called by MKConnection's
// MKUDPMessageCallback function whenever a new datagram has been received
// by our UDP socket.  The method will decrypt the received datagram and
// pass it onto the _udpMessageReceived: method (with the plain data as
// its parameter).
//
// The reason this method exists is that Mumble can tunnel UDP packets over
// TCP, and in that case, the packets are not encrypted with OCB-AES128
// because they will be tunneled through a TLS connection that is already
// encrypted using whichever cipher was agreed upon during the handshake.
// These tunelled UDP messages do not go through this method, but go directly
// to the _udpMessageReceived: method instead.
- (void) _udpDataReady:(NSData *)crypted {
	// For now, let's just do this to enable UDP. fixme(mkrautz): Better detection.
	if (! _udpAvailable) {
		_udpAvailable = true;
		NSLog(@"MKConnection: UDP is now available!");
	}

	if ([crypted length] > 4) {
		NSData *plain = [_crypt decryptData:crypted];
		[self _udpMessageReceived:plain];
	}
}

// This method is called by our NSStream delegate methods whenever
// it has received a chunk of data via TCP.  This method then fills
// it internal buffer until it has received a full Mumble message.
//
// When a complete message has been received, it calls the
// _messageReceived: method with the full received data as its
// argument.
- (void) _dataReady {
	unsigned char buffer[6];

	// Allocate a packet buffer if there isn't one available
	// already.
	if (! packetBuffer) {
		packetBuffer = [[NSMutableData alloc] initWithLength:0];
	}

	// Not currently receiving a message. This is the first part of
	// a message.
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

	// Receive in progress.
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

	// Done.
	if (packetLength == 0) {
		[self _messageRecieved:packetBuffer];
		[packetBuffer setLength:0]; // fixme(mkrautz): Is this one needed?
		packetLength = -1;
	}
}

// Returns the number of usecs since the Unix epoch.
- (uint64_t) _currentTimeStamp {
	struct timeval tv;
	gettimeofday(&tv, NULL);

	uint64_t ret = tv.tv_sec * 1000000ULL;
	ret += tv.tv_usec;

	return ret;
}

// Ping timer fired. Time to ping the server!
- (void) _pingTimerFired:(NSTimer *)timer {
	unsigned char buf[16];
	NSData *data;
	uint64_t timeStamp = [self _currentTimeStamp] - _connTime;

	// First, do a UDP ping...
	MKPacketDataStream *pds = [[MKPacketDataStream alloc] initWithBuffer:buf+1 length:16];
	buf[0] = UDPPingMessage << 5;
	[pds addVarint:timeStamp];
	if ([pds valid]) {
		data = [[NSData alloc] initWithBytesNoCopy:buf length:[pds size]+1 freeWhenDone:NO];
		[self _sendUDPMessage:data];
		[data release];
	}
	[pds release];
		
	// Then the TCP ping...
	MPPing_Builder *ping = [MPPing builder];

	[ping setTimestamp:timeStamp];

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

// The server rejected our connection.
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

	[self disconnect];
}

// Handle server crypt setup
- (void) _doCryptSetup:(MPCryptSetup *)cryptSetup {
	NSLog(@"MKConnection: Got CryptSetup from server.");

	// A full setup message. Initialize our CryptState.
	if ([cryptSetup hasKey] && [cryptSetup hasClientNonce] && [cryptSetup hasServerNonce]) {
		[_crypt setKey:[cryptSetup key] eiv:[cryptSetup clientNonce] div:[cryptSetup serverNonce]];
		NSLog(@"MKConnection: CryptState initialized.");
	}
}

// Handle incoming version information from the server.
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

// Handle codec changes
- (void) _codecChange:(MPCodecVersion *)codec {
	static const unsigned int ourCodec = 0x8000000b;

	NSInteger alpha = [codec hasAlpha] ? [codec alpha] : -1;
	NSInteger beta = [codec hasBeta] ? [codec beta] : -1;
	BOOL pref = [codec hasPreferAlpha] ? [codec preferAlpha] : NO;

	if ((alpha != -1) && (alpha != _alphaCodec)) {
		if (pref && alpha != ourCodec)
			pref = ! pref;
	}
	if ((beta != -1) && (beta != _betaCodec)) {
		if (! pref && beta != ourCodec)
			pref = ! pref;
	}

	_alphaCodec = alpha;
	_betaCodec = beta;
	_preferAlpha = pref;
}

- (void) _handleError:(NSError *)streamError {
	NSInteger errorCode = [streamError code];

	/* Is the error an SSL-related error? (OSStatus errors are negative, so the
	 * greater than and less than signs are sort-of reversed here. */
	if (errorCode <= errSSLProtocol && errorCode > errSSLLast) {
		[self _handleSslError:streamError];
	}

	NSLog(@"MKConnection: Error: %@", streamError);
}

- (void) _handleSslError:(NSError *)streamError {
	if ([streamError code] == errSSLXCertChainInvalid
        || [streamError code] == errSSLUnknownRootCert) {
		SecTrustRef trust = (SecTrustRef) CFWriteStreamCopyProperty((CFWriteStreamRef) _outputStream, kCFStreamPropertySSLPeerTrust);
		SecTrustResultType trustResult;
		if (SecTrustEvaluate(trust, &trustResult) != noErr) {
			// Unable to evaluate trust.
		}

		switch (trustResult) {
			// Invalid setting or result. Indicates the SecTrustEvaluate() did not finish completely.
			case kSecTrustResultInvalid:
			// May be trusted for the purposes designated. ('Always Trust' in Keychain)
			case kSecTrustResultProceed:
			// User confirmation is required before proceeding. ('Ask Permission' in Keychain)
			case kSecTrustResultConfirm:
			// This certificate is not trusted. ('Never Trust' in Keychain)
			case kSecTrustResultDeny:
			// No trust setting specified. ('Use System Policy' in Keychain)
			case kSecTrustResultUnspecified:
			// Fatal trust failure. Trust cannot be established without replacing the certificate.
			// This error is thrown when the certificate is corrupt.
			case kSecTrustResultFatalTrustFailure:
			// A non-trust related error. Possibly internal error in SecTrustEvaluate().
			case kSecTrustResultOtherError:
				break;

			// A recoverable trust failure.
			case kSecTrustResultRecoverableTrustFailure: {
				if ([_delegate respondsToSelector:@selector(connection:trustFailureInCertificateChain:)]) {
					dispatch_async(dispatch_get_main_queue(), ^{
						[_delegate connection:self trustFailureInCertificateChain:[self peerCertificates]];
					});
				}
			}
		}

		CFRelease(trust);
	}
}

// This is the entry point for UDP packets after they've been decrypted,
// and also for UDP packets that are tunneled through the TCP stream.
- (void) _udpMessageReceived:(NSData *)data {
	unsigned char *buf = (unsigned char *)[data bytes];
	MKUDPMessageType messageType = ((buf[0] >> 5) & 0x7);
	unsigned int messageFlags = buf[0] & 0x1f;
	MKPacketDataStream *pds = [[MKPacketDataStream alloc] initWithBuffer:buf+1 length:[data length]-1]; // fixme(-1)?

	switch (messageType) {
		case UDPVoiceCELTAlphaMessage:
		case UDPVoiceCELTBetaMessage:
		case UDPVoiceSpeexMessage: {
			NSUInteger session = [pds getUnsignedInt];
			NSUInteger seq = [pds getUnsignedInt];
			NSMutableData *voicePacketData = [[NSMutableData alloc] initWithCapacity:[pds left]+1];
			[voicePacketData setLength:[pds left]+1];
			unsigned char *bytes = [voicePacketData mutableBytes];
			bytes[0] = (unsigned char)messageFlags;
			memcpy(bytes+1, [pds dataPtr], [pds left]);
			[[MKAudio sharedAudio] addFrameToBufferWithSession:session data:voicePacketData sequence:seq type:messageType];
			[voicePacketData release];
			break;
		}

		case UDPPingMessage: {
			uint64_t timeStamp = [pds getVarint];
			uint64_t now = [self _currentTimeStamp] - _connTime;
			NSLog(@"UDP ping = %llu usec", now - timeStamp); 
			break;
		}

		default:
			NSLog(@"MKConnection: Unknown UDPTunnel packet (%i) received. Discarding...", (int)messageType);
			break;
	}

	[pds release];
}


- (void) _messageRecieved:(NSData *)data {
	dispatch_queue_t main_queue = dispatch_get_main_queue();

	/* No message handler has been assigned. Don't propagate. */
	if (! _msgHandler)
		return;

	switch (packetType) {
		// A UDP message tunneled through our TCP control channel.
		// Pass it on to our incoming UDP handler.
		case UDPTunnelMessage: {
			[self _udpMessageReceived:data];
			break;
		}
		case ServerSyncMessage: {
			if (_forceTCP) {
				// Send a dummy UDPTunnel message so the server knows that we're running
				// in TCP mode.
				NSLog(@"MKConnection: Sending dummy UDPTunnel message.");
				NSMutableData *msg = [[NSMutableData alloc] initWithLength:3];
				char *buf = [msg mutableBytes];
				memset(buf, 0, 3);
				[self sendMessageWithType:UDPTunnelMessage data:msg];
				[msg release];
			}
            _readyVoice = YES;
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
		case ContextActionModifyMessage: {
			MPContextActionModify *contextActionModify = [MPContextActionModify parseFromData:data];
			if ([_msgHandler respondsToSelector:@selector(connection:handleContextActionModifyMessage:)]) {
				dispatch_async(main_queue, ^{
					[_msgHandler connection:self handleContextActionModifyMessage:contextActionModify];
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
		case CodecVersionMessage: {
			MPCodecVersion *codecVersion = [MPCodecVersion parseFromData:data];
			[self _codecChange:codecVersion];
			break;
		}

		default: {
			NSLog(@"MKConnection: Unknown packet type recieved. Discarding. (type=%u)", packetType);
			break;
		}
	}
}

- (NSInteger) alphaCodec {
	return _alphaCodec;
}

- (NSInteger) betaCodec {
	return _betaCodec;
}

- (BOOL) preferAlphaCodec {
	return _preferAlpha;
}

@end