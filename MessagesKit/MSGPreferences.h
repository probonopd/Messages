/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

// User-visible chat preferences backed by NSUserDefaults. Kept separate
// from the preferences panel so model/UI code can read settings without
// dragging in window code.

// Posted on the main thread whenever a preference below changes value.
extern NSString *const MSGBubbleStyleDidChangeNotification;

// Speech-bubble transcript style instead of the classic text log.
BOOL MSGPreferencesUseBubbles(void);
void MSGPreferencesSetUseBubbles(BOOL flag);

// Sound on incoming public/private messages.
BOOL MSGPreferencesPlaySoundOnIncomingMessages(void);
void MSGPreferencesSetPlaySoundOnIncomingMessages(BOOL flag);

// Last open channel per server, so reconnecting to the same server reopens
// the same tab. The stored dictionary has an "id" (NSInteger) and a "name"
// (NSString) entry; the id is authoritative, the name is the fallback when
// the server handed out new identifiers.
NSDictionary *MSGPreferencesLastChannelForServer(NSString *server);
void MSGPreferencesSetLastChannelId(NSInteger identifier
	, NSString *name
	, NSString *server);

// Per-user directory for app-private files (saved servers, session tokens).
// Created with 0700 on first use because it holds credentials.
NSString *MSGApplicationSupportDirectory(void);
