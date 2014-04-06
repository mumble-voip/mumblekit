// Copyright 2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

#import "MKChannelACL.h"

@implementation MKChannelACL

@synthesize applyHere;
@synthesize applySubs;
@synthesize inherited;
@synthesize userID;
@synthesize group;
@synthesize grant;
@synthesize deny;

- (BOOL) hasUserID {
    return (self.userID > -1);
}

- (NSString *) description {
    NSMutableString *grantDescription = [[NSMutableString alloc] init];
    if (self.grant == MKPermissionAll) {
        [grantDescription appendString:@"All"];
    } else if (self.grant == MKPermissionNone) {
        [grantDescription appendString:@"None"];
    } else {
        if ((self.grant & MKPermissionWrite) == MKPermissionWrite) {
            [grantDescription appendString:@"Write | "];
        }
        if ((self.grant & MKPermissionTraverse) == MKPermissionTraverse) {
            [grantDescription appendString:@"Traverse | "];
        }
        if ((self.grant & MKPermissionEnter) == MKPermissionEnter) {
            [grantDescription appendString:@"Enter | "];
        }
        if ((self.grant & MKPermissionSpeak) == MKPermissionSpeak) {
            [grantDescription appendString:@"Speak | "];
        }
        if ((self.grant & MKPermissionMuteDeafen) == MKPermissionMuteDeafen) {
            [grantDescription appendString:@"MuteDeafen | "];
        }
        if ((self.grant & MKPermissionMove) == MKPermissionMove) {
            [grantDescription appendString:@"Move | "];
        }
        if ((self.grant & MKPermissionMakeChannel) == MKPermissionMakeChannel) {
            [grantDescription appendString:@"MakeChannel | "];
        }
        if ((self.grant & MKPermissionLinkChannel) == MKPermissionLinkChannel) {
            [grantDescription appendString:@"LinkChannel | "];
        }
        if ((self.grant & MKPermissionWhisper) == MKPermissionWhisper) {
            [grantDescription appendString:@"Whisper | "];
        }
        if ((self.grant & MKPermissionTextMessage) == MKPermissionTextMessage) {
            [grantDescription appendString:@"TextMessage | "];
        }
        if ((self.grant & MKPermissionMakeTempChannel) == MKPermissionMakeTempChannel) {
            [grantDescription appendString:@"MakeTempChannel | "];
        }
        if ((self.grant & MKPermissionKick) == MKPermissionKick) {
            [grantDescription appendString:@"Kick | "];
        }
        if ((self.grant & MKPermissionBan) == MKPermissionBan) {
            [grantDescription appendString:@"Ban | "];
        }
        if ((self.grant & MKPermissionRegister) == MKPermissionRegister) {
            [grantDescription appendString:@"Register | "];
        }
        if ((self.grant & MKPermissionSelfRegister) == MKPermissionSelfRegister) {
            [grantDescription appendString:@"SelfRegister | "];
        }
        
        if (grantDescription.length > 0) {
            grantDescription = [NSMutableString stringWithString:[grantDescription substringToIndex:grantDescription.length-3]];
        }
    }
    
    NSMutableString *denyDescription = [[NSMutableString alloc] init];
    if (self.deny == MKPermissionAll) {
        [denyDescription appendString:@"All"];
    } else if (self.deny == MKPermissionNone) {
        [denyDescription appendString:@"None"];
    } else {
        if ((self.deny & MKPermissionWrite) == MKPermissionWrite) {
            [denyDescription appendString:@"Write | "];
        }
        if ((self.deny & MKPermissionTraverse) == MKPermissionTraverse) {
            [denyDescription appendString:@"Traverse | "];
        }
        if ((self.deny & MKPermissionEnter) == MKPermissionEnter) {
            [denyDescription appendString:@"Enter | "];
        }
        if ((self.deny & MKPermissionSpeak) == MKPermissionSpeak) {
            [denyDescription appendString:@"Speak | "];
        }
        if ((self.deny & MKPermissionMuteDeafen) == MKPermissionMuteDeafen) {
            [denyDescription appendString:@"MuteDeafen | "];
        }
        if ((self.deny & MKPermissionMove) == MKPermissionMove) {
            [denyDescription appendString:@"Move | "];
        }
        if ((self.deny & MKPermissionMakeChannel) == MKPermissionMakeChannel) {
            [denyDescription appendString:@"MakeChannel | "];
        }
        if ((self.deny & MKPermissionLinkChannel) == MKPermissionLinkChannel) {
            [denyDescription appendString:@"LinkChannel | "];
        }
        if ((self.deny & MKPermissionWhisper) == MKPermissionWhisper) {
            [denyDescription appendString:@"Whisper | "];
        }
        if ((self.deny & MKPermissionTextMessage) == MKPermissionTextMessage) {
            [denyDescription appendString:@"TextMessage | "];
        }
        if ((self.deny & MKPermissionMakeTempChannel) == MKPermissionMakeTempChannel) {
            [denyDescription appendString:@"MakeTempChannel | "];
        }
        if ((self.deny & MKPermissionKick) == MKPermissionKick) {
            [denyDescription appendString:@"Kick | "];
        }
        if ((self.deny & MKPermissionBan) == MKPermissionBan) {
            [denyDescription appendString:@"Ban | "];
        }
        if ((self.deny & MKPermissionRegister) == MKPermissionRegister) {
            [denyDescription appendString:@"Register | "];
        }
        if ((self.deny & MKPermissionSelfRegister) == MKPermissionSelfRegister) {
            [denyDescription appendString:@"SelfRegister | "];
        }
        
        if (denyDescription.length > 0) {
            denyDescription = [NSMutableString stringWithString:[denyDescription substringToIndex:denyDescription.length-3]];
        }
    }
    
    return [NSString stringWithFormat:@"{applyHere: %@; applySubs: %@; inherited: %@; %@: %@; grant: %@; deny: %@}",
            self.applyHere ? @"YES" : @"NO",
            self.applySubs ? @"YES" : @"NO",
            self.inherited ? @"YES" : @"NO",
            self.hasUserID ? @"userID" : @"group",
            self.hasUserID ? [NSNumber numberWithInteger:self.userID] : self.group,
            grantDescription,
            denyDescription];
}

@end
