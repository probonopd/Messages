/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGMainWindowController.h"

#import "MSGInputTextView.h"
#import "MSGDockBadge.h"
#import "MSGAccountManager.h"
#import "MSGAccount.h"
#import "MSGServerState.h"
#import "MSGNetwork.h"
#import "MSGChannel.h"
#import "MSGMessage.h"
#import "MSGUser.h"
#import "MSGPreferences.h"
#import "MSGSoundPlayer.h"
#import "MSGGroupListController.h"
#import "MSGApplicationDelegate.h"

// The window restores one tab, whichever account it belongs to.
static NSString *const MSGLastChannelScope = @"Messages";

NSString *const MSGMainWindowSelectedAccountDidChangeNotification =
	@"MSGMainWindowSelectedAccountDidChangeNotification";

@implementation MSGMainWindowController

- (instancetype)initWithAccountManager:(MSGAccountManager *)manager
{
	NSRect contentRect = NSMakeRect(0, 0, 900, 560);
	NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
		styleMask:(NSTitledWindowMask | NSClosableWindowMask |
			NSMiniaturizableWindowMask | NSResizableWindowMask)
		backing:NSBackingStoreBuffered defer:NO];
	NSString *savedFrame = [[NSUserDefaults standardUserDefaults]
		stringForKey:@"MSGMainWindowFrame"];
	if ([savedFrame length] > 0) {
		// Restore the last-used frame before the window is ordered front.
		[window setFrame:NSRectFromString(savedFrame) display:NO];
	}
	[window setReleasedWhenClosed:NO];
	[window setDelegate:self];

	self = [super initWithWindow:window];
	[window release];
	if (self) {
	_manager = [manager retain];
	_selectedChannelId = 0;
	_loadingHistory = NO;
	_searchResults = [[NSMutableArray alloc] init];
	_dockBadge = [[MSGDockBadge alloc] init];
	[self buildInterfaceForWindow:window];
	// The combined view resolves against the accounts on every access, so
	// it stays current as accounts come and go.
	[_networkOutline setServerState:_manager.combinedState];
	[self registerForNotifications];
	[self updateStatusLabel];
	[self setWindowTitle];
	// The network-list notification usually fired while only the login
	// window existed, so populate from current state right away.
	[_networkOutline reloadData];
	[self ensureSelectedChannelPopulated];
	// Open with the cursor already in the message composer so the user can
	// start typing without first clicking the text field.
	[window makeFirstResponder:_inputTextView];
	}
	return self;
}

