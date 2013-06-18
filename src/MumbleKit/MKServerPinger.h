// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

typedef struct _MKServerPingerResult {
    UInt32  version;
    UInt32  cur_users;
    UInt32  max_users;
    UInt32  bandwidth;
    double  ping;
} MKServerPingerResult;

/// @protocol MKServerPingerDelegate MKServerPinger.h MumbleKit/MKServerPinger.h
@protocol MKServerPingerDelegate
- (void) serverPingerResult:(MKServerPingerResult *)result;
@end

/// @protocol MKServerPinger MKServerPinger.h MumbleKit/MKServerPinger.h
///
/// MKServerPinger implements a pinger object that can ping and query Mumble
/// servers for information typically shown in a server list.
///
/// Once a MKServerPinger object is created, it will continually ping the remote
/// server until it is destroyed. Whenever the MKServerPinger receives a reply from
/// the remote server, it will inform its delegate.
@interface MKServerPinger : NSObject

/// Initialize a new MKServerPinger that pings the server running
/// on the given hostname and port combination.
///
/// @param hostname  The hostname of the server to ping.
/// @param port      The port number of the server to ping.
///
/// @returns Returns an MKServerPinger object. To get ping results, one must
///          register a delegate implementing the MKServerPingerDelegate protocol.
- (id) initWithHostname:(NSString *)hostname port:(NSString *)port;

/// Returns the currently-set delegate for the MKServerPinger object.
///
/// @returns Returns an object implementing the MKServerPingerDelegate protocol.
- (id<MKServerPingerDelegate>)delegate;

/// Set the delegate of the MKServerPinger object. The delegate will be called
/// when the remote server responds to a ping request.
///
/// @param delegate  The objec to register as the MKServerPinger's delegate.
///                  Must implement the MKServerPingerDelegate protocol.
- (void) setDelegate:(id<MKServerPingerDelegate>)delegate;

@end
