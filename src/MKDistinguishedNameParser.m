// Copyright 2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MKDistinguishedNameParser.h"

@interface MKDistinguishedNameParser () {
    NSString             *_name;
    NSInteger            _pos;
    NSMutableArray       *_pairs;
}
- (id) initWithName:(NSData *)dn;

- (void) parse;
- (NSDictionary *) dictionaryRepresentation;

- (unichar) getch;
- (void) putch:(unichar)c;
- (void) rejectWithReason:(NSString *)msg;

- (void) scanAttribute;
- (void) scanAttributeName;
- (void) scanWhitespace;
- (void) scanAttributeValue;
- (void) scanCharater:(NSString *)str;
- (void) scanEquals;
- (void) scanComma;
- (void) scanAttributeValue;
- (NSString *) scanQuotedStringWithCharactersFromSet:(NSCharacterSet *)charSet;
@end

@implementation MKDistinguishedNameParser

+ (NSDictionary *) parseName:(NSData *)dn {
    MKDistinguishedNameParser *parser = [[[MKDistinguishedNameParser alloc] initWithName:dn] autorelease];
    [parser parse];
    return [parser dictionaryRepresentation];
}

- (id) initWithName:(NSData *)dn {
    if ((self = [super init])) {
        // add a junk 0 char at the end of the string to ensure termination of the scanner
        unichar nul = 0;
        NSMutableString *nameString = [[NSMutableString alloc] initWithData:dn encoding:NSUTF8StringEncoding];
        [nameString appendString:[NSString stringWithCharacters:&nul length:1]];        
        _name = nameString;
        _pairs = [[NSMutableArray alloc] init];
        _pos = 0;
    }
    return self;
}

- (void) dealloc {
    [_pairs release];
    [_name release];
    [super dealloc];
}

- (void) parse {
    while (1) {
        @try {
            [self scanAttribute];
        }
        @catch (NSException *exception) {
            return;
        }
    }
}

- (NSDictionary *) dictionaryRepresentation {
    if (([_pairs count] % 2) != 0) {
        return nil;
    }
    NSMutableDictionary *dict = [[[NSMutableDictionary alloc] initWithCapacity:[_pairs count]/2] autorelease];
    for (int i = 0; i < [_pairs count]; i += 2) {
        [dict setObject:[_pairs objectAtIndex:i+1] forKey:[_pairs objectAtIndex:i]];
    }
    return dict;
}

- (unichar) getch {
    if (_pos > [_name length]-1) {
        [self rejectWithReason:@"no more characters in string"];
    }
    return [_name characterAtIndex:_pos++];
}

- (void) putch:(unichar)c {
    _pos--;
    if (_pos < 0 || [_name characterAtIndex:_pos] != c)
       [self rejectWithReason:@"internal consistency error"]; 
}

- (void) rejectWithReason:(NSString *)msg {
    [NSException raise:@"MKDistinguishedNameParserException" format:@"%@", msg];
}

- (void) scanAttribute {
    [self scanAttributeName];
    [self scanWhitespace];
    [self scanEquals];
    [self scanWhitespace];
    [self scanAttributeValue];
    [self scanComma];
    [self scanWhitespace];
}

- (void) scanAttributeName {
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    NSMutableString *attrName = [[[NSMutableString alloc] init] autorelease];
    
    // Read at least a single 'letter'.
    unichar c = [self getch];
    if (![letters characterIsMember:c])
        [self rejectWithReason:@"bad character in attribute name"];
    [attrName appendString:[NSString stringWithCharacters:&c length:1]];
    while (1) {
        unichar c = [self getch];
        if (![letters characterIsMember:c]) {
            [self putch:c];
            [_pairs addObject:attrName];
            return;
        } else {
            [attrName appendString:[NSString stringWithCharacters:&c length:1]];
        }
    }
}

