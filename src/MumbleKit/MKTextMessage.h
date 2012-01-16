/* Copyright (C) 2009-2012 Mikkel Krautz <mikkel@krautz.dk>

   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions
   are met:

   - Redistributions of source code must retain the above copyright notice,
     this list of conditions and the following disclaimer.
   - Redistributions in binary form must reproduce the above copyright notice,
     this list of conditions and the following disclaimer in the documentation
     and/or other materials provided with the distribution.
   - Neither the name of the Mumble Developers nor the names of its
     contributors may be used to endorse or promote products derived from this
     software without specific prior written permission.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
   ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
   LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
   A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE FOUNDATION OR
   CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
   EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
   PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
   PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
   LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
   NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

@interface MKTextMessage : NSObject

/**
 * Create a new MKTextMessage with the plain text representation given in
 * msg.
 *
 * @param msg  The plain text version of the text message.
 *
 * @returns Returns a MKTextMessage object that can be sent using an
 *          MKServerModel.
 */
+ (MKTextMessage *) messageWithPlainText:(NSString *)msg;

/**
 * Create a new MKTextMessage with HTML representation given in html.
 *
 * @param msg  The HTML representing the text message.
 *
 * @returns Returns a MKTextMessage object that can be sent using an
 *          MKServerModel.
 */
+ (MKTextMessage *) messageWithHTML:(NSString *)html;

/**
 * Create a new MKTextMessage with the given string. The internal representation
 * is chosen depending on the content of the message.
 *
 * @param str  A string representing the message to create. This string can be either
 *             a plain text string, or an HTML string. MKTextMessage will detect this
 *             itself and handle the message accordingly.
 *
 * @returns Returns a MKTextMessage object that can be sent using an
 *          MKServerModel.
 */
+ (MKTextMessage *) messageWithString:(NSString *)str;

/**
 * Returns the text message represented in plain text. If the message was
 * an HTML formatted message, the formatting will be stripped, and a plain
 * text string will be returned.
 *
 * @returns A plain text representation of the text message. If the message
 *          has a plain text representation, that is returned. If the message
 *          is an HTML message, it will be lossily converted to plain text.
 */
- (NSString *) plainTextString;

/**
 * Returns an HTML representation of the text message.
 *
 * @returns Returns an HTML version of the text message. If there is no HTML
 *          version, a plain text version is returned.
 */
- (NSString *) HTMLString;

/**
 * Returns all links found in the text message.
 *
 * @returns Returns an NSArray of NSStrings corresponding to the href attributes of any a tags
 *          found in the text message.
 */
- (NSArray *) embeddedLinks;

/**
 * Returns all embedded images found in the text message. (Only images with data URIs are
 * considered valid).
 *
 * @returns Returns an NSArray of all images found in the text message. The images are
 *          represented as data URIs.
 */
- (NSArray *) embeddedImages;

@end
