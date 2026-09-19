/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

#import "MSGNetworkOutlineView.h"
#import "MSGMessageView.h"
#import "MSGUserListView.h"
#import "MSGContextMenuBuilder.h"

@class MSGAccountManager;

// Posted when the account the menus act on may have changed; userInfo
// "account" is the account of the selected network, absent when none.
extern NSString *const MSGMainWindowSelectedAccountDidChangeNotification;
@class MSGInputTextView;
@class MSGDockBadge;
@class MSGConnectingView;
@class NSSearchField;

@interface MSGMainWindowController : NSWindowController <NSSplitViewDelegate,
	MSGNetworkOutlineViewDelegate, MSGMessageViewDelegate, NSWindowDelegate,
	MSGUserListViewDelegate, MSGContextMenuActionDelegate, NSTextViewDelegate,
	NSControlTextEditingDelegate, NSTextFieldDelegate>
{
	MSGAccountManager *_manager;
	NSSplitView *_splitView;
	MSGNetworkOutlineView *_networkOutline;
	NSView *_messagePane;
	MSGMessageView *_messageView;
	NSSearchField *_searchField;
	MSGUserListView *_userListView;
	MSGInputTextView *_inputTextView;
	NSView *_composerBar;
	NSButton *_sendButton;
	NSTextField *_statusLabel;
	// Covers the sidebar and transcript until the first network arrives.
	MSGConnectingView *_connectingView;
	NSInteger _selectedChannelId;
	NSString *_selectedUserNick;
	BOOL _loadingHistory;
	// The stored-tab restore is tried once per connection; afterwards the
	// user's own selections win.
	BOOL _attemptedStoredChannelRestore;
	// Bounds how many history batches are fetched automatically to fill a
	// transcript shorter than the viewport; guards against a server that
	// keeps reporting more messages than it actually sends.
	NSInteger _autoHistoryBatches;
	// Reflects the total unread-message count in the Dock; nil when no Dock
	// service is reachable.
	MSGDockBadge *_dockBadge;
	// Live text filter for the current channel's transcript. Non-empty, it
	// hides every message that does not contain the term, and the scroll-to-
	// top handler switches from plain history to a server-side search so the
	// bouncer's backlog is consulted too.
	NSString *_filterText;
	// Whether the bouncer may still have query matches older than what we
	// hold; drives the scroll-to-top search until a page comes back short.
	BOOL _searchHasMore;
	// Single-flight guard for in-flight server searches.
	BOOL _searchLoading;
	// Accumulated backlog search results, kept separate from channel.messages
	// so they never disturb normal history pagination; merged at render time.
	NSMutableArray *_searchResults;
	// Pagination cursor for the backlog search (the bouncer returns pages of
	// up to 100 matches keyed by this offset).
	NSInteger _searchOffset;
}

@property (nonatomic, readonly) MSGAccountManager *accountManager;
@property (nonatomic, assign) NSInteger selectedChannelId;

- (instancetype)initWithAccountManager:(MSGAccountManager *)manager;
- (void)selectChannelId:(NSInteger)channelId;
- (IBAction)sendInput:(id)sender;
// Drop the Dock badge immediately; used when the application quits so no stale
// unread count remains on the icon.
- (void)clearDockBadge;

@end