// Copyright 2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKPermission.h>

@interface MKChannelACL : NSObject

@property (nonatomic) BOOL applyHere;
@property (nonatomic) BOOL applySubs;
@property (nonatomic) BOOL inherited;
@property (nonatomic) NSInteger userID;
@property (nonatomic, strong) NSString * group;
@property (nonatomic) MKPermission grant;
@property (nonatomic) MKPermission deny;
@property (nonatomic, readonly) BOOL hasUserID;

@end
