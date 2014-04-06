// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKTextMessage.h>

@interface MKTextMessage () <NSXMLParserDelegate> {
    NSString         *_rawStr;
    NSMutableString  *_plainStr;
    NSString         *_filteredStr;
    NSMutableArray   *_imagesArray;
    NSMutableArray   *_linksArray;
}
- (id) initWithString:(NSString *)str;
@end

@implementation MKTextMessage

- (id) initWithString:(NSString *)str {
    if ((self = [super init])) {
        _rawStr = [str retain];
        _imagesArray = [[NSMutableArray alloc] init];
        _linksArray = [[NSMutableArray alloc] init];
        NSRange r = [_rawStr rangeOfString:@"<"];
        BOOL possiblyHtml = r.location != NSNotFound;
        if (possiblyHtml) {
            _plainStr = [[NSMutableString alloc] init];
            NSXMLParser *xmlParser = [[NSXMLParser alloc] initWithData:[[NSString stringWithFormat:@"<doc>%@</doc>", _rawStr] dataUsingEncoding:NSUTF8StringEncoding]];
            [xmlParser setDelegate:self];
            [xmlParser parse];
            [xmlParser release];

            // Strip extra whitespace
            NSMutableData *filtered = [[NSMutableData alloc] init];
            NSCharacterSet *whitespaceNewlineSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
            NSUInteger i, len = [_plainStr length];
            unichar lastc = 0;
            for (i = 0; i < len; i++) {
                unichar c = [_plainStr characterAtIndex:i];
                if ([whitespaceNewlineSet characterIsMember:c]) {
                    if (lastc != c)
                        [filtered appendBytes:&c length:2];
                } else {
                    [filtered appendBytes:&c length:2];
                }
                lastc = c;
            }

            [_plainStr release];
            _plainStr = nil;
            _filteredStr = [[NSString stringWithCharacters:[filtered bytes] length:[filtered length]/2] retain];
            [filtered release];
        }
    }

    return self;
}

- (void) dealloc {
    [_rawStr release];
    [_plainStr release];
    [_imagesArray release];
    [_linksArray release];
    [super dealloc];
}

+ (MKTextMessage *) messageWithString:(NSString *)msg {
    return [[[MKTextMessage alloc] initWithString:msg] autorelease];
}

+ (MKTextMessage *) messageWithPlainText:(NSString *)msg {
    return [[[MKTextMessage alloc] initWithString:msg] autorelease];
}

+ (MKTextMessage *) messageWithHTML:(NSString *)msg {
    return [[[MKTextMessage alloc] initWithString:msg] autorelease];
}

- (NSString *) plainTextString {
    if (_filteredStr != nil) {
        return _filteredStr;
    }
    return _rawStr;
}

- (NSString *) HTMLString {
    return _rawStr;
}

- (NSArray *) embeddedLinks {
    return _linksArray;
}

- (NSArray *) embeddedImages {
    return _imagesArray;
}

#pragma mark - NSXMLParserDelegate

- (void) parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict {
    if ([elementName isEqualToString:@"img"]) {
        NSString *src = [attributeDict objectForKey:@"src"];
        if ([src hasPrefix:@"data:"]) {
            [_imagesArray addObject:src];
        }
    } else if ([elementName isEqualToString:@"a"]) {
        NSString *href = [attributeDict objectForKey:@"href"];
        if (href) {
            [_linksArray addObject:href];
        }
    }
}

- (void) parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if ([elementName isEqualToString:@"br"] || [elementName isEqualToString:@"p"])
        [_plainStr appendString:@"\n"];
}

- (void) parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    [_plainStr appendString:string];
}

@end
