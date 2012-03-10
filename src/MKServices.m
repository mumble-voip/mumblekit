// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKServices.h>

@implementation MKServices

+ (NSString *) regionalServicesHost {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *languages = [defaults objectForKey:@"AppleLanguages"];
    NSString *locale = [languages objectAtIndex:0];
    return [NSString stringWithFormat:@"http://%@.mumble.info", locale];
}

/*
 * Public server list
 */

+ (NSString *) regionalServerList {
    return [NSString stringWithFormat:@"%@/list2.cgi", [MKServices regionalServicesHost]];
}

+ (NSURL *) regionalServerListURL {
    return [NSURL URLWithString:[MKServices regionalServerList]];
}

@end
