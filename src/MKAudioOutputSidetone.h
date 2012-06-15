// Copyright 2005-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import <MumbleKit/MKAudio.h>
#import "MKAudioOutputUser.h"

@interface MKAudioOutputSidetone : MKAudioOutputUser
- (id) initWithSettings:(MKAudioSettings *)settings;
- (void) addFrame:(NSData *)data;
@end