- (void)buildInterfaceForWindow:(NSWindow *)window
{
	NSView *contentView = [window contentView];
	NSRect contentBounds = [contentView bounds];
	const CGFloat barHeight = 34.0;

	_splitView = [[NSSplitView alloc] initWithFrame:
		NSMakeRect(0, barHeight, NSWidth(contentBounds), NSHeight(contentBounds) - barHeight)];
	[_splitView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[_splitView setVertical:YES];
	[_splitView setDelegate:self];

	CGFloat divider = [_splitView dividerThickness];
	CGFloat splitHeight = NSHeight([_splitView frame]);

	_networkOutline = [[MSGNetworkOutlineView alloc] initWithFrame:
		NSMakeRect(0, 0, 190, splitHeight)];
	[_networkOutline setAutoresizingMask:NSViewHeightSizable];
	[_networkOutline setDelegate:self];

	_messageView = [[MSGMessageView alloc] initWithFrame:
		NSMakeRect(0, 0, NSWidth(contentBounds) - 190 - 150 - 2.0 * divider, splitHeight)];
	[_messageView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[_messageView setDelegate:self];

	_userListView = [[MSGUserListView alloc] initWithFrame:
		NSMakeRect(0, 0, 150, splitHeight)];
	[_userListView setAutoresizingMask:NSViewHeightSizable];
	[_userListView setDelegate:self];

	// The message pane stacks a filter box over the transcript so the search
	// field stays pinned to the top of the chat column while the transcript
	// below it resizes with the split.
	_messagePane = [[NSView alloc] initWithFrame:
		NSMakeRect(0, 0, NSWidth(contentBounds) - 190 - 150 - 2.0 * divider, splitHeight)];
	[_messagePane setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

	_searchField = [[NSSearchField alloc] initWithFrame:
		NSMakeRect(0, [_messagePane bounds].size.height - 26.0,
			[_messagePane bounds].size.width, 26.0)];
	[_searchField setPlaceholderString:@"Filter messages"];
	[_searchField setTarget:self];
	[_searchField setDelegate:self];
	[_searchField setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
	[_messagePane addSubview:_searchField];

	// The transcript fills the pane below the search field; its top is pinned
	// just under the field via the MaxY margin so it never overlaps it.
	[_messageView setFrame:NSMakeRect(0, 0, [_messagePane bounds].size.width,
		[_messagePane bounds].size.height - 26.0)];
	[_messageView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable |
		NSViewMaxYMargin];
	[_messagePane addSubview:_messageView];

	[_splitView addSubview:_networkOutline];
	[_splitView addSubview:_messagePane];
	[_splitView addSubview:_userListView];
	[contentView addSubview:_splitView];

	NSView *bar = [[NSView alloc] initWithFrame:
		NSMakeRect(0, 0, NSWidth(contentBounds), barHeight)];
	[bar setAutoresizingMask:NSViewWidthSizable];

	_statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 9, 130, 16)];
	[_statusLabel setEditable:NO];
	[_statusLabel setSelectable:NO];
	[_statusLabel setBezeled:NO];
	// A transparent label relies on its superview repainting behind it,
	// which misses areas under a fractional scale factor and leaves the
	// previous status text visible underneath the new one.
	[_statusLabel setDrawsBackground:YES];
	[_statusLabel setBackgroundColor:[NSColor windowBackgroundColor]];
	[_statusLabel setAutoresizingMask:NSViewMaxYMargin];
	[bar addSubview:_statusLabel];

	// Multi-line composer: Enter sends, Shift-Enter folds a newline into
	// the draft; the bar grows with the text up to a few lines.
	NSScrollView *inputScroll = [[NSScrollView alloc] initWithFrame:
		NSMakeRect(150, 5, NSWidth(contentBounds) - 150 - 70, 24)];
	[inputScroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[inputScroll setHasVerticalScroller:NO];
	[inputScroll setBorderType:NSBezelBorder];
	_inputTextView = [[MSGInputTextView alloc] initWithFrame:
		NSMakeRect(0, 0, [inputScroll contentSize].width,
		[inputScroll contentSize].height)];
	[_inputTextView setRichText:NO];
	[_inputTextView setDelegate:self];
	[_inputTextView setSendTarget:self action:@selector(sendInput:)];
	[inputScroll setDocumentView:_inputTextView];
	[_inputTextView release];
	[bar addSubview:inputScroll];
	[inputScroll release];

	_sendButton = [[NSButton alloc] initWithFrame:
		NSMakeRect(NSWidth(contentBounds) - 64, 4, 60, 26)];
	[_sendButton setTitle:@"Send"];
	[_sendButton setButtonType:NSMomentaryLightButton];
	[_sendButton setBezelStyle:NSRoundedBezelStyle];
	[_sendButton setTarget:self];
	[_sendButton setAction:@selector(sendInput:)];
	[_sendButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
	[bar addSubview:_sendButton];

	_composerBar = [bar retain];
	[contentView addSubview:bar];
	[bar release];
}

// Keeps the composer tall enough to show the whole draft, growing the bar
// (and shrinking the chat area) up to a few visible lines. The input sits
// with 5pt margins inside the bar, so bar height tracks input height.
- (void)updateComposerHeight
{
	NSSize used = [[_inputTextView layoutManager]
	    usedRectForTextContainer:[_inputTextView textContainer]].size;
	const CGFloat minInputHeight = 24.0;
	const CGFloat maxInputHeight = 58.0;
	CGFloat needed = MIN(MAX(ceil(used.height) + 2.0, minInputHeight), maxInputHeight);

	NSRect barFrame = [_composerBar frame];
	CGFloat currentInputHeight = barFrame.size.height - 10.0;
	CGFloat delta = needed - currentInputHeight;
	if (fabs(delta) < 1.0) {
		return;
	}
	barFrame.size.height += delta;
	[_composerBar setFrame:barFrame];

	NSRect splitFrame = [_splitView frame];
	splitFrame.origin.y += delta;
	splitFrame.size.height -= delta;
	[_splitView setFrame:splitFrame];
}

- (void)textDidChange:(NSNotification *)notification
{
	if (notification.object != _inputTextView) {
		return;
	}
	[self updateComposerHeight];
}

- (void)registerForNotifications
{
	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(protocolNetworkListDidChange:)
		name:MSGNetworkListDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(protocolChannelDidChange:)
		name:MSGChannelDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(protocolMessagesDidChange:)
		name:MSGMessagesDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(protocolUserListDidChange:)
		name:MSGUserListDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(protocolNicknamesDidChange:)
		name:MSGNicknamesDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(protocolHistoryDidChange:)
		name:MSGHistoryDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(protocolSearchResultsDidChange:)
		name:MSGSearchResultsDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(accountStateDidChange:)
		name:MSGAccountStateDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(accountListDidChange:)
		name:MSGAccountListDidChangeNotification object:_manager];
	[center addObserver:self selector:@selector(bubbleStyleDidChange:)
		name:MSGBubbleStyleDidChangeNotification object:nil];
	// Any change that can move the unread totals must refresh the Dock badge.
	[center addObserver:self selector:@selector(updateDockBadge)
		name:MSGNetworkListDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(updateDockBadge)
		name:MSGChannelDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(updateDockBadge)
		name:MSGMessagesDidChangeNotification object:nil];
	[center addObserver:self selector:@selector(updateDockBadge)
		name:MSGHistoryDidChangeNotification object:nil];
}

- (MSGAccountManager *)accountManager
{
	return _manager;
}

#pragma mark - Dock badge

- (void)clearDockBadge
{
	[_dockBadge clear];
}

// The Dock badge is exactly the sum of the per-channel badges drawn in the
// sidebar: both derive from -[MSGNetwork badgeTotal], which is the lobby
// (server) unread plus every channel's badge count, so the Dock total can
// never diverge from the window's sum. The unseen count is client-side and
// window-visibility aware (see MSGChannel), so it grows even for the active
// channel while the window is hidden.
- (void)updateDockBadge
{
	NSInteger total = 0;
	for (MSGNetwork *network in _manager.combinedState.networks) {
		total += [network badgeTotal];
	}
	[_dockBadge updateWithUnreadCount:total];
}

// Treat the active channel as seen once the user can actually see it. This is
// called when a channel is selected, whenever a message arrives in the active
// channel, and whenever the window returns to a visible state. A miniaturized
// or hidden window means the content is not on screen, so the unseen count is
// left intact there - that is what lets the badge accumulate while the window
// is in the Dock. (WindowShade is a window-manager feature with no AppKit
// query, so it cannot be detected here; isVisible/isMiniaturized cover the
// cases AppKit exposes.)
- (void)markActiveChannelSeen
{
	NSWindow *window = [self window];
	if (![window isVisible] || [window isMiniaturized]) {
		return;
	}
	if (_selectedChannelId == 0) {
		return;
	}
	MSGChannel *channel = [_manager.combinedState channelWithIdentifier:_selectedChannelId];
	if (!channel) {
		return;
	}
	if (channel.unseen != 0 || channel.unseenHighlight != 0) {
		channel.unseen = 0;
		channel.unseenHighlight = 0;
		// Let the sidebar (and the badge observer below) refresh.
		[[NSNotificationCenter defaultCenter]
			postNotificationName:MSGChannelDidChangeNotification
			object:self
			userInfo:@{@"channelId": @(_selectedChannelId)}];
	}
	// The server/lobby unread is network-scoped, not tied to the channel being
	// viewed. While the user is engaged with a network (window visible, any of
	// its channels active), its server notices are considered seen, so clear
	// them the same way the active channel's unread is cleared.
	MSGNetwork *activeNetwork =
		[_manager.combinedState networkContainingChannel:_selectedChannelId];
	MSGChannel *lobby = [activeNetwork lobby];
	if (lobby != nil && lobby.identifier != _selectedChannelId &&
		(lobby.unseen != 0 || lobby.unseenHighlight != 0)) {
		lobby.unseen = 0;
		lobby.unseenHighlight = 0;
		[[NSNotificationCenter defaultCenter]
			postNotificationName:MSGChannelDidChangeNotification
			object:self
			userInfo:@{@"channelId": @(lobby.identifier)}];
	}
	[self updateDockBadge];
}

- (void)setSelectedChannelId:(NSInteger)selectedChannelId
{
	_selectedChannelId = selectedChannelId;
}

- (NSInteger)selectedChannelId
{
	return _selectedChannelId;
}

#pragma mark - Channel selection

- (void)selectChannelId:(NSInteger)channelId
{
	MSGChannel *channel = [_manager.combinedState channelWithIdentifier:channelId];
	if (!channel) {
		return;
	}
	_selectedChannelId = channelId;
	[self resetFilterState];
	_loadingHistory = NO;
	_autoHistoryBatches = 0;
	[_selectedUserNick release];
	_selectedUserNick = nil;
	// Remember the open tab for the next visit to this server.
	MSGPreferencesSetLastChannelId(channelId, channel.name,
	    MSGLastChannelScope);
	[_networkOutline setSelectedChannelId:channelId];
	[_networkOutline selectChannelId:channelId];
	[_manager openChannelId:channelId];
	if ([channel isChannel] || [channel isQuery]) {
		[_manager requestNamesForChannelId:channelId];
	}
	[self populateViewsForChannel:channel];
	[self setWindowTitle];
	[self announceSelectedAccount];
	// The channel is now on screen, so clear its unread immediately instead
	// of waiting for the bouncer to echo the reset back.
	[self markActiveChannelSeen];
}

- (void)populateViewsForChannel:(MSGChannel *)channel
{
	[_messageView setChannelId:channel.identifier];
	[_messageView clear];
	for (MSGMessage *message in channel.messages) {
		if ([self message:message matchesFilter:_filterText]) {
			[_messageView appendMessage:message];
		}
	}
	// Show pending messages (typed while offline) at the bottom, dimmed.
	for (MSGMessage *message in channel.pendingMessages) {
		[_messageView appendMessage:message];
	}
	[self updateHasMoreHistoryForChannelId:channel.identifier];
	if ([_filterText length] > 0) {
		// While filtering, the scroll-to-top handler runs a server search
		// rather than plain history, so reflect the search cursor instead.
		[_messageView setHasMoreHistory:_searchHasMore];
	}
	[_messageView scrollToBottom];
	[_userListView reloadWithChannel:channel];
	// The bouncer replays only messages newer than what this client last
	// saw, so a quiet channel can start out shorter than the viewport -
	// too short to ever reach the top by scrolling. Fetch older batches
	// until the transcript is scrollable.
	[self autoFillHistoryIfShortTranscript];
}

- (void)repopulateActiveChannelCoalesced
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(repopulateActiveChannelNow) object:nil];
	[self performSelector:@selector(repopulateActiveChannelNow) withObject:nil afterDelay:0.12];
}

- (void)repopulateActiveChannelNow
{
	MSGChannel *channel = [_manager.combinedState channelWithIdentifier:_selectedChannelId];
	if (channel) {
		[self populateViewsForChannel:channel];
	}
}

- (void)updateHasMoreHistoryForChannelId:(NSInteger)channelId
{
	if (channelId != _selectedChannelId) {
		return;
	}
	MSGChannel *channel = [_manager.combinedState channelWithIdentifier:channelId];
	BOOL more = (channel &&
		channel.totalMessages > (NSInteger)[channel.messages count]);
	[_messageView setHasMoreHistory:more];
}

- (MSGChannel *)defaultChannelInServerState:(MSGServerState *)serverState
{
	for (MSGNetwork *network in serverState.networks) {
		MSGChannel *lobby = [network lobby];
		if (lobby) {
			return lobby;
		}
		for (MSGChannel *channel in network.channels) {
			if (channel.state == MSGChannelStateJoined) {
				return channel;
			}
		}
	}
	return nil;
}

// The tab that was open on this server last time, matched by identifier
// first and by name second; identifiers are server-assigned and can change.
- (MSGChannel *)storedChannelInServerState:(MSGServerState *)serverState
{
	NSDictionary *saved =
	    MSGPreferencesLastChannelForServer(MSGLastChannelScope);
	if (saved == nil) {
		return nil;
	}
	NSInteger storedId = [saved[@"id"] integerValue];
	NSString *name = saved[@"name"];
	if (storedId > 0) {
		MSGChannel *byId = [serverState channelWithIdentifier:storedId];
		if (byId) {
			return byId;
		}
	}
	if ([name length] > 0) {
		for (MSGNetwork *network in serverState.networks) {
			MSGChannel *lobby = [network lobby];
			if ([lobby.name isEqualToString:name]) {
				return lobby;
			}
			for (MSGChannel *channel in network.channels) {
				if ([channel.name isEqualToString:name]) {
					return channel;
				}
			}
		}
	}
	return nil;
}

#pragma mark - Protocol notifications

- (void)protocolNetworkListDidChange:(NSNotification *)notification
{
	[_networkOutline reloadData];
	[self ensureSelectedChannelPopulated];
	[self setWindowTitle];
}

- (void)protocolChannelDidChange:(NSNotification *)notification
{
	[_networkOutline reloadData];
	[self ensureSelectedChannelPopulated];
	[self setWindowTitle];
}

- (void)protocolMessagesDidChange:(NSNotification *)notification
{
	NSInteger channelId = [notification.userInfo[@"channelId"] integerValue];
	MSGMessage *message = notification.userInfo[@"message"];
	[_networkOutline reloadData];
	if (message) {
		[self playMessageAlertIfNeeded:message];
	}
	if (_selectedChannelId == channelId) {
		if (message) {
			if ([self message:message matchesFilter:_filterText]) {
				// A historical backfill can arrive newest-first; if the new
				// message is older than the transcript's current tail, rebuild
				// from the (timestamp-sorted) store instead of appending.
				MSGChannel *ch = [_manager.combinedState channelWithIdentifier:channelId];
				BOOL outOfOrder = NO;
				if (ch != nil) {
					MSGMessage *last = [[ch messages] lastObject];
					if (last != nil && message.timestamp != nil &&
						[message.timestamp compare:[last timestamp]] == NSOrderedAscending) {
						outOfOrder = YES;
					}
				}
			if (outOfOrder) {
				[self repopulateActiveChannelCoalesced];
			} else {
				[_messageView appendMessage:message];
			}
			}
		} else {
			// No specific message - pending messages were queued or flushed.
			// Repopulate to show/hide pending indicators.
			MSGChannel *ch = [_manager.combinedState channelWithIdentifier:channelId];
			if (ch) {
				[self populateViewsForChannel:ch];
			}
		}
		[self updateHasMoreHistoryForChannelId:channelId];
		if ([_filterText length] > 0) {
			[_messageView setHasMoreHistory:_searchHasMore];
		}
		// The active channel is on screen, so its unseen count is cleared
		// immediately even though the protocol just incremented it.
		[self markActiveChannelSeen];
	}
	[self setWindowTitle];
}

// A short, quiet sound when a chat message arrives. Own messages, technical
// lines (join/part/mode/...), muted channels, and catch-up replays of old
// events stay silent; MSGSoundPlayer additionally rate-limits bursts.
- (void)playMessageAlertIfNeeded:(MSGMessage *)message
{
	if (!MSGPreferencesPlaySoundOnIncomingMessages()) {
		return;
	}
	if ([message isSelf]) {
		return;
	}
	MSGMessageType type = [message type];
	if (type != MSGMessageTypeMessage && type != MSGMessageTypeAction) {
		return;
	}
	NSDate *timestamp = [message timestamp];
	if (timestamp == nil || [timestamp timeIntervalSinceNow] < -120.0) {
		return;
	}
	MSGChannel *channel = [_manager.combinedState
		channelWithIdentifier:[message channelId]];
	if (channel && [channel muted]) {
		return;
	}
	[MSGSoundPlayer playMessageSound];
}

- (void)protocolHistoryDidChange:(NSNotification *)notification
{
	NSInteger channelId = [notification.userInfo[@"channelId"] integerValue];
	_loadingHistory = NO;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(resetHistoryLoadingFlag) object:nil];
	[_networkOutline reloadData];
	if (_selectedChannelId == channelId) {
		MSGChannel *channel = [_manager.combinedState channelWithIdentifier:channelId];
		if (channel) {
			// The first page of a freshly opened channel must show the newest
			// message at the bottom, so repopulate and scroll down. Once the
			// transcript already holds that channel's messages, later (older
			// history) batches arrive via the same notification but use prepend,
			// which keeps the current reading position in place.
			if ([_filterText length] == 0) {
				if ([_messageView isEmpty]) {
					[self populateViewsForChannel:channel];
				} else {
					[_messageView prependMessages:channel.messages];
				}
			}
		}
		[self updateHasMoreHistoryForChannelId:channelId];
		// A batch may still have left the transcript shorter than the
		// viewport; keep going until scrolling becomes possible.
		[self autoFillHistoryIfShortTranscript];
	}
	[self setWindowTitle];
}

