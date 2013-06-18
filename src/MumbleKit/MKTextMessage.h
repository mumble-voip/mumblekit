// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/// @class MKTextMessage MKTestMessage.h MumbleKit/MKTextMessage.h
@interface MKTextMessage : NSObject

/// Create a new MKTextMessage with the plain text representation given in
/// msg.
///
/// @param msg  The plain text version of the text message.
///
/// @returns Returns a MKTextMessage object that can be sent using an
///          MKServerModel.
+ (MKTextMessage *) messageWithPlainText:(NSString *)msg;

/// Create a new MKTextMessage with HTML representation given in html.
///
/// @param html  The HTML representing the text message.
///
/// @returns Returns a MKTextMessage object that can be sent using an
///          MKServerModel.
+ (MKTextMessage *) messageWithHTML:(NSString *)html;

/// Create a new MKTextMessage with the given string. The internal representation
/// is chosen depending on the content of the message.
///
/// @param str  A string representing the message to create. This string can be either
///             a plain text string, or an HTML string. MKTextMessage will detect this
///             itself and handle the message accordingly.
///
/// @returns Returns a MKTextMessage object that can be sent using an
///          MKServerModel.
+ (MKTextMessage *) messageWithString:(NSString *)str;

/// Returns the text message represented in plain text. If the message was
/// an HTML formatted message, the formatting will be stripped, and a plain
/// text string will be returned.
///
/// @returns A plain text representation of the text message. If the message
///          has a plain text representation, that is returned. If the message
///          is an HTML message, it will be lossily converted to plain text.
- (NSString *) plainTextString;

/// Returns an HTML representation of the text message.
///
/// @returns Returns an HTML version of the text message. If there is no HTML
///          version, a plain text version is returned.
- (NSString *) HTMLString;

/// Returns all links found in the text message.
///
/// @returns Returns an NSArray of NSStrings corresponding to the href attributes of any a tags
///          found in the text message.
- (NSArray *) embeddedLinks;

/// Returns all embedded images found in the text message. (Only images with data URIs are
/// considered valid).
///
/// @returns Returns an NSArray of all images found in the text message. The images are
///          represented as data URIs.
- (NSArray *) embeddedImages;

@end
