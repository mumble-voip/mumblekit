// Copyright 2009-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

@interface MKAudioOutputUser () {
@protected
    NSString    *_name;
    NSUInteger   _bufferSize;
    float       *_buffer;
    float       *_volume;
    float        _pos[3];
}
@end