- (void)protocolUserListDidChange:(NSNotification *)notification
{
	NSInteger channelId = [notification.userInfo[@"channelId"] integerValue];
	if (_selectedChannelId != channelId) {
		return;
	}
	MSGChannel *channel = [_manager.combinedState channelWithIdentifier:channelId];
	if (channel) {
		[_userListView reloadWithChannel:channel];
	}
}

// Nostr display names (kind 0 metadata) resolve asynchronously after the
// messages have already been rendered, so re-render the open transcript with
// the now-resolved nicknames.
- (void)protocolNicknamesDidChange:(NSNotification *)notification
{
	MSGChannel *channel = [_manager.combinedState channelWithIdentifier:_selectedChannelId];
	if (channel) {
		[self populateViewsForChannel:channel];
	}
}

// The bouncer answered a backlog `search` with a page of matching messages.
// Merge them into the running result set, advance the pagination offset, and
// rebuild the filtered transcript. A short page means the backlog is done.
- (void)protocolSearchResultsDidChange:(NSNotification *)notification
{
	NSInteger channelId = [notification.userInfo[@"channelId"] integerValue];
	if (channelId != _selectedChannelId) {
		return;
	}
	NSArray *messages = notification.userInfo[@"messages"];
	NSInteger count = [notification.userInfo[@"count"] integerValue];
	if (count > 0 && [messages isKindOfClass:[NSArray class]]) {
		for (MSGMessage *message in messages) {
			[_searchResults addObject:message];
		}
		_searchOffset += count;
	}
	// The bouncer caps each page at 100, so fewer returned means no more
	// matches remain for this term.
	_searchHasMore = (count >= 100);
	_searchLoading = NO;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(resetSearchLoadingFlag) object:nil];
	[self rebuildTranscriptForFilter];
}

- (void)accountStateDidChange:(NSNotification *)notification
{
	[self updateStatusLabel];
}

- (void)accountListDidChange:(NSNotification *)notification
{
	[self announceSelectedAccount];
	[_networkOutline reloadData];
	if (_selectedChannelId > 0 &&
		[_manager.combinedState channelWithIdentifier:_selectedChannelId] == nil) {
		_selectedChannelId = 0;
		[self ensureSelectedChannelPopulated];
	}
	[self updateStatusLabel];
	[self setWindowTitle];
}

