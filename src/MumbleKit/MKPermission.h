// Copyright 2010-2012 The MumbleKit Developers. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

typedef enum {
    MKPermissionNone             = 0x00000,
    MKPermissionWrite            = 0x00001,
    MKPermissionTraverse         = 0x00002,
    MKPermissionEnter            = 0x00004,
    MKPermissionSpeak            = 0x00008,
    MKPermissionMuteDeafen       = 0x00010,
    MKPermissionMove             = 0x00020,
    MKPermissionMakeChannel      = 0x00040,
    MKPermissionLinkChannel      = 0x00080,
    MKPermissionWhisper          = 0x00100,
    MKPermissionTextMessage      = 0x00200,
    MKPermissionMakeTempChannel  = 0x00400,
    MKPermissionKick             = 0x10000,
    MKPermissionBan              = 0x20000,
    MKPermissionRegister         = 0x40000,
    MKPermissionSelfRegister     = 0x80000,
    MKPermissionAll              = 0xf07ff,
} MKPermission;

