/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

// CLI-only read test: connects to the Nosterm relay, subscribes to #general,
// collects messages, and prints the last 3 with resolved nicknames.
// No key needed, but connecting publishes a profile for the test nickname
// under a fresh key, so it only runs when the relay is named explicitly:
//
//   TL_NOSTERM_TEST_RELAY=wss://chat.nosterm.com/relay ./obj/t_nosterm_read

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "TestAccounts.h"
#import "MSGServerState.h"
#import "MSGNetwork.h"
#import "MSGChannel.h"
#import "MSGMessage.h"
#import "NTNostrCrypto.h"
#import "MSGLogger.h"

static BOOL g_ready = NO;
static BOOL g_messagesChanged = NO;

static BOOL TLWaitFor(BOOL *flag, NSTimeInterval timeout)
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while (!*flag && [[NSDate date] compare:deadline] == NSOrderedAscending) {
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
			beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
	}
	return *flag;
}

@interface ReadObserver : NSObject
@end

@implementation ReadObserver

- (void)stateChanged:(NSNotification *)notification
{
	NSInteger state = [notification.userInfo[@"state"] integerValue];
	if (state == MSGConnectionStateReady) {
		g_ready = YES;
	}
}

- (void)messagesChanged:(NSNotification *)notification
{
	g_messagesChanged = YES;
}

@end

int main(void)
{
	@autoreleasepool {
		const char *relayEnv = getenv("TL_NOSTERM_TEST_RELAY");
		if (relayEnv == NULL || relayEnv[0] == '\0') {
			printf("SKIP: TL_NOSTERM_TEST_RELAY is not set; "
			       "live relay read test not run.\n");
			return 0;
		}
		NSString *relay = [NSString stringWithUTF8String:relayEnv];

		[[MSGLogger sharedLogger] setLevel:MSGLogLevelWarning];

		NSURL *url = [NSURL URLWithString:relay];
		MSGAccount *session = NewNostermAccount(url, @"tl-read-test", nil);

		ReadObserver *observer = [[ReadObserver alloc] init];
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		[center addObserver:observer selector:@selector(stateChanged:)
			name:MSGAccountStateDidChangeNotification object:session];
		[center addObserver:observer selector:@selector(messagesChanged:)
			name:MSGMessagesDidChangeNotification object:session];

		NSLog(@"Connecting to %@...", relay);
		[session connect];

		if (!TLWaitFor(&g_ready, 30.0)) {
			NSLog(@"FAIL: did not reach ready state within 30s");
			[session disconnect];
			[center removeObserver:observer];
			[observer release];
			[session release];
			return 1;
		}
		NSLog(@"Connected and ready.");

		// Channels arrive asynchronously from nostr-groups (kind 39000) after
		// becomeReady fires.  Wait up to 15s for #general to appear.
		MSGChannel *general = nil;
		NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15.0];
		while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
			for (MSGNetwork *n in session.serverState.networks) {
				for (MSGChannel *c in n.channels) {
					if ([[c name] isEqualToString:@"general"]) {
						general = c;
						break;
					}
				}
				if (general != nil) break;
			}
			if (general != nil) break;
			g_messagesChanged = NO;
			[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
				beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
		}
		if (general == nil) {
			NSLog(@"FAIL: #general not found after 15s");
			for (MSGNetwork *n in session.serverState.networks) {
				NSLog(@"  network '%@': %lu channels", [n name],
					(unsigned long)[[n channels] count]);
				for (MSGChannel *c in n.channels) {
					NSLog(@"    ch '%@' id=%ld", [c name], (long)[c identifier]);
				}
			}
			[session disconnect];
			[center removeObserver:observer];
			[observer release];
			[session release];
			return 1;
		}

		// Wait for messages to stream in.
		NSLog(@"Collecting messages in #general (id %ld)...", (long)general.identifier);
		deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
		while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
			g_messagesChanged = NO;
			[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
				beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
		}

		NSArray *messages = [general messages];
		NSUInteger count = [messages count];
		NSLog(@"Total messages in #general: %lu", (unsigned long)count);

		if (count == 0) {
			NSLog(@"FAIL: no messages received");
			[session disconnect];
			[center removeObserver:observer];
			[observer release];
			[session release];
			return 1;
		}

		// Print last 3 with timestamps.
		NSLog(@"--- All %lu messages ---", (unsigned long)count);
		for (NSUInteger i = 0; i < count; i++) {
			MSGMessage *m = [messages objectAtIndex:i];
			NSString *nick = [m sender] ? [[m sender] nick] : @"???";
			NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
			[fmt setDateFormat:@"HH:mm:ss"];
			NSLog(@"  [%lu] [%@] %@: %@", (unsigned long)i,
				[fmt stringFromDate:[m timestamp]], nick, [m text]);
			[fmt release];
		}

		[session disconnect];
		[center removeObserver:observer];
		[observer release];
		[session release];
		return 0;
	}
}