// One line for all accounts: the first one that is not ready speaks for
// the rest, because that is the one the user may have to act on.
- (void)updateStatusLabel
{
	NSArray *accounts = _manager.accounts;
	MSGAccount *troubled = nil;
	for (MSGAccount *account in accounts) {
		if (account.state != MSGConnectionStateReady) {
			troubled = account;
			break;
		}
	}
	NSString *text;
	MSGConnectionState state;
	if ([accounts count] == 0) {
		text = @"No accounts";
		state = MSGConnectionStateDisconnected;
	} else if (troubled == nil) {
		text = MSGConnectionStateDisplayString(MSGConnectionStateReady);
		state = MSGConnectionStateReady;
	} else {
		state = troubled.state;
		text = [accounts count] == 1
			? MSGConnectionStateDisplayString(state)
			: [NSString stringWithFormat:@"%@: %@", [troubled displayName],
				MSGConnectionStateDisplayString(state)];
	}
	[_statusLabel setStringValue:text];
	// Color the status label to reflect connection health at a glance.
	switch (state) {
		case MSGConnectionStateReconnecting:
		case MSGConnectionStateConnectionError:
		case MSGConnectionStateServerDisconnected:
		case MSGConnectionStateAuthenticationFailed:
		case MSGConnectionStateProtocolError:
			[_statusLabel setTextColor:[NSColor colorWithCalibratedRed:0.85
				green:0.35 blue:0.25 alpha:1.0]];
			break;
		case MSGConnectionStateReady:
			[_statusLabel setTextColor:[NSColor colorWithCalibratedRed:0.25
				green:0.70 blue:0.35 alpha:1.0]];
			break;
		default:
			[_statusLabel setTextColor:[NSColor controlTextColor]];
			break;
	}
}

// Rebuilds the transcript in the newly selected style; the current channel
// is repopulated from server state, so nothing is lost.
- (void)bubbleStyleDidChange:(NSNotification *)notification
{
	BOOL bubbles = MSGPreferencesUseBubbles();
	if ([_messageView usesBubbles] == bubbles) {
		return;
	}
	[_messageView setUsesBubbles:bubbles];
	MSGChannel *channel =
		[_manager.combinedState channelWithIdentifier:_selectedChannelId];
	if (channel) {
		[self populateViewsForChannel:channel];
	}
}

- (void)ensureSelectedChannelPopulated
{
	MSGServerState *serverState = _manager.combinedState;
	MSGChannel *channel = nil;
	if (_selectedChannelId > 0) {
		channel = [serverState channelWithIdentifier:_selectedChannelId];
	}
	// The stored tab is only consulted until the first successful
	// selection; afterwards the user drives.
	if (!channel && !_attemptedStoredChannelRestore) {
		_attemptedStoredChannelRestore = YES;
		channel = [self storedChannelInServerState:serverState];
	}
	if (!channel) {
		channel = [self defaultChannelInServerState:serverState];
	}
	if (!channel) {
		return;
	}
	if (_selectedChannelId == channel.identifier && _messageView.channelId == channel.identifier) {
		return;
	}
	[self selectChannelId:channel.identifier];
}

#pragma mark - Sending

- (IBAction)sendInput:(id)sender
{
	if (_selectedChannelId <= 0) {
		return;
	}
	NSString *text = [[_inputTextView string]
		stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([text length] == 0) {
		return;
	}
	// The Lounge expects commands with the leading slash intact; the session
	// layer forwards the raw line to the bouncer which does the parsing.
	if ([text hasPrefix:@"/"]) {
		[_manager sendCommand:text toChannelId:_selectedChannelId];
	} else {
		[_manager sendMessage:text toChannelId:_selectedChannelId];
	}
	[_inputTextView setString:@""];
	[self updateComposerHeight];
}

// Tab completes the word before the cursor to a nick of the current
// channel, but only when exactly one user matches; anything ambiguous is
// left untouched rather than guessing.
- (BOOL)textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
	// Name-based selector comparison: robust even where SEL pointers are
	// not guaranteed identical across modules.
	BOOL isTab = [NSStringFromSelector(command) isEqualToString:@"insertTab:"];
	if (!isTab || textView != _inputTextView) {
		return NO;
	}

	NSString *text = [textView string];
	NSUInteger cursor = NSMaxRange([textView selectedRange]);
	NSUInteger start = cursor;
	NSCharacterSet *spaces = [NSCharacterSet whitespaceAndNewlineCharacterSet];
	while (start > 0 && ![spaces characterIsMember:[text characterAtIndex:start - 1]]) {
		start--;
	}
	if (cursor <= start) {
		return YES;
	}

	MSGChannel *channel = [_manager.combinedState channelWithIdentifier:_selectedChannelId];
	MSGUser *match = [channel uniqueUserWithNickPrefix:
	    [text substringWithRange:NSMakeRange(start, cursor - start)]];
	if (!match) {
		return YES;
	}

	// A completion that starts the line reads as an address; mid-sentence
	// it is just a mention.
	NSString *nick = [match nick];
	NSString *replacement = (start == 0)
	    ? [nick stringByAppendingString:@": "]
	    : [nick stringByAppendingString:@" "];
	NSString *newText = [NSString stringWithFormat:@"%@%@%@",
	    [text substringToIndex:start], replacement,
	    [text substringFromIndex:cursor]];
	[textView setString:newText];
	[textView setSelectedRange:NSMakeRange(start + [replacement length], 0)];
	return YES;
}

#pragma mark - Window title

- (void)setWindowTitle
{
	NSString *title = @"Messages";
	MSGChannel *channel = nil;
	if (_selectedChannelId > 0) {
		channel = [_manager.combinedState channelWithIdentifier:_selectedChannelId];
	}
	MSGAccount *account = [_manager accountForChannelId:_selectedChannelId];
	if (channel && account) {
		title = [account displayName];
	}
	if (channel && [channel.name length] > 0) {
		title = [title stringByAppendingFormat:@" - %@", channel.name];
	}
	[[self window] setTitle:title];
}

#pragma mark - History loading

- (void)messageViewDidScrollToTop:(MSGMessageView *)messageView
{
	[self requestOlderContentForSelectedChannel];
}

// Asks the bouncer for one batch of messages older than the oldest one we
// hold. Single-flight via _loadingHistory; a lost response clears the flag
// after 10 seconds.
- (void)requestOlderHistoryForSelectedChannel
{
	if (_loadingHistory) {
		return;
	}
	MSGChannel *channel = [_manager.combinedState channelWithIdentifier:_selectedChannelId];
	if (!channel) {
		return;
	}
	if (!([[_manager accountForChannelId:channel.identifier] capabilities]
		& MSGCapabilityHistoryPaging)) {
		[_messageView setHasMoreHistory:NO];
		return;
	}
	if (channel.totalMessages <= (NSInteger)[channel.messages count]) {
		[_messageView setHasMoreHistory:NO];
		return;
	}
	MSGMessage *firstMessage = [channel.messages firstObject];
	if (!firstMessage) {
		return;
	}
	_loadingHistory = YES;
	// Guard against a lost "more" response leaving the flag stuck on.
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(resetHistoryLoadingFlag) object:nil];
	[self performSelector:@selector(resetHistoryLoadingFlag) withObject:nil afterDelay:10.0];
	[_manager loadMoreHistoryForChannelId:channel.identifier lastId:firstMessage.identifier];
}

// Keeps requesting older batches while the transcript is too short to be
// scrollable; otherwise reaching the top - and with it history loading -
// would be impossible. Suppressed while a filter is active, because in that
// mode scroll-to-top means "search the server", not "load older history".
- (void)autoFillHistoryIfShortTranscript
{
	if ([_filterText length] > 0) {
		return;
	}
	if (!_messageView.hasMoreHistory || [_messageView contentFillsViewport]) {
		return;
	}
	// Hard cap so a misbehaving server cannot keep us fetching forever.
	if (_autoHistoryBatches >= 10) {
		return;
	}
	if (_loadingHistory) {
		return;
	}
	_autoHistoryBatches++;
	[self requestOlderHistoryForSelectedChannel];
}

