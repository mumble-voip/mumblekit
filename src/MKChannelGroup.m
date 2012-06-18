//
//  MKChannelGroup.m
//  MumbleKit
//
//  Created by Emilio Pavia on 17/06/12.
//  Copyright (c) 2012 TOK.TV Inc. All rights reserved.
//

#import "MKChannelGroup.h"

@implementation MKChannelGroup

@synthesize name;
@synthesize inherited;
@synthesize inherit;
@synthesize inheritable;
@synthesize members;
@synthesize excludedMembers;
@synthesize inheritedMembers;

- (NSString *)description
{
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
