/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "MSGNetwork.h"
#import "MSGChannel.h"
#import "MSGServerState.h"

static MSGChannel *mk(NSInteger ident, NSString *name, MSGChannelType type, NSInteger unseen, BOOL muted, MSGChannelState st, BOOL closed)
{
	MSGChannel *c = [[MSGChannel alloc] initWithDictionary:@{
		@"id": @(ident), @"name": name, @"type": MSGChannelTypeToString(type)}];
	c.unseen = unseen;
	c.unseenHighlight = 0;
	c.muted = muted;
	c.closed = closed;
	c.state = st;
	return c;
}

// Dock sum over the model (what -[MSGNetwork badgeTotal] feeds the Dock).
static NSInteger dockSum(MSGServerState *state)
{
	NSInteger total = 0;
	for (MSGNetwork *net in state.networks) total += [net badgeTotal];
	return total;
}

// Pane sum: network row shows badgeTotal minus the VISIBLE channel badges
// (hidden/parted channels roll up into the network row), and visible channel
// rows show their own badge.
static NSInteger paneSum(MSGServerState *state, BOOL expanded, NSArray *(^visible)(MSGNetwork *))
{
	NSInteger pane = 0;
	for (MSGNetwork *net in state.networks) {
		NSInteger total = [net badgeTotal];
		NSInteger perChannel = 0;
		if (expanded) {
			for (MSGChannel *c in visible(net)) perChannel += [c badgeCount];
		}
		pane += (total - perChannel);
		if (expanded) {
			for (MSGChannel *c in visible(net)) pane += [c badgeCount];
		}
	}
	return pane;
}

int main(void)
{
	@autoreleasepool {
		MSGServerState *state = [[MSGServerState alloc] init];
		MSGNetwork *net = [[MSGNetwork alloc] initWithDictionary:@{@"id": @"u1", @"name": @"NetOne"}];
		// lobby (server) unread=2, two joined channels, one PARTED channel
		// with unread=18 (hidden from the outline), one muted (unread=5).
		[net addChannel:mk(1, @"Server", MSGChannelTypeLobby, 2, NO, MSGChannelStateJoined, NO)];
		[net addChannel:mk(2, @"#big", MSGChannelTypeChannel, 70, NO, MSGChannelStateJoined, NO)];
		[net addChannel:mk(3, @"#small", MSGChannelTypeChannel, 1, NO, MSGChannelStateJoined, NO)];
		[net addChannel:mk(4, @"#parted", MSGChannelTypeChannel, 18, NO, MSGChannelStateParted, NO)];
		[net addChannel:mk(5, @"#muted", MSGChannelTypeChannel, 5, YES, MSGChannelStateJoined, NO)];
		[state addNetwork:net];

		// Visible == joined && !closed (matches visibleChannelsForNetwork).
		NSArray *(^visible)(MSGNetwork *) = ^NSArray *(MSGNetwork *n) {
			NSMutableArray *r = [NSMutableArray array];
			for (MSGChannel *c in n.channels)
				if (c.state == MSGChannelStateJoined && !c.closed) [r addObject:c];
			return r;
		};

		NSInteger dock = dockSum(state);
		NSInteger pane = paneSum(state, YES, visible);

		NSLog(@"dock=%ld paneExpanded=%ld", (long)dock, (long)pane);
		NSLog(@"badgeTotal=%ld (lobby2 + big70 + small1 + parted18 + muted0)", (long)[net badgeTotal]);

		if (dock == pane) { NSLog(@"PASS"); return 0; }
		NSLog(@"FAIL: dock != pane"); return 1;
	}
}