- (void)resetHistoryLoadingFlag
{
	_loadingHistory = NO;
}

#pragma mark - Transcript filtering / server search

// Forgets all filter state; called when switching channels and on teardown so
// a previous search can never leak into the next channel.
- (void)resetFilterState
{
	[_filterText release];
	_filterText = nil;
	[_searchResults removeAllObjects];
	_searchOffset = 0;
	_searchHasMore = NO;
	_searchLoading = NO;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(applySearchFilter) object:nil];
	if (_searchField && ![[_searchField stringValue] isEqualToString:@""]) {
		[_searchField setStringValue:@""];
	}
}

// Live filtering as the user types; debounced so we rebuild at most once the
// typing settles rather than on every keystroke.
- (void)controlTextDidChange:(NSNotification *)notification
{
	if ([notification object] != _searchField) {
		return;
	}
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(applySearchFilter) object:nil];
	[self performSelector:@selector(applySearchFilter) withObject:nil afterDelay:0.3];
}

- (void)applySearchFilter
{
	NSString *term = [[_searchField stringValue]
		stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	[_filterText release];
	_filterText = ([term length] > 0) ? [term retain] : nil;
	// A fresh term starts a new server search from the first page of the
	// backlog; discard any previous results.
	[_searchResults removeAllObjects];
	_searchOffset = 0;
	_searchHasMore = ([_filterText length] > 0);
	_searchLoading = NO;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(resetSearchLoadingFlag) object:nil];
	[self rebuildTranscriptForFilter];
	if ([_filterText length] > 0) {
		// The bouncer may hold matches older than what we downloaded; fetch
		// the first page of server-side matches immediately so the filter is
		// not limited to already-loaded messages.
		[self requestServerSearchForSelectedChannel];
	}
}

// Case-insensitive substring match against the message body and the sender's
// nick, which is what a user expects from a transcript filter.
- (BOOL)message:(MSGMessage *)message matchesFilter:(NSString *)filter
{
	if ([filter length] == 0) {
		return YES;
	}
	NSString *needle = [filter lowercaseString];
	if ([[[message text] lowercaseString] rangeOfString:needle].location
		!= NSNotFound) {
		return YES;
	}
	MSGUser *sender = [message sender];
	NSString *nick = sender ? [sender nick] : nil;
	if (nick && [[nick lowercaseString] rangeOfString:needle].location
		!= NSNotFound) {
		return YES;
	}
	return NO;
}

// Rebuilds the transcript from the channel's messages plus any server-side
// search results, keeping only those that match the active filter. The two
// sources are merged and deduplicated (by time+author+text, since search
// results carry synthetic ids) and ordered chronologically so backlog matches
// interleave correctly with the messages we already hold.
- (void)rebuildTranscriptForFilter
{
	MSGChannel *channel =
		[_manager.combinedState channelWithIdentifier:_selectedChannelId];
	if (!channel) {
		return;
	}
	[_messageView clear];

	NSMutableArray *combined = [NSMutableArray array];
	for (MSGMessage *message in channel.messages) {
		[combined addObject:message];
	}
	for (MSGMessage *message in _searchResults) {
		[combined addObject:message];
	}
	[combined sortUsingComparator:^NSComparisonResult(MSGMessage *a, MSGMessage *b) {
		return [a.timestamp compare:b.timestamp];
	}];

	NSMutableSet *seen = [NSMutableSet set];
	for (MSGMessage *message in combined) {
		if (![self message:message matchesFilter:_filterText]) {
			continue;
		}
		NSString *key = [NSString stringWithFormat:@"%@|%@|%@",
			[message.timestamp description], [message text] ?: @"",
			[message sender] ? [[message sender] nick] : @""];
		if ([seen containsObject:key]) {
			continue;
		}
		[seen addObject:key];
		[_messageView appendMessage:message];
	}

	if ([_filterText length] > 0) {
		[_messageView setHasMoreHistory:_searchHasMore];
	} else {
		[self updateHasMoreHistoryForChannelId:_selectedChannelId];
	}
}

// Scroll-to-top routes to a server search while filtering, otherwise to the
// usual older-history fetch.
- (void)requestOlderContentForSelectedChannel
{
	if ([_filterText length] > 0) {
		[self requestServerSearchForSelectedChannel];
	} else {
		[self requestOlderHistoryForSelectedChannel];
	}
}

// Asks the bouncer to search its stored backlog for the active filter term and
// merge the page of matches into the transcript. Pagination is by `offset`
// (the bouncer returns at most 100 per page); when a page comes back short the
// search is exhausted. Single-flight via _searchLoading; a lost response clears
// the flag after 10 seconds.
- (void)requestServerSearchForSelectedChannel
{
	if (_searchLoading || !_searchHasMore) {
		return;
	}
	MSGChannel *channel =
		[_manager.combinedState channelWithIdentifier:_selectedChannelId];
	if (!channel) {
		return;
	}
	if (!([[_manager accountForChannelId:channel.identifier] capabilities]
		& MSGCapabilityServerSearch)) {
		// Only the messages already loaded can be filtered.
		_searchHasMore = NO;
		return;
	}
	_searchLoading = YES;
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(resetSearchLoadingFlag) object:nil];
	[self performSelector:@selector(resetSearchLoadingFlag)
		withObject:nil afterDelay:10.0];
	[_manager searchMessagesForChannelId:channel.identifier
		term:_filterText offset:_searchOffset];
}

- (void)resetSearchLoadingFlag
{
	_searchLoading = NO;
}

#pragma mark - MSGNetworkOutlineViewDelegate

- (void)networkOutlineView:(MSGNetworkOutlineView *)outline didSelectChannelId:(NSInteger)channelId
{
	[self selectChannelId:channelId];
}

- (NSMenu *)networkOutlineView:(MSGNetworkOutlineView *)outline contextMenuForRowItem:(id)item
{
	MSGNetwork *network = nil;
	MSGChannel *channel = nil;
	if ([item isKindOfClass:[MSGNetwork class]]) {
		network = item;
		channel = [network lobby];
	} else if ([item isKindOfClass:[MSGChannel class]]) {
		channel = item;
		network = [_manager.combinedState networkContainingChannel:channel.identifier];
	}
	if (!channel || !network) {
		return nil;
	}
	NSString *myNick = network.nick;
	return [MSGContextMenuBuilder channelMenuForChannel:channel
		network:network myNick:myNick
		capabilities:[[_manager accountForNetwork:network] capabilities]
		delegate:self];
}

#pragma mark - MSGUserListViewDelegate

- (void)userListView:(MSGUserListView *)view didSelectRow:(NSInteger)row
{
	[_selectedUserNick release];
	_selectedUserNick = nil;
	if (row < 0) {
		return;
	}
	MSGChannel *channel = [_manager.combinedState channelWithIdentifier:_selectedChannelId];
	if (!channel) {
		return;
	}
	NSArray *users = [channel sortedUsers];
	if (row >= (NSInteger)[users count]) {
		return;
	}
	_selectedUserNick = [[[users objectAtIndex:(NSUInteger)row] nick] copy];
}

- (void)messageView:(MSGMessageView *)messageView didSelectSenderNick:(NSString *)nick
{
	// Clicking a speaker picture behaves like clicking that user's row:
	// the selection change keeps every Chat-menu action in sync.
	[_userListView selectUserWithNick:nick];
}

- (NSMenu *)userListView:(MSGUserListView *)view contextMenuForRow:(NSInteger)row
{
	MSGChannel *channel = [_manager.combinedState channelWithIdentifier:_selectedChannelId];
	if (!channel) {
		return nil;
	}
	NSArray *users = [channel sortedUsers];
	if (row < 0 || row >= (NSInteger)[users count]) {
		return nil;
	}
	MSGNetwork *network = [_manager.combinedState networkContainingChannel:channel.identifier];
	if (!network) {
		return nil;
	}
	NSString *myNick = network.nick;
	return [MSGContextMenuBuilder userMenuForUser:[users objectAtIndex:(NSUInteger)row]
		channel:channel network:network myNick:myNick
		capabilities:[[_manager accountForNetwork:network] capabilities]
		delegate:self];
}

