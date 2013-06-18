// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/// @class MKServices MKServices.h MumbleKit/MKServices.h
///
/// MKServices implements convenience methods for accessing publicly available
/// Mumble services.
@interface MKServices : NSObject

/// Get the hostname of the closest regional services host.
+ (NSString *) regionalServicesHost;

/// Get the URL of the server list on a server near the client's current location.
+ (NSString *) regionalServerList;

/// Returns an NSURL version of the URL returned by regionalServerList.
+ (NSURL *) regionalServerListURL;

@end
