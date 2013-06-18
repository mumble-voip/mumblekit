// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/// @class MKVersion MKVersion.h MumbleKit/MKVersion.h
@interface MKVersion : NSObject
+ (MKVersion *) sharedVersion;
- (NSUInteger) hexVersion;
- (NSString *) releaseString;

- (void) setOverrideReleaseString:(NSString *)releaseString;

- (void) setOpusEnabled:(BOOL)isEnabled;
- (BOOL) isOpusEnabled;
@end
