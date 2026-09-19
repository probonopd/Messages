/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* t_outline.m - selection in the network outline stays on the item the
 * window shows while rows are added above it (another account loading),
 * and clicks on rows are reported so the window can move the cursor to the
 * composer. Headless AppKit. */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"

#import "MSGNetworkOutlineView.h"
#import "MSGServerState.h"
#import "MSGNetwork.h"
#import "MSGChannel.h"

static MSGNetwork *Network(NSString *uuid, NSInteger lobbyId)
{
	MSGNetwork *network = [[[MSGNetwork alloc] init] autorelease];
	network.uuid = uuid;
	network.name = uuid;
	MSGChannel *lobby = [[[MSGChannel alloc] init] autorelease];
	lobby.identifier = lobbyId;
	lobby.name = uuid;
	lobby.type = MSGChannelTypeLobby;
	lobby.state = MSGChannelStateJoined;
	[network addChannel:lobby];
	MSGChannel *channel = [[[MSGChannel alloc] init] autorelease];
	channel.identifier = lobbyId + 1;
	channel.name = @"#general";
	channel.type = MSGChannelTypeChannel;
	channel.state = MSGChannelStateJoined;
	[network addChannel:channel];
	return network;
}

// Records what the outline reports.
@interface ClickRecorder : NSObject <MSGNetworkOutlineViewDelegate>
{
@public
	NSMutableArray *clicked;
}
@end

@implementation ClickRecorder
- (id)init
{
	if ((self = [super init])) {
		clicked = [NSMutableArray new];
	}
	return self;
}
- (void)dealloc
{
	[clicked release];
	[super dealloc];
}
- (void)networkOutlineView:(MSGNetworkOutlineView *)outline didSelectChannelId:(NSInteger)channelId
{
}
- (void)networkOutlineView:(MSGNetworkOutlineView *)outline didClickItem:(id)item
{
	[clicked addObject:item];
}
@end

static NSOutlineView *InnerOutline(NSView *view)
{
	if ([view isKindOfClass:[NSOutlineView class]]) {
		return (NSOutlineView *)view;
	}
	for (NSView *sub in [view subviews]) {
		NSOutlineView *found = InnerOutline(sub);
		if (found) {
			return found;
		}
	}
	return nil;
}

// What the table does at the end of a real click: the clicked row is only
// set while a mouse event is handled, so the test sets it the same way.
static void Click(NSOutlineView *table, NSInteger row)
{
	[table setValue:@(row) forKey:@"_clickedRow"];
	[NSApp sendAction:[table action] to:[table target] from:table];
}

int main(void)
{
	NSAutoreleasePool *arp = [NSAutoreleasePool new];
	[NSApplication sharedApplication];

	MSGServerState *state = [[[MSGServerState alloc] init] autorelease];
	MSGNetwork *quassel = Network(@"TestNet", 10);
	[state addNetwork:quassel];
	MSGNetworkOutlineView *outline = [[[MSGNetworkOutlineView alloc]
		initWithFrame:NSMakeRect(0, 0, 200, 400)] autorelease];
	[outline setServerState:state];
	[outline reloadData];

	[outline setSelectedChannelId:10];
	[outline selectChannelId:10];
	PASS([outline selectedItem] == quassel,
		"a lobby selected from code highlights its network row");

	// Another account's network loads and sorts above it.
	MSGNetwork *relay = Network(@"relay", 20);
	[state.networks insertObject:relay atIndex:0];
	[outline reloadData];
	PASS([outline selectedItem] == quassel,
		"the highlight follows the network when rows are added above it");

	[outline selectChannelId:21];
	MSGChannel *selected = [outline selectedItem];
	PASS([selected isKindOfClass:[MSGChannel class]] && selected.identifier == 21,
		"channels select their own row");

	ClickRecorder *recorder = [[ClickRecorder new] autorelease];
	[outline setDelegate:recorder];
	NSOutlineView *table = InnerOutline(outline);
	NSInteger relayRow = [table rowForItem:relay];
	NSInteger generalRow = [table rowForItem:[quassel channelWithIdentifier:11]];
	Click(table, relayRow);
	Click(table, generalRow);
	Click(table, generalRow);
	NSArray *expected = @[relay, [quassel channelWithIdentifier:11],
		[quassel channelWithIdentifier:11]];
	PASS_EQUAL(recorder->clicked, expected,
		"every click on a server or channel row is reported, also on the selected one");
	Click(table, -1);
	PASS([recorder->clicked count] == 3, "a click below the rows is not");
	[outline setDelegate:nil];

	// Nothing paints the part of the clip view the table does not cover,
	// so scrolling would copy stale pixels there; the table must span it.
	NSClipView *clip = (NSClipView *)[table superview];
	// The table re-tiles to its columns whenever rows expand or change.
	[outline setFrameSize:NSMakeSize(320, 400)];
	[table tile];
	PASS(fabs(NSWidth([table frame]) - NSWidth([clip bounds])) < 0.01,
		"the table covers the clip view when the sidebar gets wider");
	[outline setFrameSize:NSMakeSize(180, 400)];
	PASS(fabs(NSWidth([table frame]) - NSWidth([clip bounds])) < 0.01,
		"and when it gets narrower");

	[arp release];
	return 0;
}
