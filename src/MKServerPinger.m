// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

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
#include <fcntl.h>

@interface MKServerPinger () {
    NSData                      *_address;
    id<MKServerPingerDelegate>  _delegate;
}

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

@implementation MKServerPingerController

+ (MKServerPingerController *) sharedController {
    static MKServerPingerController *serverPingerController;
    static dispatch_once_t token;
    dispatch_once(&token, ^{
        serverPingerController = [[MKServerPingerController alloc] init];
    });
    return serverPingerController;
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
        int val = 1;
        if (setsockopt(_sock6, SOL_SOCKET, SO_NOSIGPIPE, &val, sizeof(val)) == -1)
            NSLog(@"MKServerPinger: unable to set SO_NOSIGPIPE for _sock6: %s", strerror(errno));
        int flags = fcntl(_sock6, F_GETFL, 0);
        if (flags != -1) {
            fcntl(_sock6, F_SETFL, flags | O_NONBLOCK);
        }
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
        } else {
            NSLog(@"MKServerPinger: unable to bind _sock6: %s", strerror(errno));
        }
    }

    _sock4 = socket(AF_INET, SOCK_DGRAM, 0);
    if (_sock4 > 0) {
        int val = 1;
        if (setsockopt(_sock4, SOL_SOCKET, SO_NOSIGPIPE, &val, sizeof(val)) == -1)
            NSLog(@"MKServerPinger: unable to set SO_NOSIGPIPE for _sock4: %s", strerror(errno));
        int flags = fcntl(_sock4, F_GETFL, 0);
        if (flags != -1) {
            fcntl(_sock4, F_SETFL, flags | O_NONBLOCK);
        }
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
        } else {
            NSLog(@"MKServerPinger: unable to bind _sock4: %s", strerror(errno));
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
            sendto(_sock4, buf, 12, 0, [addr bytes], (socklen_t)[addr length]);
        else if (sa->sa_family == AF_INET6)
            sendto(_sock6, buf, 12, 0, [addr bytes], (socklen_t)[addr length]);
    }
}

- (void) addPinger:(MKServerPinger *)pinger {
    NSData *addr = [pinger address];

    if (addr != nil) {
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
}

- (void) removePinger:(MKServerPinger *)pinger {
    [pinger retain];

    NSData *addr = [pinger address];
    if (addr != nil) {
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
        NSData *addrData = nil;
        while (iter != NULL) {
            if (iter->ai_family == AF_INET || iter->ai_family == AF_INET6) {
                addrData = [NSData dataWithBytes:iter->ai_addr length:iter->ai_addrlen];
                break;
            }
        }
        freeaddrinfo(ai);
        return [self initWithAddress:addrData];
    }
    return [self initWithAddress:nil];
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
    [_address release];
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
