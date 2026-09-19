/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class MSGChannel;
@class MSGUserListView;

@protocol MSGUserListViewDelegate <NSObject>
@optional
// Row indexes match -sortedUsers order; returned menu is popped at the mouse.
- (NSMenu *)userListView:(MSGUserListView *)view contextMenuForRow:(NSInteger)row;
// Fires with -1 when the selection goes away (e.g. after a reload).
- (void)userListView:(MSGUserListView *)view didSelectRow:(NSInteger)row;
@end

@interface MSGUserListView : NSView <NSTableViewDataSource>
{
	NSScrollView *_scrollView;
	NSTableView *_tableView;
	MSGChannel *_channel;
	id<MSGUserListViewDelegate> _delegate;
}

@property (nonatomic, assign) id<MSGUserListViewDelegate> delegate;
@property (nonatomic, readonly) NSInteger selectedUserRow;

- (void)reloadWithChannel:(MSGChannel *)channel;
// Selects and reveals the row of the given nick; NO when that user is not
// in the current channel.
- (BOOL)selectUserWithNick:(NSString *)nick;

@end
