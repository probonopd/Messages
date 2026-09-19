/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "NTNostermBackend.h"
#import "NTNostermAccount.h"
#import "NTNostrSocketClient.h"

@implementation NTNostermBackend

+ (NSString *)backendIdentifier
{
	return @"io.github.gershwin-desktop.Messages.Nosterm";
}

+ (NSString *)displayName
{
	return @"Nosterm Relay";
}

+ (Class)accountClass
{
	return [NTNostermAccount class];
}

+ (NSArray *)accountSettingFields
{
	return @[
		@{MSGSettingFieldKey: @"url", MSGSettingFieldLabel: @"Relay URL:",
			MSGSettingFieldType: MSGSettingFieldTypeText,
			MSGSettingFieldPlaceholder: NTNostermDefaultRelayURL,
			MSGSettingFieldDefault: NTNostermDefaultRelayURL,
			MSGSettingFieldRequired: @YES},
		@{MSGSettingFieldKey: @"username", MSGSettingFieldLabel: @"Display name:",
			MSGSettingFieldType: MSGSettingFieldTypeText,
			MSGSettingFieldRequired: @YES},
		@{MSGSettingFieldKey: @"privateKey", MSGSettingFieldLabel: @"Private key:",
			MSGSettingFieldType: MSGSettingFieldTypeSecure,
			MSGSettingFieldPlaceholder: @"64 hex digits, optional"}];
}

+ (NSString *)validationErrorForSettings:(NSDictionary *)settings
{
	NSURL *url = [NSURL URLWithString:settings[@"url"] ?: @""];
	NSString *scheme = [[url scheme] lowercaseString];
	if (!([scheme isEqualToString:@"ws"] || [scheme isEqualToString:@"wss"]) ||
		[[url host] length] == 0) {
		return @"Enter the relay URL, for example wss://relay.example.net/.";
	}
	if ([settings[@"username"] length] == 0) {
		return @"Enter a display name.";
	}
	NSString *key = settings[@"privateKey"];
	if ([key length] > 0) {
		NSCharacterSet *nonHex = [[NSCharacterSet characterSetWithCharactersInString:
			@"0123456789abcdefABCDEF"] invertedSet];
		if ([key length] != 64 ||
			[key rangeOfCharacterFromSet:nonHex].location != NSNotFound) {
			return @"The private key must be 64 hexadecimal digits.";
		}
	}
	return nil;
}

+ (NSArray *)quickConnectPresets
{
	return @[@{MSGPresetTitle: @"Nosterm Demo Relay",
		MSGPresetSettings: @{@"url": NTNostermDefaultRelayURL, @"username": @"guest"}}];
}

@end
