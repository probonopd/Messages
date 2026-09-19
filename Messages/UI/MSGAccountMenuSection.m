/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "MSGAccountMenuSection.h"

@implementation MSGAccountMenuSection

+ (NSMenuItem *)itemWithTitle:(NSString *)title action:(SEL)action
{
	return [[[NSMenuItem alloc] initWithTitle:title action:action
		keyEquivalent:@""] autorelease];
}

// Standard IRC ranks; the items are enabled only when the server has the
// mode and our own rank permits it (checked against PREFIX when the menu
// is validated).
+ (NSMenu *)operatorMenu
{
	NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"Operator"] autorelease];
	NSArray *ranks = @[
		@{@"mode": @"q", @"symbol": @"~", @"name": @"Owner"},
		@{@"mode": @"a", @"symbol": @"&", @"name": @"Admin"},
		@{@"mode": @"o", @"symbol": @"@", @"name": @"Operator"},
		@{@"mode": @"h", @"symbol": @"%", @"name": @"Half-op"},
		@{@"mode": @"v", @"symbol": @"+", @"name": @"Voice"}];
	for (NSDictionary *rank in ranks) {
		NSMenuItem *give = [self itemWithTitle:[NSString stringWithFormat:
			@"Give %@ (+%@)", rank[@"name"], rank[@"mode"]]
			action:@selector(chatSetMode:)];
		[give setRepresentedObject:@{@"mode": rank[@"mode"],
			@"symbol": rank[@"symbol"], @"give": @YES}];
		[menu addItem:give];
		NSMenuItem *revoke = [self itemWithTitle:[NSString stringWithFormat:
			@"Revoke %@ (-%@)", rank[@"name"], rank[@"mode"]]
			action:@selector(chatSetMode:)];
		[revoke setRepresentedObject:@{@"mode": rank[@"mode"],
			@"symbol": rank[@"symbol"], @"give": @NO}];
		[menu addItem:revoke];
	}
	return menu;
}

+ (NSMenuItem *)userItem
{
	NSMenu *menu = [[[NSMenu alloc] initWithTitle:@"User"] autorelease];
	[menu addItem:[self itemWithTitle:@"User Information"
		action:@selector(chatWhoisSelectedUser:)]];
	[menu addItem:[self itemWithTitle:@"Send Message"
		action:@selector(chatQuerySelectedUser:)]];
	[menu addItem:[self itemWithTitle:@"Ignore User"
		action:@selector(chatIgnoreSelectedUser:)]];
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItem:[self itemWithTitle:@"Kick"
		action:@selector(chatKickSelectedUser:)]];
	NSMenuItem *operatorItem = [self itemWithTitle:@"Operator" action:NULL];
	[operatorItem setSubmenu:[self operatorMenu]];
	[menu addItem:operatorItem];

	NSMenuItem *item = [self itemWithTitle:@"User" action:NULL];
	[item setSubmenu:menu];
	return item;
}

+ (NSArray *)itemsForCapabilities:(MSGCapabilities)capabilities
{
	NSMutableArray *items = [NSMutableArray array];
	if (capabilities & MSGCapabilityIRCCommands) {
		[items addObject:[self itemWithTitle:@"List All Channels"
			action:@selector(chatListChannels:)]];
		[items addObject:[self itemWithTitle:@"Edit Topic…"
			action:@selector(chatEditTopic:)]];
		[items addObject:[self itemWithTitle:@"List Ignored Users"
			action:@selector(chatListIgnoredUsers:)]];
		[items addObject:[self itemWithTitle:@"List Banned Users"
			action:@selector(chatListBannedUsers:)]];
		if (capabilities & MSGCapabilityServerManagedNetworks) {
			[items addObject:[NSMenuItem separatorItem]];
			// Retitled Connect/Disconnect Network when validated.
			[items addObject:[self itemWithTitle:@"Connect Network"
				action:@selector(chatToggleConnection:)]];
			[items addObject:[self itemWithTitle:@"Remove Network…"
				action:@selector(chatRemoveNetwork:)]];
		}
		[items addObject:[NSMenuItem separatorItem]];
		[items addObject:[self userItem]];
	} else if (capabilities & MSGCapabilityGroupDirectory) {
		[items addObject:[self itemWithTitle:@"Browse Groups…"
			action:@selector(chatListChannels:)]];
	}
	return items;
}

@end