#pragma mark - MSGContextMenuActionDelegate

- (void)contextMenuSwitchToChannelId:(NSInteger)channelId
{
	[self selectChannelId:channelId];
}

- (void)contextMenuRunCommand:(NSString *)command onChannelId:(NSInteger)channelId
{
	if ([command isEqualToString:@"/list"]) {
		MSGNetwork *network =
			[_manager.combinedState networkContainingChannel:channelId];
		if ([self networkHasGroupDirectory:network]) {
			[self showGroupListForNetwork:network];
			return;
		}
	}
	[_manager sendCommand:command toChannelId:channelId];
}

- (void)contextMenuSetMuted:(BOOL)muted forChannelId:(NSInteger)channelId
{
	[_manager setMuted:muted forChannelId:channelId];
}

- (void)contextMenuClearHistoryForChannelId:(NSInteger)channelId
{
	MSGChannel *channel = [_manager.combinedState channelWithIdentifier:channelId];
	NSString *name = channel.name ?: @"this channel";
	if (![self confirmTitled:@"Clear history"
		message:[NSString stringWithFormat:
			@"Are you sure you want to clear history for %@? This cannot be undone.",
			name]
		button:@"Clear history"]) {
		return;
	}
	[_manager clearHistoryForChannelId:channelId];
}

- (void)contextMenuCloseChannelId:(NSInteger)channelId isLobby:(BOOL)isLobby
{
	if (isLobby) {
		MSGNetwork *network = [_manager.combinedState networkContainingChannel:channelId];
		NSString *name = network.name ?: @"the network";
		if (![self confirmTitled:@"Remove network"
			message:[NSString stringWithFormat:
				@"Are you sure you want to quit and remove %@? This cannot be undone.",
				name]
			button:@"Remove network"]) {
			return;
		}
		MSGAccount *account = [_manager accountForNetwork:network];
		if ([account capabilities] & MSGCapabilityServerManagedNetworks) {
			[account.protocol removeNetwork:network];
		} else {
			[_manager removeAccount:account];
		}
		return;
	}
	// The server-side /close parts channels and closes queries.
	[_manager sendCommand:@"/close" toChannelId:channelId];
}

- (void)contextMenuJoinPromptForLobbyId:(NSInteger)lobbyId
{
	NSString *name = [self runTextPromptTitled:@"Join a channel"
		label:@"Channel name:" defaultValue:@""];
	name = [name stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([name length] == 0) {
		return;
	}
	// The web client also accepts bare names; pass through unchanged and let
	// the bouncer normalize the target. Nosterm relays handle joining by
	// creating/subscribing to a NIP-29 group instead.
	[_manager joinExistingChannelNamed:name forLobbyId:lobbyId];

	// If the join produced a channel we can see, bring it into view.
	for (MSGNetwork *network in _manager.combinedState.networks) {
		for (MSGChannel *channel in network.channels) {
			if ([channel.name isEqualToString:name]) {
				[self selectChannelId:channel.identifier];
				return;
			}
		}
	}
}

- (void)contextMenuEditTopicForChannelId:(NSInteger)channelId
{
	MSGChannel *channel = [_manager.combinedState channelWithIdentifier:channelId];
	if (!channel) {
		return;
	}
	NSString *topic = [self runTextPromptTitled:@"Edit topic"
		label:[NSString stringWithFormat:@"Topic for %@:", channel.name]
		defaultValue:channel.topic ?: @""];
	topic = [topic stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([topic length] == 0) {
		return;
	}
	[_manager sendCommand:[NSString stringWithFormat:@"/topic %@", topic]
		toChannelId:channelId];
}

- (void)contextMenuForgetNetworkForChannelId:(NSInteger)channelId
{
	MSGNetwork *network = [_manager.combinedState networkContainingChannel:channelId];
	if (!network) {
		return;
	}
	MSGAccount *account = [_manager accountForNetwork:network];
	NSString *name = [account displayName] ?: @"this account";
	if (![self confirmTitled:@"Forget account"
		message:[NSString stringWithFormat:
			@"Are you sure you want to forget %@? It will be removed from the sidebar "
			"and will not reconnect on next launch.", name]
		button:@"Forget"]) {
		return;
	}
	[_manager removeAccount:[_manager accountForNetwork:network]];
}

#pragma mark - Context menu prompts

- (BOOL)confirmTitled:(NSString *)title message:(NSString *)message
	button:(NSString *)button
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setMessageText:title];
	[alert setInformativeText:message];
	[alert addButtonWithTitle:button];
	[alert addButtonWithTitle:@"Cancel"];
	NSInteger result = [alert runModal];
	[alert release];
	return result == NSAlertFirstButtonReturn;
}

- (void)textPromptConfirmed:(id)sender
{
	[NSApp stopModalWithCode:1];
}

- (void)textPromptCancelled:(id)sender
{
	[NSApp stopModalWithCode:0];
}

- (NSString *)runTextPromptTitled:(NSString *)title
	label:(NSString *)label
	defaultValue:(NSString *)defaultValue
{
	// GNUstep's NSAlert has no accessory views, so text prompts get their
	// own small modal panel.
	NSWindow *panel = [[NSWindow alloc]
		initWithContentRect:NSMakeRect(0, 0, 320, 120)
		styleMask:(NSTitledWindowMask | NSClosableWindowMask)
		backing:NSBackingStoreBuffered defer:NO];
	[panel setTitle:title];
	[panel setReleasedWhenClosed:NO];
	[panel center];

	NSView *content = [panel contentView];
	NSRect bounds = [content bounds];

	BOOL hasLabel = [label length] > 0;
	CGFloat inputY = hasLabel ? NSHeight(bounds) - 68 : NSHeight(bounds) - 40;

	if (hasLabel) {
		NSTextField *labelField = [[NSTextField alloc] initWithFrame:
			NSMakeRect(16, NSHeight(bounds) - 36, NSWidth(bounds) - 32, 18)];
		[labelField setEditable:NO];
		[labelField setSelectable:NO];
		[labelField setBordered:NO];
		[labelField setBezeled:NO];
		[labelField setDrawsBackground:NO];
		[labelField setStringValue:label];
		[content addSubview:labelField];
		[labelField release];
	}

	NSTextField *input = [[NSTextField alloc] initWithFrame:
		NSMakeRect(16, inputY, NSWidth(bounds) - 32, 24)];
	[input setStringValue:defaultValue ?: @""];
	[input setTarget:self];
	[input setAction:@selector(textPromptConfirmed:)];
	[content addSubview:input];

	NSButton *cancelButton = [[NSButton alloc] initWithFrame:
		NSMakeRect(NSWidth(bounds) - 140, 14, 60, 26)];
	[cancelButton setTitle:@"Cancel"];
	[cancelButton setButtonType:NSMomentaryLightButton];
	[cancelButton setBezelStyle:NSRoundedBezelStyle];
	[cancelButton setTarget:self];
	[cancelButton setAction:@selector(textPromptCancelled:)];
	[content addSubview:cancelButton];
	[cancelButton release];

	NSButton *okButton = [[NSButton alloc] initWithFrame:
		NSMakeRect(NSWidth(bounds) - 74, 14, 58, 26)];
	[okButton setTitle:@"OK"];
	[okButton setButtonType:NSMomentaryLightButton];
	[okButton setBezelStyle:NSRoundedBezelStyle];
	[okButton setKeyEquivalent:@"\r"];
	[okButton setTarget:self];
	[okButton setAction:@selector(textPromptConfirmed:)];
	[content addSubview:okButton];
	[okButton release];

	[[self window] addChildWindow:panel ordered:NSWindowAbove];
	[panel makeKeyAndOrderFront:nil];
	[panel makeFirstResponder:input];
	NSString *value = nil;
	if ([NSApp runModalForWindow:panel] == 1) {
		value = [[input stringValue] retain];
	}
	[[self window] removeChildWindow:panel];
	[panel orderOut:nil];
	[panel release];
	return [value autorelease];
}

