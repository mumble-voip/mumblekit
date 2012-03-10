// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKConnectionController.h>
#import <MumbleKit/MKConnection.h>

@interface MKConnectionController () {
    NSMutableArray *_openConnections;
}

- (id) init;
- (void) dealloc;

@end

@implementation MKConnectionController

- (id) init {
    if ((self = [super init])) {
        _openConnections = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void) dealloc {
    [_openConnections release];
    [super dealloc];
}

+ (MKConnectionController *) sharedController {
    static dispatch_once_t pred;
    static MKConnectionController *controller;

    dispatch_once(&pred, ^{
        controller = [[MKConnectionController alloc] init]; 
    });

    return controller;
}
                                
- (void) addConnection:(MKConnection *)conn {
    [_openConnections addObject:[NSValue valueWithNonretainedObject:conn]];
}

- (void) removeConnection:(MKConnection *)conn {
    [_openConnections removeObject:[NSValue valueWithNonretainedObject:conn]];
}

- (NSArray *) allConnections {
    return _openConnections;
}

@end
