/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLoungeBackend.h"
#import "TLoungeAccount.h"

@implementation TLoungeBackend

+ (NSString *)backendIdentifier
{
	return @"io.github.gershwin-desktop.Messages.TheLounge";
}

+ (NSString *)displayName
{
	return @"The Lounge";
}

+ (Class)accountClass
{
	return [TLoungeAccount class];
}

+ (NSArray *)accountSettingFields
{
	return @[
		@{MSGSettingFieldKey: @"url", MSGSettingFieldLabel: @"Server URL:",
			MSGSettingFieldType: MSGSettingFieldTypeText,
			MSGSettingFieldPlaceholder: @"https://lounge.example.net/",
			MSGSettingFieldRequired: @YES},
		@{MSGSettingFieldKey: @"username", MSGSettingFieldLabel: @"Username:",
			MSGSettingFieldType: MSGSettingFieldTypeText,
			MSGSettingFieldRequired: @YES},
		@{MSGSettingFieldKey: @"password", MSGSettingFieldLabel: @"Password:",
			MSGSettingFieldType: MSGSettingFieldTypeSecure}];
}

+ (NSString *)validationErrorForSettings:(NSDictionary *)settings
{
	NSURL *url = [NSURL URLWithString:settings[@"url"] ?: @""];
	NSString *scheme = [[url scheme] lowercaseString];
	if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) ||
		[[url host] length] == 0) {
		return @"Enter the server URL, for example https://lounge.example.net/.";
	}
	if ([settings[@"username"] length] == 0) {
		return @"Enter your username.";
	}
	if ([settings[@"password"] length] == 0 && [settings[@"token"] length] == 0) {
		return @"Enter your password.";
	}
	return nil;
}

@end