#pragma mark - NSSplitViewDelegate

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin
	ofSubviewAt:(NSInteger)dividerIndex
{
	if (dividerIndex == 0) {
		return 150.0;
	}
	return proposedMin;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax
	ofSubviewAt:(NSInteger)dividerIndex
{
	if (dividerIndex == 1) {
		return NSWidth([splitView bounds]) - 120.0;
	}
	return proposedMax;
}

#pragma mark - Chat main-menu actions

// The channel whose network-scoped commands apply: the selected channel's
// lobby.  Falls back to the first network when nothing is selected.
- (MSGNetwork *)currentChatNetwork
{
	if (_selectedChannelId > 0) {
		return [_manager.combinedState networkContainingChannel:_selectedChannelId];
	}
	MSGServerState *state = _manager.combinedState;
	return [state.networks count] > 0 ? [state.networks objectAtIndex:0] : nil;
}

- (MSGChannel *)currentChatChannel
{
	return _selectedChannelId > 0
		? [_manager.combinedState channelWithIdentifier:_selectedChannelId]
		: nil;
}

- (MSGUser *)selectedChatUserInChannel:(MSGChannel *)channel
{
	if (!_selectedUserNick) {
		return nil;
	}
	return [channel userWithNick:_selectedUserNick];
}

- (void)chatToggleConnection:(id)sender
{
	MSGNetwork *network = [self currentChatNetwork];
	if (!network) {
		return;
	}
	NSString *command = network.connected ? @"/disconnect" : @"/connect";
	[_manager sendCommand:command toChannelId:[[network lobby] identifier]];
}

- (void)chatRemoveNetwork:(id)sender
{
	MSGNetwork *network = [self currentChatNetwork];
	if (!network) {
		return;
	}
	[self contextMenuCloseChannelId:[[network lobby] identifier] isLobby:YES];
}

#pragma mark - Account menu actions

- (MSGAccount *)selectedAccount
{
	return [_manager accountForNetwork:[self currentChatNetwork]];
}

- (void)accountToggleConnection:(id)sender
{
	MSGAccount *account = [self selectedAccount];
	if (account.state == MSGConnectionStateDisconnected ||
		account.state == MSGConnectionStateAuthenticationFailed ||
		account.state == MSGConnectionStateProtocolError ||
		account.state == MSGConnectionStateConnectionError) {
		[account connect];
	} else {
		[account disconnect];
	}
}

- (void)accountShowSettings:(id)sender
{
	[(MSGApplicationDelegate *)[NSApp delegate] editAccount:[self selectedAccount]];
}

- (void)accountRemove:(id)sender
{
	MSGNetwork *network = [self currentChatNetwork];
	if (network) {
		[self contextMenuForgetNetworkForChannelId:[[network lobby] identifier]];
	}
}

// Tells the app which account the menus act on, so the Account menu can
// offer that backend's commands.
- (void)announceSelectedAccount
{
	MSGAccount *account = [self selectedAccount];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGMainWindowSelectedAccountDidChangeNotification
		object:self userInfo:account ? @{@"account": account} : @{}];
}

- (void)chatJoinChannel:(id)sender
{
	MSGNetwork *network = [self currentChatNetwork];
	if (network) {
		[self contextMenuJoinPromptForLobbyId:[[network lobby] identifier]];
	}
}

- (void)chatListChannels:(id)sender
{
	MSGNetwork *network = [self currentChatNetwork];
	if (network == nil) {
		return;
	}
	if ([self networkHasGroupDirectory:network]) {
		[self showGroupListForNetwork:network];
		return;
	}
	[self contextMenuRunCommand:@"/list"
		onChannelId:[[network lobby] identifier]];
}

// Protocols without an IRC-style channel directory list the groups they
// already know about instead of sending a no-op /list.
- (BOOL)networkHasGroupDirectory:(MSGNetwork *)network
{
	return ([[_manager accountForNetwork:network] capabilities]
		& MSGCapabilityGroupDirectory) != 0;
}

- (void)showGroupListForNetwork:(MSGNetwork *)network
{
	NSArray *names = [[_manager accountForNetwork:network].protocol knownGroupNames];
	if ([names count] == 0) {
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:@"No groups known"];
		[alert setInformativeText:
			@"No groups are known on this server yet. "
			@"Join or create one from Join Channel."];
		[alert addButtonWithTitle:@"OK"];
		[alert runModal];
		[alert release];
		return;
	}
	MSGGroupListController *panel =
		[[MSGGroupListController alloc] initWithGroupNames:names];
	[panel.window center];
	NSInteger result = [NSApp runModalForWindow:panel.window];
	if (result == 1 && [panel.selectedGroupName length] > 0) {
		[self openGroupNamed:panel.selectedGroupName
			inNetwork:network];
	}
	[panel close];
	[panel release];
}

- (void)openGroupNamed:(NSString *)name inNetwork:(MSGNetwork *)network
{
	for (MSGChannel *ch in [network channels]) {
		if ([[ch name] isEqualToString:name]) {
			// Re-send the group join in case it was missed, so posting is
			// permitted even if the group was only discovered via metadata.
			[_manager ensureJoinedChannelId:[ch identifier]];
			[self selectChannelId:[ch identifier]];
			return;
		}
	}
	NSInteger lobbyId = [network lobby] ? [[network lobby] identifier] : 0;
	[_manager joinChannelNamed:name forLobbyId:lobbyId];
}

- (void)chatListIgnoredUsers:(id)sender
{
	MSGNetwork *network = [self currentChatNetwork];
	if (network) {
		[self contextMenuRunCommand:@"/ignorelist"
			onChannelId:[[network lobby] identifier]];
	}
}

- (void)chatListBannedUsers:(id)sender
{
	MSGChannel *channel = [self currentChatChannel];
	if ([channel isChannel]) {
		[self contextMenuRunCommand:@"/banlist" onChannelId:channel.identifier];
	}
}

- (void)chatEditTopic:(id)sender
{
	MSGChannel *channel = [self currentChatChannel];
	if ([channel isChannel]) {
		[self contextMenuEditTopicForChannelId:channel.identifier];
	}
}

- (void)chatClearHistory:(id)sender
{
	MSGChannel *channel = [self currentChatChannel];
	if (channel) {
		[self contextMenuClearHistoryForChannelId:channel.identifier];
	}
}

- (void)chatToggleMuted:(id)sender
{
	MSGChannel *channel = [self currentChatChannel];
	if (channel && channel.type != MSGChannelTypeSpecial) {
		[self contextMenuSetMuted:!channel.muted forChannelId:channel.identifier];
	}
}

- (void)chatCloseCurrent:(id)sender
{
	MSGChannel *channel = [self currentChatChannel];
	if (channel) {
		[self contextMenuCloseChannelId:channel.identifier
			isLobby:(channel.type == MSGChannelTypeLobby)];
	}
}

- (NSString *)commandForSelectedUser:(NSString *)verb
{
	MSGChannel *channel = [self currentChatChannel];
	if (!channel || !_selectedUserNick) {
		return nil;
	}
	return [NSString stringWithFormat:@"/%@ %@", verb, _selectedUserNick];
}

- (void)chatWhoisSelectedUser:(id)sender
{
	NSString *command = [self commandForSelectedUser:@"whois"];
	if (command) {
		[self contextMenuRunCommand:command onChannelId:_selectedChannelId];
	}
}

- (void)chatIgnoreSelectedUser:(id)sender
{
	NSString *command = [self commandForSelectedUser:@"ignore"];
	if (command) {
		[self contextMenuRunCommand:command onChannelId:_selectedChannelId];
	}
}

- (void)chatQuerySelectedUser:(id)sender
{
	NSString *command = [self commandForSelectedUser:@"query"];
	if (command) {
		[self contextMenuRunCommand:command onChannelId:_selectedChannelId];
	}
}

