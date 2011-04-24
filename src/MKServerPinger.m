/* Copyright (C) 2009-2011 Mikkel Krautz <mikkel@krautz.dk>

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

#import "MKServerPinger.h"

#if TARGET_OS_IPHONE == 1
# import <CFNetwork/CFNetwork.h>
# import <CoreFoundation/CoreFoundation.h>
#endif

#include <sys/socket.h>
#include <sys/types.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <netdb.h>

@interface MKServerPinger (Private)
- (id) initWithAddress:(NSData *)address;
- (NSData *) address;
@end

@interface MKServerPingerController : NSObject {
    NSMutableDictionary  *_randvalues;
    NSMutableDictionary  *_pingers;
    int                  _sock4;
    int                  _sock6;
    dispatch_source_t    _reader4;
    dispatch_source_t    _reader6;
    dispatch_source_t    _timer;
}

- (void) socketReader:(int)sock;
- (void) timerTicked;
- (void) setupPingerState;
- (void) teardownPingerState;
- (void) addPinger:(MKServerPinger *)pinger;
- (void) removePinger:(MKServerPinger *)pinger;

@end

static MKServerPingerController *_serverPingerControllerSingleton;

@implementation MKServerPingerController

+ (MKServerPingerController *) sharedController {
    if (_serverPingerControllerSingleton == nil) {
        _serverPingerControllerSingleton = [[MKServerPingerController alloc] init];
    }
    return _serverPingerControllerSingleton;
}

- (id) init {
    if ((self = [super init])) {
        _pingers = [[NSMutableDictionary alloc] init];
        _randvalues = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void) dealloc {
    [_pingers release];
    [_randvalues release];
    [self teardownPingerState];
    [super dealloc];
}

- (void) setupPingerState {
    _sock6 = socket(AF_INET6, SOCK_DGRAM, 0);
    if (_sock6 > 0) {
        struct sockaddr_in6 sa6;
        memset(&sa6, 0, sizeof(struct sockaddr_in6));
        sa6.sin6_len = sizeof(struct sockaddr_in6);
        sa6.sin6_family = AF_INET6;
        sa6.sin6_port = 0;
        sa6.sin6_addr = in6addr_any;
        if (bind(_sock6, (struct sockaddr *) &sa6, sa6.sin6_len) != -1) {
            _reader6 = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _sock6, 0, dispatch_get_main_queue());
            if (_reader6 != NULL) {
                dispatch_source_set_event_handler(_reader6, ^{
                    [self socketReader:_sock6];
                });
                dispatch_resume(_reader6);
            }
        }
    }

    _sock4 = socket(AF_INET, SOCK_DGRAM, 0);
    if (_sock4 > 0) {
        struct sockaddr_in sa;
        memset(&sa, 0, sizeof(struct sockaddr_in));
        sa.sin_len = sizeof(struct sockaddr_in);
        sa.sin_family = AF_INET;
        sa.sin_port = 0;
        sa.sin_addr.s_addr = htonl(INADDR_ANY);
        if (bind(_sock4, (struct sockaddr *) &sa, sa.sin_len) != -1) {
            _reader4 = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, _sock4, 0, dispatch_get_main_queue());
            if (_reader4 != NULL) {
                dispatch_source_set_event_handler(_reader4, ^{
                    [self socketReader:_sock4];
                });
                dispatch_resume(_reader4);
            }
        }
    }
    
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, 1000000000ULL, 3000000000ULL);
    dispatch_source_set_event_handler(_timer, ^{
        [self timerTicked];
    });
    dispatch_resume(_timer);
}

- (void) teardownPingerState {
    dispatch_release(_reader4);
    dispatch_release(_reader6);
    dispatch_release(_timer);
    if (_sock4 > 0)
        close(_sock4);
    if (_sock6 > 0)
        close(_sock6);
}

- (void) socketReader:(int)sock {
    struct sockaddr addr;
    socklen_t addrlen = sizeof(struct sockaddr);
    char buf[64];
    ssize_t nread = recvfrom(sock, buf, 64, 0, &addr, &addrlen);
    if (nread == 24) {
        NSData *recvAddr = [NSData dataWithBytesNoCopy:&addr length:addrlen freeWhenDone:NO];
        NSArray *addrPingers = [_pingers objectForKey:recvAddr];
        NSNumber *randNumber = [_randvalues objectForKey:recvAddr];
        UInt64 randValue = (UInt64) [randNumber unsignedLongLongValue];

        UInt32 *ping = (UInt32 *)buf;
        UInt64 pingRand = ((UInt64) ping[1] << 32) | (UInt64) ping[2];
        UInt64 timeStamp =  pingRand ^ randValue;
        // Get the raw bits, don't do integer -> double conversion;
        NSTimeInterval origInterval = *((NSTimeInterval *) &timeStamp);
        NSTimeInterval pingTime = [NSDate timeIntervalSinceReferenceDate] - origInterval;

        MKServerPingerResult res;
        res.version = CFSwapInt32BigToHost(ping[0]);
        res.cur_users = CFSwapInt32BigToHost(ping[3]);
        res.max_users = CFSwapInt32BigToHost(ping[4]);
        res.bandwidth = CFSwapInt32BigToHost(ping[5]);
        res.ping = (double) pingTime;

        for (MKServerPinger *pinger in addrPingers) {
            [[pinger delegate] serverPingerResult:&res];
        }
    }
}

- (void) timerTicked {
    char buf[12];
    for (NSData *addr in [_randvalues allKeys]) {
        memset(buf, 0, 12);

        NSNumber *randNumber = [_randvalues objectForKey:addr];
        UInt64 randValue = (UInt64) [randNumber unsignedLongLongValue];

        NSTimeInterval origInterval = [NSDate timeIntervalSinceReferenceDate];
        // Get the raw bits, don't do double -> integer conversion.
        UInt64 intervalBits = *((UInt64 *) &origInterval);
        UInt64 rand = randValue ^ intervalBits;

        UInt32 *ping = (UInt32 *)buf;
        ping[0] = 0;
        ping[1] = (rand >> 32) & 0xffffffff;
        ping[2] = rand & 0xffffffff;

        struct sockaddr *sa = (struct sockaddr *) [addr bytes];
        if (sa->sa_family == AF_INET)
            sendto(_sock4, buf, 12, 0, [addr bytes], [addr length]);
        else if (sa->sa_family == AF_INET6)
            sendto(_sock6, buf, 12, 0, [addr bytes], [addr length]);
    }
}

- (void) addPinger:(MKServerPinger *)pinger {
    NSData *addr = [pinger address];

    NSNumber *randData = [_randvalues objectForKey:addr];
    if (randData == nil) {
        UInt64 randValue = (UInt64) arc4random() << 32 | (UInt64) arc4random();
        randData = [NSNumber numberWithUnsignedLongLong:(unsigned long long)randValue];
        [_randvalues setObject:randData forKey:addr];
        [_pingers setObject:[NSMutableArray arrayWithObject:pinger] forKey:addr];
    } else {
        NSMutableArray *addrPingers = [_pingers objectForKey:addr];
        [addrPingers addObject:pinger];
    }

    [pinger release];
    if ([_pingers count] == 1)
        [self setupPingerState];
}

- (void) removePinger:(MKServerPinger *)pinger {
    [pinger retain];

    NSData *addr = [pinger address];
    NSMutableArray *addrPingers = [_pingers objectForKey:addr];
    [addrPingers removeObject:pinger];
    if ([addrPingers count] == 0) {
        [_pingers removeObjectForKey:addr];
        [_randvalues removeObjectForKey:addr];
    }

    if ([_pingers count] == 0) {
        [self teardownPingerState];
    }
}

@end

@implementation MKServerPinger

- (id) initWithHostname:(NSString *)hostname port:(NSString *)port {
    struct addrinfo *ai = NULL, *iter = NULL;
    struct addrinfo hints;

    memset(&hints, 0, sizeof(struct addrinfo));
    hints.ai_family = PF_UNSPEC;
    hints.ai_flags = AI_ADDRCONFIG;

    if (getaddrinfo([hostname UTF8String], [port UTF8String], &hints, &ai) == 0) {
        iter = ai;
        while (iter != NULL) {
            if (iter->ai_family == AF_INET || iter->ai_family == AF_INET6)
                break;
        }

        NSData *addrData = [NSData dataWithBytes:iter->ai_addr length:iter->ai_addrlen];
        return [self initWithAddress:addrData];
    } else {
        return [self initWithAddress:nil];
    }
}

- (id) initWithAddress:(NSData *)address {
    if ((self = [super init])) {
        _address = [address copy];
        [[MKServerPingerController sharedController] addPinger:self];
    }
    return self;
}

- (void) dealloc {
    [[MKServerPingerController sharedController] removePinger:self];
    [super dealloc];
}

- (void) setDelegate:(id<MKServerPingerDelegate>)delegate {
    _delegate = delegate;
}

- (id<MKServerPingerDelegate>)delegate {
    return _delegate;
}

- (NSData *) address {
    return _address;
}

@end
