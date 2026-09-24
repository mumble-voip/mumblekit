// Copyright 2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <Foundation/Foundation.h>

@interface MKDistinguishedNameParser : NSObject
+ (NSDictionary *) parseName:(NSData *)dn;
@end
