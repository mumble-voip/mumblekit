// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKServices.h>

@implementation MKServices

+ (NSString *) regionalServicesHost {
	return nil;
}

/*
 * Public server list
 */

+ (NSString *) regionalServerList {
	return @"https://publist.mumble.info/v1/list";
}

+ (NSURL *) regionalServerListURL {
	return [NSURL URLWithString:[MKServices regionalServerList]];
}

@end
