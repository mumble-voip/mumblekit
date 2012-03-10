// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKConnection.h>

/**
 * MKConnectionController is a singleton controller object that holds references
 * to all active connections (instances of MKConnection).
 *
 * Internal consumers of this controller include the MKAudioInput class, which
 * must transmit audio to all active connections.
 *
 * External consumers of this controller could for example be a UI component that
 * is used to show a list of active Mumble server connections.
 */
@interface MKConnectionController : NSObject

///------------------------------------
/// Accessing the connection controller
///------------------------------------

/**
 * Get this process's instance of MKConnectionController.
 */
+ (MKConnectionController *) sharedController;

///--------------------------------
/// Adding or removing a connection
///--------------------------------

/**
 * Add a connection to the connection controller.
 * Note: This will be removed sooner or later, as it should not be part of the controller's public API.
 *
 * @param conn  The connection to add.
 */
- (void) addConnection:(MKConnection *)conn;

/**
 * Remove a connection from the connection controller.
 * Note: This will be removed sooner or later, as it should not be part of the controller's public API.
 *
 * @param conn  The connection to remove.
 */
- (void) removeConnection:(MKConnection *)conn;

///-----------------------------------------
/// Accessing the list of active connections
///-----------------------------------------

/**
 * Get a reference to an array of active connections.
 * This way of accessing connections is very fragile, since concurrent access
 * to the array are not currently handled.
 */
- (NSArray *) allConnections;

@end
