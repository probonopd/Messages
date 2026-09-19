/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* t_accountui.m - the backend section of the Account menu and the settings
 * form built from a backend's field descriptions. Headless AppKit. */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"

#import "MSGAccountMenuSection.h"
#import "MSGSettingsFormView.h"
#import "MSGBackend.h"
#import "MSGProtocol.h"

static NSArray *Titles(NSArray *items)
{
	NSMutableArray *titles = [NSMutableArray array];
	for (NSMenuItem *item in items) {
		[titles addObject:[item isSeparatorItem] ? @"---" : [item title]];
	}
	return titles;
}

static NSMenuItem *ItemTitled(NSArray *items, NSString *title)
{
	for (NSMenuItem *item in items) {
		if ([[item title] isEqualToString:title]) {
			return item;
		}
	}
	return nil;
}

static NSArray *Fields(void)
{
	return @[
		@{MSGSettingFieldKey: @"host", MSGSettingFieldLabel: @"Host:",
			MSGSettingFieldType: MSGSettingFieldTypeText,
			MSGSettingFieldRequired: @YES},
		@{MSGSettingFieldKey: @"port", MSGSettingFieldLabel: @"Port:",
			MSGSettingFieldType: MSGSettingFieldTypeNumber,
			MSGSettingFieldDefault: @4242},
		@{MSGSettingFieldKey: @"password", MSGSettingFieldLabel: @"Password:",
			MSGSettingFieldType: MSGSettingFieldTypeSecure},
		@{MSGSettingFieldKey: @"tls", MSGSettingFieldLabel: @"Use TLS",
			MSGSettingFieldType: MSGSettingFieldTypeCheckbox}];
}

int main(void)
{
	NSAutoreleasePool *arp = [NSAutoreleasePool new];
	[NSApplication sharedApplication];

	START_SET("account menu section")
	MSGCapabilities lounge = MSGCapabilityIRCCommands |
		MSGCapabilityServerManagedNetworks | MSGCapabilityMute;
	MSGCapabilities quassel = MSGCapabilityIRCCommands | MSGCapabilityHistoryPaging;
	MSGCapabilities nosterm = MSGCapabilityGroupDirectory | MSGCapabilityMute;

	NSArray *items = [MSGAccountMenuSection itemsForCapabilities:lounge];
	NSArray *titles = Titles(items);
	PASS([titles containsObject:@"List All Channels"] &&
		[titles containsObject:@"Edit Topic…"] &&
		[titles containsObject:@"List Ignored Users"] &&
		[titles containsObject:@"List Banned Users"], "IRC items for a bouncer");
	PASS([titles containsObject:@"Connect Network"] &&
		[titles containsObject:@"Remove Network…"], "network items for a bouncer");
	NSMenuItem *user = ItemTitled(items, @"User");
	NSArray *userTitles = Titles([[user submenu] itemArray]);
	PASS(user != nil && [userTitles containsObject:@"User Information"] &&
		[userTitles containsObject:@"Kick"] && [userTitles containsObject:@"Operator"],
		"user actions are grouped in a submenu");
	PASS([[ItemTitled([[user submenu] itemArray], @"Operator") submenu]
		numberOfItems] == 10, "operator submenu gives and revokes five ranks");
	PASS([ItemTitled(items, @"List All Channels") target] == nil,
		"items go through the responder chain");

	titles = Titles([MSGAccountMenuSection itemsForCapabilities:quassel]);
	PASS([titles containsObject:@"List All Channels"] &&
		![titles containsObject:@"Remove Network…"] &&
		![titles containsObject:@"Connect Network"],
		"no network management where the client does not own the networks");

	titles = Titles([MSGAccountMenuSection itemsForCapabilities:nosterm]);
	NSArray *groupsOnly = @[@"Browse Groups…"];
	PASS_EQUAL(titles, groupsOnly, "a relay only offers its group directory");

	PASS([[MSGAccountMenuSection itemsForCapabilities:0] count] == 0,
		"nothing for a backend without extras");
	END_SET("account menu section")

	START_SET("settings form")
	NSArray *fields = Fields();
	CGFloat height = [MSGSettingsFormView heightForFields:fields];
	PASS(height == 4 * 30.0 - 8.0, "rows follow the 30px rhythm");
	MSGSettingsFormView *form = [[[MSGSettingsFormView alloc]
		initWithFields:fields width:360 labelWidth:100] autorelease];
	PASS(NSHeight([form frame]) == height, "form is as tall as its rows");

	PASS_EQUAL([form missingRequiredFieldLabel], @"Host",
		"an empty required field is reported by its label");
	NSDictionary *empty = [form settingsByMergingInto:@{}];
	PASS_EQUAL(empty[@"port"], @4242, "defaults fill empty settings");

	[form setSettings:@{@"host": @"core.example.net", @"port": @6000,
		@"password": @"pw", @"tls": @YES}];
	PASS([form missingRequiredFieldLabel] == nil, "required fields are filled");
	NSDictionary *base = @{@"token": @"keep", @"password": @"old"};
	NSDictionary *merged = [form settingsByMergingInto:base];
	PASS_EQUAL(merged[@"host"], @"core.example.net", "text round-trips");
	PASS_EQUAL(merged[@"port"], @6000, "numbers come back as numbers");
	PASS_EQUAL(merged[@"tls"], @YES, "checkboxes come back as booleans");
	PASS_EQUAL(merged[@"password"], @"pw", "secure fields round-trip");
	PASS_EQUAL(merged[@"token"], @"keep", "settings the form does not show are kept");

	[form setSettings:@{@"host": @"core.example.net"}];
	merged = [form settingsByMergingInto:base];
	PASS(merged[@"password"] == nil, "a cleared field removes the setting");

	__block NSUInteger changes = 0;
	id observer = [[NSNotificationCenter defaultCenter]
		addObserverForName:MSGSettingsFormViewDidChangeNotification object:form
		queue:nil usingBlock:^(NSNotification *note) { changes++; }];
	[form controlTextDidChange:[NSNotification
		notificationWithName:NSControlTextDidChangeNotification object:nil]];
	PASS(changes == 1, "edits are announced for dirty tracking");
	[[NSNotificationCenter defaultCenter] removeObserver:observer];
	END_SET("settings form")

	[arp release];
	return 0;
}
