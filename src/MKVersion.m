/* Copyright (C) 2009-2012 Mikkel Krautz <mikkel@krautz.dk>

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

#import <MumbleKit/MKVersion.h>

@interface MKVersion () {
    NSString *_overrideReleaseString;
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
    return 0x10201;
}

- (void) setOverrideReleaseString:(NSString *)releaseString {
    [_overrideReleaseString release];
    _overrideReleaseString = [releaseString retain];
}

- (NSString *) releaseString {
    if (_overrideReleaseString) {
        return _overrideReleaseString;
    }
    return @"MumbleKit";
}

@end