- (void) scanWhitespace {
    NSCharacterSet *whiteSpace = [NSCharacterSet whitespaceCharacterSet];
    
    // Scan at least a single whitespace character.
    unichar c = [self getch];
    if (![whiteSpace characterIsMember:c])
        [self rejectWithReason:@"expected at least 1 whitespace character"];
    while (1) {
        unichar c = [self getch];
        if (![whiteSpace characterIsMember:c]) {
            [self putch:c];
            return;
        }
    }
}

- (void) scanCharater:(NSString *)str {
    unichar matchChar = [str characterAtIndex:0];
    unichar c = [self getch]; 
    if (c != matchChar) {
        [self rejectWithReason:[NSString stringWithFormat:@"expected `%C'", matchChar]];
    }
}

- (void) scanEquals {
    [self scanCharater:@"="];
}

- (void) scanComma {
    [self scanCharater:@","];
}

- (void) scanAttributeValue {
    NSMutableCharacterSet *allAllowedChars = [[NSMutableCharacterSet alloc] init];
    [allAllowedChars formUnionWithCharacterSet:[NSCharacterSet alphanumericCharacterSet]];
    [allAllowedChars formUnionWithCharacterSet:[NSCharacterSet whitespaceCharacterSet]];
    [allAllowedChars formUnionWithCharacterSet:[NSCharacterSet symbolCharacterSet]];
    [allAllowedChars formUnionWithCharacterSet:[NSCharacterSet punctuationCharacterSet]];
    [allAllowedChars autorelease];
    
    NSMutableCharacterSet *charsOutsideQuotes = [allAllowedChars mutableCopy];
    [charsOutsideQuotes removeCharactersInString:@","];
    [charsOutsideQuotes autorelease];
    
    NSString *doubleQuote = @"\"";
    unichar quoteChar = [doubleQuote characterAtIndex:0];
    
    NSMutableString *attrValue = [[[NSMutableString alloc] init] autorelease];
    
    unichar c = [self getch];
    if (c == quoteChar) {
        [self putch:c];
        NSString *quotedString = [self scanQuotedStringWithCharactersFromSet:allAllowedChars];
        [attrValue appendString:quotedString];
    } else if (![charsOutsideQuotes characterIsMember:c]) {
        [self rejectWithReason:@"unexpected character outside of quotes"];
    } else {
        [attrValue appendString:[NSString stringWithCharacters:&c length:1]];
    }
    
    while (1) {
        unichar c = [self getch];
        if (c == quoteChar) {
            [self putch:c];
            NSString *quotedString = [self scanQuotedStringWithCharactersFromSet:allAllowedChars];
            [attrValue appendString:quotedString]; 
        } else if (![charsOutsideQuotes characterIsMember:c]) {
            [_pairs addObject:attrValue];
            [self putch:c];
            return;
        } else {
            [attrValue appendString:[NSString stringWithCharacters:&c length:1]];
        }
    }
}

- (NSString *) scanQuotedStringWithCharactersFromSet:(NSCharacterSet *)charSet {
    unichar c = [self getch];
    unichar quoteChar = [@"\"" characterAtIndex:0];
    unichar backSlashChar = [@"\\" characterAtIndex:0];
    
    if (c != quoteChar) {
        [self rejectWithReason:@"expected quoted string to start with `\"'"];
    }
    
    NSMutableString *quotedString = [[[NSMutableString alloc] init] autorelease];
    while (1) {
        c = [self getch];
        if (c == quoteChar) {
            return quotedString;
        } else if (c == backSlashChar) {
            c = [self getch];
            if (c != quoteChar) {
                [self rejectWithReason:@"only quote-escapes are allowed inside quotes"];
            }
            [quotedString appendString:@"\""];
        } else if ([charSet characterIsMember:c]) {
            [quotedString appendString:[NSString stringWithCharacters:&c length:1]];
        } else {
            [self rejectWithReason:@"unexpected character inside quoted string"];
        }
    }
}

@end
