/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class MSGNetworkOutlineView;
@class MSGServerState;

@protocol MSGNetworkOutlineViewDelegate <NSObject>
- (void)networkOutlineView:(MSGNetworkOutlineView *)outline didSelectChannelId:(NSInteger)channelId;
@optional
// Returned menu is popped up at the mouse; item is a MSGNetwork or MSGChannel.
- (NSMenu *)networkOutlineView:(MSGNetworkOutlineView *)outline contextMenuForRowItem:(id)item;
@end

// The GNUstep data source/delegate protocols do not mark their optional
// methods as optional, so conformance is not declared here; the required
// methods are implemented in the class.
@interface MSGNetworkOutlineView : NSView
{
	NSScrollView *_scrollView;
	NSOutlineView *_outlineView;
	MSGServerState *_serverState;
	NSInteger _selectedChannelId;
	id<MSGNetworkOutlineViewDelegate> _delegate;
}

@property (nonatomic, assign) id<MSGNetworkOutlineViewDelegate> delegate;
@property (nonatomic, retain) MSGServerState *serverState;
@property (nonatomic, assign) NSInteger selectedChannelId;

- (void)reloadData;
- (void)selectChannelId:(NSInteger)channelId;
// The highlighted row's MSGNetwork or MSGChannel, nil when none.
- (id)selectedItem;

@end