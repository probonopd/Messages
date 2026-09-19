/* t_contextmenu.m - ObjectTesting coverage for MSGContextMenuBuilder.
   The menus must mirror the The Lounge v4.5 web client's
   generateChannelContextMenu/generateUserContextMenu behavior.
 * SPDX-License-Identifier: BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"

#import "MSGContextMenuBuilder.h"
#import "MSGChannel.h"
#import "MSGNetwork.h"
#import "MSGUser.h"
#import "MSGProtocol.h"

static NSArray *MenuTitles(NSMenu *menu)
{
	NSMutableArray *titles = [NSMutableArray array];
	for (NSMenuItem *item in [menu itemArray]) {
		if ([item isSeparatorItem]) {
			[titles addObject:@"---"];
		} else {
			[titles addObject:[item title]];
		}
	}
	return titles;
}

static BOOL MenuHasTitle(NSMenu *menu, NSString *title)
{
	return [MenuTitles(menu) containsObject:title];
}

/* Standard IRC prefix hierarchy used by the web client's fixtures. */
static NSDictionary *PrefixOptions(void)
{
	return @{@"prefix": @[
		@{@"symbol": @"~", @"mode": @"q"},
		@{@"symbol": @"&", @"mode": @"a"},
		@{@"symbol": @"@", @"mode": @"o"},
		@{@"symbol": @"%", @"mode": @"h"},
		@{@"symbol": @"+", @"mode": @"v"}],
		@"symbols": @[@"~", @"&", @"@", @"%", @"+"]};
}

static MSGNetwork *MakeNetwork(BOOL connected)
{
	MSGNetwork *network = [[MSGNetwork alloc] initWithDictionary:@{
		@"uuid": @"u1", @"name": @"Libera", @"nick": @"me",
		@"serverOptions": @{@"PREFIX": PrefixOptions()},
		@"status": @{@"connected": connected ? @YES : @NO}}];
	network.connected = connected;
	MSGChannel *lobby = [[MSGChannel alloc] initWithDictionary:
		@{@"id": @10, @"name": @"Libera", @"type": @"lobby", @"state": @1}];
	[network addChannel:lobby];
	[lobby release];
	return [network autorelease];
}

static void AddUser(MSGChannel *channel, NSString *nick, NSArray *modes)
{
	MSGUser *user = [[MSGUser alloc] initWithDictionary:
		@{@"nick": nick, @"modes": modes}];
	[channel addUser:user];
	[user release];
}

