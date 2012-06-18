//
//  MKACL.m
//  MumbleKit
//
//  Created by Emilio Pavia on 14/06/12.
//  Copyright (c) 2012 TOK.TV Inc. All rights reserved.
//

#import "MKACL.h"

@implementation MKACL

@synthesize inheritACLs;
@synthesize groups;
@synthesize acls;

- (NSString *)description
{
    return [NSString stringWithFormat:@"{\n\tinheritACLs: %@\n\tgroups: %@\n\tacls: %@\n}", self.inheritACLs ? @"YES" : @"NO", self.groups, self.acls];
}

@end
