/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>

// Shown in place of the empty sidebar and transcript while the accounts are
// still connecting: a short message above an indeterminate progress bar,
// centered in the window, so launching does not look like a broken, empty
// window.
@interface MSGConnectingView : NSView

// The message to show for `accounts` (MSGAccount), or nil when the view
// should be hidden: something is already in the sidebar, or no account is
// on its way to being connected.
+ (NSString *)messageForAccounts:(NSArray *)accounts hasNetworks:(BOOL)hasNetworks;

- (void)setMessage:(NSString *)message;
- (NSProgressIndicator *)progressIndicator;

@end
