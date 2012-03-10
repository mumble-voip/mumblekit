// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKVersion.h>

@interface MKVersion () {
    NSString  *_overrideReleaseString;
    BOOL      _opusEnabled;
}
@end

@implementation MKVersion

+ (MKVersion *) sharedVersion {
    static dispatch_once_t pred;
    static MKVersion *vers;
    
    dispatch_once(&pred, ^{
        vers = [[MKVersion alloc] init];
    });
    
    return vers;
}

- (id) init {
    if ((self = [super init])) {
        // ...
    }
    return self;
}

- (void) dealloc {
    [_overrideReleaseString release];
    [super dealloc];
}

- (NSUInteger) hexVersion {
    return 0x10204;
}

- (void) setOverrideReleaseString:(NSString *)releaseString {
    [_overrideReleaseString release];
    _overrideReleaseString = [releaseString retain];
}

- (void) setOpusEnabled:(BOOL)isEnabled {
    _opusEnabled = isEnabled;
}

- (BOOL) isOpusEnabled {
    return _opusEnabled;
}

- (NSString *) releaseString {
    if (_overrideReleaseString) {
        return _overrideReleaseString;
    }
    return @"MumbleKit";
}

@end
