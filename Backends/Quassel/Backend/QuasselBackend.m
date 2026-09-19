/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "QuasselBackend.h"
#import "QuasselAccount.h"

@implementation QuasselBackend

+ (NSString *)backendIdentifier
{
	return @"io.github.gershwin-desktop.Messages.Quassel";
}

+ (NSString *)displayName
{
	return @"Quassel Core";
}

+ (Class)accountClass
{
	return [QuasselAccount class];
}

+ (NSArray *)accountSettingFields
{
	return @[
		@{MSGSettingFieldKey: @"host", MSGSettingFieldLabel: @"Core host:",
			MSGSettingFieldType: MSGSettingFieldTypeText,
			MSGSettingFieldPlaceholder: @"quassel.example.net",
			MSGSettingFieldRequired: @YES},
		@{MSGSettingFieldKey: @"port", MSGSettingFieldLabel: @"Port:",
			MSGSettingFieldType: MSGSettingFieldTypeNumber,
			MSGSettingFieldDefault: @4242},
		@{MSGSettingFieldKey: @"username", MSGSettingFieldLabel: @"Username:",
			MSGSettingFieldType: MSGSettingFieldTypeText,
			MSGSettingFieldRequired: @YES},
		@{MSGSettingFieldKey: @"password", MSGSettingFieldLabel: @"Password:",
			MSGSettingFieldType: MSGSettingFieldTypeSecure,
			MSGSettingFieldRequired: @YES}];
}

+ (NSString *)validationErrorForSettings:(NSDictionary *)settings
{
	NSString *host = settings[@"host"];
	if ([host length] == 0 || [host rangeOfString:@"/"].location != NSNotFound) {
		return @"Enter the host name of the Quassel core, without a URL scheme.";
	}
	id port = settings[@"port"];
	if (port != nil && ([port intValue] <= 0 || [port intValue] > 65535)) {
		return @"The port must be between 1 and 65535.";
	}
	if ([settings[@"username"] length] == 0) {
		return @"Enter your username.";
	}
	if ([settings[@"password"] length] == 0) {
		return @"Enter your password.";
	}
	return nil;
}

@end
