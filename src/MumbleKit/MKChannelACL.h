//
//  MKChannelACL.h
//  MumbleKit
//
//  Created by Emilio Pavia on 17/06/12.
//  Copyright (c) 2012 TOK.TV Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <MumbleKit/MKPermission.h>

@interface MKChannelACL : NSObject

@property (nonatomic) BOOL applyHere;
@property (nonatomic) BOOL applySubs;
@property (nonatomic) BOOL inherited;
@property (nonatomic) NSInteger userID;
@property (nonatomic, strong) NSString *group;
@property (nonatomic) MKPermission grant;
@property (nonatomic) MKPermission deny;
@property (nonatomic, readonly) BOOL hasUserID;

@end
