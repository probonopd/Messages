/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>

#import "MSGProtocol.h"

// The backend-specific part of the Account menu. It is derived from what
// the selected account's protocol can do, so a backend's commands appear
// only while one of its networks is selected and never for another
// backend. The items have no target: they reach the main window
// controller through the responder chain, which enables them for the
// current channel and user.
@interface MSGAccountMenuSection : NSObject

+ (NSArray *)itemsForCapabilities:(MSGCapabilities)capabilities;

@end
