//
//  MKChannelGroup.h
//  MumbleKit
//
//  Created by Emilio Pavia on 17/06/12.
//  Copyright (c) 2012 TOK.TV Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MKChannelGroup : NSObject

@property (nonatomic, strong) NSString *name;
@property (nonatomic) BOOL inherited;
@property (nonatomic) BOOL inherit;
@property (nonatomic) BOOL inheritable;
@property (nonatomic, strong) NSMutableArray *members;
@property (nonatomic, strong) NSMutableArray *excludedMembers;
@property (nonatomic, strong) NSMutableArray *inheritedMembers;

@end
