/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGPreferences.h"

NSString *const MSGBubbleStyleDidChangeNotification =
	@"MSGBubbleStyleDidChangeNotification";

static NSString * const MSGUseBubblesKey = @"MSGUseBubbleStyle";
static NSString * const MSGPlaySoundOnIncomingMessagesKey = @"MSGPlaySoundOnIncomingMessages";
static NSString * const MSGLastChannelsKey = @"MSGLastOpenChannels";

@interface MSGPreferences : NSObject
+ (void)initialize;
@end

@implementation MSGPreferences

+ (void)initialize
{
	if (self == [MSGPreferences class]) {
		NSDictionary *defaults = [NSDictionary dictionaryWithObjectsAndKeys:
			@YES, MSGPlaySoundOnIncomingMessagesKey, nil];
		[[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
	}
}

BOOL MSGPreferencesUseBubbles(void)
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:MSGUseBubblesKey];
}

void MSGPreferencesSetUseBubbles(BOOL flag)
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	BOOL current = [defaults boolForKey:MSGUseBubblesKey];
	if (current == flag) {
		return;
	}
	[defaults setBool:flag forKey:MSGUseBubblesKey];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGBubbleStyleDidChangeNotification object:nil];
}

BOOL MSGPreferencesPlaySoundOnIncomingMessages(void)
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:MSGPlaySoundOnIncomingMessagesKey];
}

void MSGPreferencesSetPlaySoundOnIncomingMessages(BOOL flag)
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setBool:flag forKey:MSGPlaySoundOnIncomingMessagesKey];
}

NSDictionary *MSGPreferencesLastChannelForServer(NSString *server)
{
	if ([server length] == 0) {
		return nil;
	}
	NSDictionary *all = [[NSUserDefaults standardUserDefaults]
		dictionaryForKey:MSGLastChannelsKey];
	return [all objectForKey:server];
}

void MSGPreferencesSetLastChannelId(NSInteger identifier
	, NSString *name
	, NSString *server)
{
	if ([server length] == 0) {
		return;
	}
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *all = [[[defaults
		dictionaryForKey:MSGLastChannelsKey] mutableCopy] autorelease];
	if (all == nil) {
		all = [NSMutableDictionary dictionary];
	}
	[all setObject:[NSDictionary dictionaryWithObjectsAndKeys:
		@(identifier), @"id", name ?: @"", @"name", nil]
		forKey:server];
	[defaults setObject:all forKey:MSGLastChannelsKey];
}

@end

NSString *MSGApplicationSupportDirectory(void)
{
	NSString *appSupport = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
		NSUserDomainMask, YES) firstObject];
	NSString *dir = [appSupport stringByAppendingPathComponent:@"Messages"];
	if (![[NSFileManager defaultManager] fileExistsAtPath:dir]) {
		[[NSFileManager defaultManager] createDirectoryAtPath:dir
			withIntermediateDirectories:YES
			attributes:@{NSFilePosixPermissions: @0700}
			error:NULL];
	}
	return dir;
}
