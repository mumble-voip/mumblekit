// Copyright 2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MKAccessControl.h"

@implementation MKAccessControl

@synthesize inheritACLs;
@synthesize groups;
@synthesize acls;

- (NSString *) description {
    return [NSString stringWithFormat:@"{\n\tinheritACLs: %@\n\tgroups: %@\n\tacls: %@\n}", self.inheritACLs ? @"YES" : @"NO", self.groups, self.acls];
}

@end
