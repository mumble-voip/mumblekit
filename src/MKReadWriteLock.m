// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

/*
 * MKReadWriteLock - Simple ObjC wrapper around the pthreads read/write lock.
 */

#import "MKReadWriteLock.h"

@interface MKReadWriteLock () {
    pthread_rwlock_t rwlock;
}
@end

@implementation MKReadWriteLock

- (id) init {
    int err;

    self = [super init];
    if (self == nil)
        return nil;

    err = pthread_rwlock_init(&rwlock, NULL);
    if (err != 0) {
        NSLog(@"RWLock: Unable to initialize rwlock. Error=%i", err);
        return nil;
    }

    return self;
}

- (void) dealloc {
    int err = pthread_rwlock_destroy(&rwlock);
    if (err != 0) {
        NSLog(@"RWLock: Unable to destroy rwlock.");
    }

    [super dealloc];
}

/*
 * Try to acquire a write lock. Returns immediately.
 */
- (BOOL) tryWriteLock {
    int err;

    err = pthread_rwlock_trywrlock(&rwlock);
    if (err != 0) {
        NSLog(@"RWLock: tryWriteLock failed: %i (%s).", err, strerror(err));
        return NO;
    }

    return YES;
}

/*
 * Acquire a write lock. Block until we can get it.
 */
- (void) writeLock {
    int err;

    err = pthread_rwlock_wrlock(&rwlock);
    if (err != 0) {
        NSLog(@"writeLock failed: %i (%s)", err, strerror(err));
    }

    assert(err == 0);
}

/*
 * Try to acquire a read lock. Returns immediately.
 */
- (BOOL) tryReadLock {
    int err;

    err = pthread_rwlock_tryrdlock(&rwlock);
    if (err != 0) {
        return NO;
    }

    return YES;
}

/*
 * Acquire a read lock. Block until it succeeds.
 */
- (void) readLock {
    int err;

    err = pthread_rwlock_rdlock(&rwlock);
    assert(err == 0);
}

/*
 * Unlock.
 */
- (void) unlock {
    int err;

    err = pthread_rwlock_unlock(&rwlock);
    assert(err == 0);
}

@end