int main(void)
{
	NSAutoreleasePool *arp = [NSAutoreleasePool new];

	/* GNUstep refuses to create menu windows without a shared application;
	   the menus themselves are built and never shown here. */
	[NSApplication sharedApplication];

	/* --- rank comparison mirrors the web client's compare() --- */
	{
		NSArray *symbols = @[@"~", @"&", @"@", @"%", @"+"];
		PASS([MSGContextMenuBuilder mode:@"~" canActOnMode:@"~" inSymbols:symbols],
			"owner can act on owner");
		PASS([MSGContextMenuBuilder mode:@"~" canActOnMode:@"+" inSymbols:symbols],
			"owner can act on voice");
		PASS([MSGContextMenuBuilder mode:@"@" canActOnMode:@"@" inSymbols:symbols],
			"op can act on op");
		PASS(![MSGContextMenuBuilder mode:@"+" canActOnMode:@"@" inSymbols:symbols],
			"voice cannot act on op");
		PASS(![MSGContextMenuBuilder mode:@"%" canActOnMode:@"@" inSymbols:symbols],
			"half-op cannot act on op");
		PASS(![MSGContextMenuBuilder mode:@"+" canActOnMode:@"+" inSymbols:symbols],
			"voice cannot act on voice");
	}

	/* --- lobby menu --- */
	{
		MSGNetwork *network = MakeNetwork(YES);
		MSGChannel *lobby = [network lobby];

		NSMenu *menu = [MSGContextMenuBuilder channelMenuForChannel:lobby
			network:network myNick:@"me" delegate:nil];
		NSArray *titles = MenuTitles(menu);

		PASS([titles count] > 2, "lobby menu has items");
		PASS([[titles objectAtIndex:0] isEqualToString:@"Libera"],
			"header shows network name");
		PASS(MenuHasTitle(menu, @"Join a channel…"), "lobby has join item");
		PASS(MenuHasTitle(menu, @"List all channels"), "lobby has /list item");
		PASS(MenuHasTitle(menu, @"List ignored users"), "lobby has /ignorelist item");
		PASS(MenuHasTitle(menu, @"Disconnect"), "connected lobby offers Disconnect");
		PASS(!MenuHasTitle(menu, @"Connect"), "connected lobby hides Connect");
		PASS(MenuHasTitle(menu, @"Forget"), "lobby has Forget item");
		PASS(MenuHasTitle(menu, @"Mute network"), "unmuted lobby offers Mute");
		PASS([[titles lastObject] isEqualToString:@"Remove"], "lobby close label is Remove");
		PASS(!MenuHasTitle(menu, @"Leave"), "no Leave on lobby");

		NSMenu *disconnected = [MSGContextMenuBuilder channelMenuForChannel:lobby
			network:MakeNetwork(NO) myNick:@"me" delegate:nil];
		PASS(MenuHasTitle(disconnected, @"Connect"), "disconnected lobby offers Connect");
		PASS(!MenuHasTitle(disconnected, @"Disconnect"), "disconnected lobby hides Disconnect");
	}

	/* --- channel menu --- */
	{
		MSGNetwork *network = MakeNetwork(YES);
		MSGChannel *chan = [[MSGChannel alloc] initWithDictionary:
			@{@"id": @11, @"name": @"#room", @"type": @"channel",
			  @"state": @1, @"muted": @NO}];
		[network addChannel:chan];

		NSMenu *menu = [MSGContextMenuBuilder channelMenuForChannel:chan
			network:network myNick:@"me" delegate:nil];
		PASS(MenuHasTitle(menu, @"Edit topic"), "channel has Edit topic");
		PASS(MenuHasTitle(menu, @"List banned users"), "channel has /banlist");
		PASS(MenuHasTitle(menu, @"Clear history"), "channel has Clear history");
		PASS(MenuHasTitle(menu, @"Mute channel"), "unmuted channel offers Mute channel");
		PASS([[MenuTitles(menu) lastObject] isEqualToString:@"Leave"],
			"channel close label is Leave");

		chan.muted = YES;
		NSMenu *muted = [MSGContextMenuBuilder channelMenuForChannel:chan
			network:network myNick:@"me" delegate:nil];
		PASS(MenuHasTitle(muted, @"Unmute channel"), "muted channel offers Unmute");
		PASS(!MenuHasTitle(muted, @"Mute channel"), "muted channel hides Mute");

		[chan release];
	}

	/* --- query menu --- */
	{
		MSGNetwork *network = MakeNetwork(YES);
		MSGChannel *query = [[MSGChannel alloc] initWithDictionary:
			@{@"id": @12, @"name": @"alice", @"type": @"query", @"state": @1}];
		[network addChannel:query];

		NSMenu *menu = [MSGContextMenuBuilder channelMenuForChannel:query
			network:network myNick:@"me" delegate:nil];
		PASS(MenuHasTitle(menu, @"User information"), "query has User information");
		PASS(MenuHasTitle(menu, @"Ignore user"), "query has Ignore user");
		PASS(MenuHasTitle(menu, @"Clear history"), "query has Clear history");
		PASS(MenuHasTitle(menu, @"Mute conversation"), "query offers Mute conversation");
		PASS([[MenuTitles(menu) lastObject] isEqualToString:@"Close"],
			"query close label is Close");

		[query release];
	}

	/* --- special channels only get header + Close --- */
	{
		MSGNetwork *network = MakeNetwork(YES);
		MSGChannel *special = [[MSGChannel alloc] initWithDictionary:
			@{@"id": @13, @"name": @"Ban list", @"type": @"special", @"state": @1}];
		[special.data setValue:@"list_bans" forKey:@"specialType"];
		[network addChannel:special];

		NSMenu *menu = [MSGContextMenuBuilder channelMenuForChannel:special
			network:network myNick:@"me" delegate:nil];
		NSArray *titles = MenuTitles(menu);
		PASS([titles count] == 3, "special menu has exactly header/divider/close");
		PASS([[titles objectAtIndex:2] isEqualToString:@"Close"], "special closes with Close");
		PASS(!MenuHasTitle(menu, @"Mute channel") && !MenuHasTitle(menu, @"Mute conversation"),
			"special cannot be muted");

		[special release];
	}

	/* --- user menu basics --- */
	{
		MSGNetwork *network = MakeNetwork(YES);
		MSGChannel *chan = [[MSGChannel alloc] initWithDictionary:
			@{@"id": @14, @"name": @"#room", @"type": @"channel", @"state": @1}];
		AddUser(chan, @"me", @[]);
		AddUser(chan, @"bob", @[]);
		[network addChannel:chan];
		MSGUser *bob = [chan userWithNick:@"bob"];

		NSMenu *menu = [MSGContextMenuBuilder userMenuForUser:bob channel:chan
			network:network myNick:@"me" delegate:nil];
		PASS([[MenuTitles(menu) objectAtIndex:0] isEqualToString:@"bob"],
			"user menu header is the nick");
		PASS(MenuHasTitle(menu, @"User information"), "user menu has whois");
		PASS(MenuHasTitle(menu, @"Ignore user"), "user menu has ignore");
		PASS(MenuHasTitle(menu, @"Direct messages"), "user menu has query");
		PASS([MenuTitles(menu) indexOfObject:@"---"] != NSNotFound, "user menu has divider");

		/* Without a mode of our own there are no op actions. */
		PASS(!MenuHasTitle(menu, @"Kick"), "plain user sees no Kick");

		[chan release];
	}

	/* --- user menu mode actions as operator --- */
	{
		MSGNetwork *network = MakeNetwork(YES);
		MSGChannel *chan = [[MSGChannel alloc] initWithDictionary:
			@{@"id": @15, @"name": @"#room", @"type": @"channel", @"state": @1}];
		AddUser(chan, @"me", @[@"@"]);
		AddUser(chan, @"boss", @[@"~"]);
		AddUser(chan, @"alice", @[@"+"]);
		AddUser(chan, @"carol", @[]);
		[network addChannel:chan];

		NSMenu *onPlain = [MSGContextMenuBuilder userMenuForUser:[chan userWithNick:@"carol"]
			channel:chan network:network myNick:@"me" delegate:nil];
		NSArray *titles = MenuTitles(onPlain);
		PASS([titles containsObject:@"Give operator (+o)"], "op sees Give operator");
		PASS([titles containsObject:@"Give owner (+q)"] == NO,
			"op cannot grant owner above their rank");
		PASS([titles containsObject:@"Give admin (+a)"] == NO,
			"op cannot grant admin above their rank");
		PASS([titles containsObject:@"Revoke operator (-o)" ] == NO, "op does not revoke own op on plain target");
		PASS([titles containsObject:@"Give half-op (+h)"], "op sees Give half-op");
		PASS([titles containsObject:@"Give voice (+v)"], "op sees Give voice");
		PASS([titles containsObject:@"Kick"], "op can kick plain user");

		NSInteger giveOp = [titles indexOfObject:@"Give operator (+o)"];
		NSInteger kick = [titles indexOfObject:@"Kick"];
		PASS(giveOp != NSNotFound && kick != NSNotFound && giveOp < kick,
			"Kick comes after the mode items");

		NSMenu *onBoss = [MSGContextMenuBuilder userMenuForUser:[chan userWithNick:@"boss"]
			channel:chan network:network myNick:@"me" delegate:nil];
		titles = MenuTitles(onBoss);
		PASS([titles containsObject:@"Revoke owner (-q)"] == NO,
			"op cannot revoke owner above them");
		PASS([titles containsObject:@"Kick"] == NO, "op cannot kick owner");

		NSMenu *onAlice = [MSGContextMenuBuilder userMenuForUser:[chan userWithNick:@"alice"]
			channel:chan network:network myNick:@"me" delegate:nil];
		titles = MenuTitles(onAlice);
		PASS([titles containsObject:@"Revoke voice (-v)"], "op revokes voice from voiced");
		PASS([titles containsObject:@"Give voice (+v)"] == NO,
			"voiced target gets revoke not give");

		[chan release];
	}

	/* --- voice users see no op actions at all --- */
	{
		MSGNetwork *network = MakeNetwork(YES);
		MSGChannel *chan = [[MSGChannel alloc] initWithDictionary:
			@{@"id": @16, @"name": @"#room", @"type": @"channel", @"state": @1}];
		AddUser(chan, @"me", @[@"+"]);
		AddUser(chan, @"bob", @[]);
		AddUser(chan, @"ops", @[@"@"]);
		[network addChannel:chan];

		NSMenu *onPlain = [MSGContextMenuBuilder userMenuForUser:[chan userWithNick:@"bob"]
			channel:chan network:network myNick:@"me" delegate:nil];
		PASS([MenuTitles(onPlain) containsObject:@"Give voice (+v)"] == NO,
			"voice user gets no Give items");
		PASS(!MenuHasTitle(onPlain, @"Kick"), "voice user sees no Kick");

		NSMenu *onOp = [MSGContextMenuBuilder userMenuForUser:[chan userWithNick:@"ops"]
			channel:chan network:network myNick:@"me" delegate:nil];
		NSArray *opTitles = MenuTitles(onOp);
		PASS([opTitles containsObject:@"Revoke operator (-o)"] == NO,
			"voice user cannot revoke op");
		PASS([opTitles containsObject:@"Give voice (+v)"] == NO,
			"voice user gets no Give items on op target");
		PASS(!MenuHasTitle(onOp, @"Kick"), "voice user sees no Kick on op");

		[chan release];
	}

	/* --- menus follow the backend's capabilities --- */
	{
		MSGCapabilities lounge = MSGCapabilityServerSearch |
			MSGCapabilityHistoryPaging | MSGCapabilityClearHistory |
			MSGCapabilityMute | MSGCapabilityIRCCommands |
			MSGCapabilityServerManagedNetworks;
		MSGCapabilities quassel = MSGCapabilityHistoryPaging |
			MSGCapabilityIRCCommands;
		MSGCapabilities nosterm = MSGCapabilityGroupDirectory |
			MSGCapabilityHistoryPaging | MSGCapabilityClearHistory |
			MSGCapabilityMute;
		MSGNetwork *network = MakeNetwork(YES);
		MSGChannel *lobby = [network lobby];
		MSGChannel *channel = [[[MSGChannel alloc] initWithDictionary:
			@{@"id": @11, @"name": @"#gnustep", @"type": @"channel",
			  @"state": @1}] autorelease];
		[network addChannel:channel];
		MSGChannel *query = [[[MSGChannel alloc] initWithDictionary:
			@{@"id": @12, @"name": @"alice", @"type": @"query"}] autorelease];
		[network addChannel:query];

		NSMenu *m = [MSGContextMenuBuilder channelMenuForChannel:lobby
			network:network myNick:@"me" capabilities:lounge delegate:nil];
		PASS(MenuHasTitle(m, @"List ignored users") && MenuHasTitle(m, @"Disconnect"),
			"bouncer lobby keeps IRC and network items");

		m = [MSGContextMenuBuilder channelMenuForChannel:lobby
			network:network myNick:@"me" capabilities:quassel delegate:nil];
		PASS(MenuHasTitle(m, @"List all channels") && !MenuHasTitle(m, @"Disconnect"),
			"networks the client does not manage offer no connect item");
		PASS(!MenuHasTitle(m, @"Remove"),
			"networks the client does not manage cannot be removed");

		m = [MSGContextMenuBuilder channelMenuForChannel:lobby
			network:network myNick:@"me" capabilities:nosterm delegate:nil];
		PASS(!MenuHasTitle(m, @"List ignored users") && !MenuHasTitle(m, @"Disconnect"),
			"relay lobby has no IRC items");
		PASS(MenuHasTitle(m, @"List all channels") && MenuHasTitle(m, @"Join a channel…"),
			"relay lobby lists groups and joins");

		m = [MSGContextMenuBuilder channelMenuForChannel:channel
			network:network myNick:@"me" capabilities:nosterm delegate:nil];
		PASS(!MenuHasTitle(m, @"Edit topic") && !MenuHasTitle(m, @"List banned users"),
			"relay channel has no IRC items");
		PASS(MenuHasTitle(m, @"Clear history") && MenuHasTitle(m, @"Leave"),
			"relay channel keeps generic items");

		m = [MSGContextMenuBuilder channelMenuForChannel:channel
			network:network myNick:@"me" capabilities:quassel delegate:nil];
		PASS(!MenuHasTitle(m, @"Clear history") && !MenuHasTitle(m, @"Mute channel"),
			"items for missing capabilities are left out");

		m = [MSGContextMenuBuilder channelMenuForChannel:query
			network:network myNick:@"me" capabilities:nosterm delegate:nil];
		PASS(!MenuHasTitle(m, @"User information"), "relay query has no whois");

		MSGUser *alice = [[[MSGUser alloc] initWithDictionary:
			@{@"nick": @"alice", @"modes": @[]}] autorelease];
		PASS([MSGContextMenuBuilder userMenuForUser:alice channel:channel
			network:network myNick:@"me" capabilities:nosterm delegate:nil] == nil,
			"no user menu without IRC commands");
		PASS([MSGContextMenuBuilder userMenuForUser:alice channel:channel
			network:network myNick:@"me" capabilities:quassel delegate:nil] != nil,
			"IRC backends keep the user menu");
	}

	[arp release];
	return 0;
}
