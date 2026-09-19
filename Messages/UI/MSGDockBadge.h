/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

// Mirrors the DockService protocol published by the Gershwin workspace Dock.
// We declare it locally instead of importing the workspace headers so this
// app builds without linking gershwin-workspace; the service is reached at
// runtime over distributed objects and is simply absent when no Dock runs.
// The methods must stay oneway like the Dock's own declaration: otherwise
// every badge update waits for the Dock, and a busy Dock stalls the UI.
@protocol DockService <NSObject>

- (oneway void)setBadgeCount:(int64_t)count;
- (oneway void)setCountVisible:(BOOL)visible;
- (oneway void)setProgressValue:(double)value;
- (oneway void)setProgressVisible:(BOOL)visible;
- (oneway void)setUrgent:(BOOL)urgent;
- (oneway void)clearAll;

@end

@interface MSGDockBadge : NSObject

// Push the running total of unread messages to the Dock; a zero or negative
// count hides the badge entirely.
- (void)updateWithUnreadCount:(NSInteger)count;

// Hide the badge unconditionally, e.g. when the application quits so no stale
// count lingers on the Dock icon.
- (void)clear;

@end