- (void)chatKickSelectedUser:(id)sender
{
	NSString *command = [self commandForSelectedUser:@"kick"];
	if (command) {
		[self contextMenuRunCommand:command onChannelId:_selectedChannelId];
	}
}

- (void)chatSetMode:(NSMenuItem *)sender
{
	NSDictionary *spec = [sender representedObject];
	NSString *command = [NSString stringWithFormat:@"/mode %@%@ %@",
		[spec[@"give"] boolValue] ? @"+" : @"-",
		spec[@"mode"], _selectedUserNick];
	[self contextMenuRunCommand:command onChannelId:_selectedChannelId];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
	SEL action = [menuItem action];
	MSGChannel *channel = [self currentChatChannel];
	MSGNetwork *network = [self currentChatNetwork];
	MSGCapabilities caps = [[_manager accountForNetwork:network] capabilities];
	BOOL irc = (caps & MSGCapabilityIRCCommands) != 0;

	MSGAccount *account = [_manager accountForNetwork:network];
	BOOL managedNetworks = (caps & MSGCapabilityServerManagedNetworks) != 0;

	if (action == @selector(accountToggleConnection:)) {
		BOOL offline = account == nil ||
			account.state == MSGConnectionStateDisconnected ||
			account.state == MSGConnectionStateAuthenticationFailed ||
			account.state == MSGConnectionStateProtocolError ||
			account.state == MSGConnectionStateConnectionError;
		[menuItem setTitle:offline ? @"Connect" : @"Disconnect"];
		return account != nil;
	}
	if (action == @selector(accountShowSettings:) ||
		action == @selector(accountRemove:)) {
		return account != nil;
	}
	if (action == @selector(chatToggleConnection:)) {
		[menuItem setTitle:network.connected ? @"Disconnect Network" : @"Connect Network"];
		return network != nil && managedNetworks;
	}
	if (action == @selector(chatRemoveNetwork:)) {
		return network != nil && managedNetworks;
	}
	if (action == @selector(chatJoinChannel:)) {
		return network != nil && [account isConnected];
	}
	if (action == @selector(chatListChannels:)) {
		return network != nil && (irc || (caps & MSGCapabilityGroupDirectory));
	}
	if (action == @selector(chatListIgnoredUsers:)) {
		return network != nil && irc;
	}
	if (action == @selector(chatListBannedUsers:) ||
		action == @selector(chatEditTopic:)) {
		return irc && [channel isChannel];
	}
	if (action == @selector(chatClearHistory:)) {
		return channel != nil && (caps & MSGCapabilityClearHistory) &&
			([channel isChannel] || [channel isQuery]);
	}
	if (action == @selector(chatToggleMuted:)) {
		if (!channel || channel.type == MSGChannelTypeSpecial ||
			!(caps & MSGCapabilityMute)) {
			return NO;
		}
		NSString *type = [[MSGContextMenuBuilder humanTypeNameForChannel:channel]
			capitalizedString];
		[menuItem setTitle:[NSString stringWithFormat:
			channel.muted ? @"Unmute %@" : @"Mute %@", type]];
		return YES;
	}
	if (action == @selector(chatCloseCurrent:)) {
		// A network is removed from the Account menu, where the backend
		// says whether that is possible.
		if (!channel || [channel isLobby]) {
			[menuItem setTitle:@"Leave Channel"];
			return NO;
		}
		[menuItem setTitle:[channel isChannel] ? @"Leave Channel" : @"Close Conversation"];
		return YES;
	}

	BOOL userAction = (action == @selector(chatWhoisSelectedUser:) ||
		action == @selector(chatIgnoreSelectedUser:) ||
		action == @selector(chatQuerySelectedUser:) ||
		action == @selector(chatKickSelectedUser:) ||
		action == @selector(chatSetMode:));
	if (userAction) {
		if (!irc || !channel || !_selectedUserNick ||
			[channel userWithNick:_selectedUserNick] == nil) {
			return NO;
		}
		if (action != @selector(chatSetMode:)) {
			[menuItem setTitle:[menuItem.title stringByReplacingOccurrencesOfString:
				@"Selected User" withString:_selectedUserNick]];
		}
		// Kick and mode have additional rank checks below; Whois, Ignore,
		// Query are simply enabled when a user is selected.
		if (action != @selector(chatKickSelectedUser:) &&
			action != @selector(chatSetMode:)) {
			return YES;
		}
	}

	if (action == @selector(chatKickSelectedUser:)) {
		// Same eligibility rule as the context menu: at least half-op (or
		// operator on servers without half-ops), target unranked or below.
		MSGUser *me = [channel userWithNick:[self currentChatNetwork].nick ?: @""];
		MSGUser *target = [self selectedChatUserInChannel:channel];
		if (!me || [me.modes count] == 0 || !target) {
			return NO;
		}
		NSDictionary *prefixOptions =
			[[self currentChatNetwork] serverOptions][@"PREFIX"];
		NSArray *symbols = prefixOptions[@"symbols"];
		NSString *myTop = [me.modes objectAtIndex:0];
		NSString *requirement = [symbols containsObject:@"%"] ? @"%" : @"@";
		BOOL atLeastHalfOp = ![MSGContextMenuBuilder mode:requirement
			canActOnMode:myTop inSymbols:symbols];
		BOOL targetBelowUs = ([target.modes count] == 0 ||
			[MSGContextMenuBuilder mode:myTop
				canActOnMode:[target.modes objectAtIndex:0]
				inSymbols:symbols]);
		return atLeastHalfOp && targetBelowUs;
	}

	if (action == @selector(chatSetMode:)) {
		MSGUser *me = [channel userWithNick:[self currentChatNetwork].nick ?: @""];
		MSGUser *target = [self selectedChatUserInChannel:channel];
		if (!me || [me.modes count] == 0 || !target) {
			return NO;
		}
		NSDictionary *prefixOptions =
			[[self currentChatNetwork] serverOptions][@"PREFIX"];
		NSArray *symbols = prefixOptions[@"symbols"];
		NSString *myTop = [me.modes objectAtIndex:0];
		NSDictionary *spec = [menuItem representedObject];
		NSString *symbol = spec[@"symbol"];
		BOOL give = [spec[@"give"] boolValue];
		BOOL rankOk = [MSGContextMenuBuilder mode:myTop canActOnMode:symbol
			inSymbols:symbols];
		BOOL stateOk = give
			? ![target.modes containsObject:symbol]
			: [target.modes containsObject:symbol];
		return rankOk && stateOk;
	}

	// Actions forwarded to the app delegate (menu items target it directly).
	if (action == @selector(connectToRelay:) ||
		action == @selector(connectToDemoRelay:) ||
		action == @selector(connectToLounge:)) {
		return YES;
	}

	// Actions not implemented here must fall through so the responder chain
	// can deliver them to the app delegate (e.g. connectToRelay:).
	return NO;
}

- (BOOL)windowShouldClose:(id)sender
{
	[NSApp terminate:self];
	return YES;
}

- (void)windowDidMove:(NSNotification *)notification
{
	[[NSUserDefaults standardUserDefaults]
		setObject:NSStringFromRect([[self window] frame])
		forKey:@"MSGMainWindowFrame"];
}

- (void)windowDidEndLiveResize:(NSNotification *)notification
{
	[[NSUserDefaults standardUserDefaults]
		setObject:NSStringFromRect([[self window] frame])
		forKey:@"MSGMainWindowFrame"];
}

// The window returning to the screen means the user can see the active
// channel again, so drop its unread count right away.
- (void)windowDidBecomeKey:(NSNotification *)notification
{
	[self markActiveChannelSeen];
}

- (void)windowDidDeminiaturize:(NSNotification *)notification
{
	[self markActiveChannelSeen];
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[_manager release];
	[_splitView release];
	[_networkOutline release];
	[_messagePane release];
	[_messageView release];
	[_searchField release];
	[_searchResults release];
	[_userListView release];
	[_inputTextView release];
	[_composerBar release];
	[_dockBadge release];
	[_sendButton release];
	[_statusLabel release];
	[super dealloc];
}

@end