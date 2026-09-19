/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* t_outline.m - selection in the network outline stays on the item the
 * window shows while rows are added above it (another account loading).
 * Headless AppKit. */

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

	[arp release];
	return 0;
}
