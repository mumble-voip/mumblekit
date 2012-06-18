//
//  MKACL.h
//  MumbleKit
//
//  Created by Emilio Pavia on 14/06/12.
//  Copyright (c) 2012 TOK.TV Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface MKACL : NSObject

@property (nonatomic) BOOL inheritACLs;
@property (nonatomic, strong) NSMutableArray *groups;
@property (nonatomic, strong) NSMutableArray *acls;

@end
