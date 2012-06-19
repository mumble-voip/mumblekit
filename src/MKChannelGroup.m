// Copyright 2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MKChannelGroup.h"

@implementation MKChannelGroup

@synthesize name;
@synthesize inherited;
@synthesize inherit;
@synthesize inheritable;
@synthesize members;
@synthesize excludedMembers;
@synthesize inheritedMembers;

- (NSString *) description {
    return [NSString stringWithFormat:@"{name: %@; inherited: %@; inherit: %@; inheritable: %@; members: %@; excludedMembers: %@; inheritedMembers: %@}",
            self.name,
            self.inherited ? @"YES" : @"NO",
            self.inherit ? @"YES" : @"NO",
            self.inheritable ? @"YES" : @"NO",
            self.members,
            self.excludedMembers,
            self.inheritedMembers];
}
@end
