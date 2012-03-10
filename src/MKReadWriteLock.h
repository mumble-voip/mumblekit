// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#include <pthread.h>

@interface MKReadWriteLock : NSObject

- (id) init;
- (void) dealloc;

- (BOOL) tryWriteLock;
- (void) writeLock;

- (BOOL) tryReadLock;
- (void) readLock;

- (void) unlock;

@end
