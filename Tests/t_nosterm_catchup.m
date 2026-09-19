/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

// Live Nosterm offline-catch-up test against a real relay.
//
// Scenario: identity A connects and posts a message, then goes offline. A second
// identity B (a different key) posts a message to the same group while A is
// offline. When A reconnects, the relay must replay the message B posted (the
// "offline catch-up" requirement), and no message may appear twice even though
// it can arrive via both a global and a per-channel subscription (id dedup).
//
// Gated behind TL_NOSTERM_TEST_KEY exactly like t_nosterm_live: the key is read
// from the environment only, never logged or embedded, and the test SKIPs (exit
// 0) when the variable is unset.
//
//   export TL_NOSTERM_TEST_KEY=<64-hex-char seckey>
//   ./obj/t_nosterm_catchup

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
static BOOL g_failed = NO;
static NSString *g_failMessage = nil;

static void TLSetFailMessage(NSString *message)
{
	[g_failMessage release];
	g_failMessage = [message retain];
}

static NSString *TLRandomKey(void)
{
	unsigned char bytes[32];
	for (int i = 0; i < 32; i++) {
		bytes[i] = (unsigned char)(rand() & 0xff);
	}
	NSMutableString *s = [NSMutableString string];
	for (int i = 0; i < 32; i++) {
		[s appendFormat:@"%02x", bytes[i]];
	}
	return s;
}

static BOOL TLWaitFor(BOOL *flag, NSTimeInterval timeout)
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while (!*flag && [[NSDate date] compare:deadline] == NSOrderedAscending) {
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
			beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
	}
	return *flag;
}

@interface LiveObserver : NSObject
@end

@implementation LiveObserver

- (void)stateChanged:(NSNotification *)notification
{
	NSInteger state = [notification.userInfo[@"state"] integerValue];
	if (state == MSGConnectionStateReady) {
		g_ready = YES;
	}
	if (state == MSGConnectionStateConnectionError ||
		state == MSGConnectionStateAuthenticationFailed ||
		state == MSGConnectionStateProtocolError) {
		g_failed = YES;
		TLSetFailMessage([NSString stringWithFormat:
			@"connection state %ld", (long)state]);
	}
}

- (void)didFail:(NSNotification *)notification
{
	g_failed = YES;
	NSError *error = notification.userInfo[@"error"];
	TLSetFailMessage([error localizedDescription]);
}

@end

static MSGChannel *TLFindChannelNamed(MSGAccount *session, NSString *name)
{
	for (MSGNetwork *network in session.serverState.networks) {
		for (MSGChannel *channel in network.channels) {
			if ([[channel name] isEqualToString:name]) {
				return channel;
			}
		}
	}
	return nil;
}

static NSInteger TLLobbyIdFor(MSGAccount *session, NSString *host)
{
	for (MSGNetwork *n in session.serverState.networks) {
		if ([[n name] isEqualToString:host] && [n lobby] != nil) {
			return [[n lobby] identifier];
		}
	}
	return 0;
}

static MSGAccount *TLConnect(NSString *relay, NSString *key,
	LiveObserver *obs, NSNotificationCenter **outCenter)
{
	g_ready = NO;
	g_failed = NO;
	NSURL *url = [NSURL URLWithString:relay];
	MSGAccount *s = NewNostermAccount(url, @"tl-catchup-test", key);
	NSNotificationCenter *c = [NSNotificationCenter defaultCenter];
	[c addObserver:obs selector:@selector(stateChanged:)
		name:MSGAccountStateDidChangeNotification object:s];
	[c addObserver:obs selector:@selector(didFail:)
		name:MSGAccountErrorNotification object:s];
	[s connect];
	if (!TLWaitFor(&g_ready, 40.0)) {
		[c removeObserver:obs];
		[s release];
		return nil;
	}
	*outCenter = c;
	return s;
}

static void TLDisconnect(MSGAccount *s, LiveObserver *obs,
	NSNotificationCenter *c)
{
	[c removeObserver:obs];
	[s disconnect];
	[s release];
}

static MSGChannel *TLJoinAndWait(MSGAccount *s, NSString *groupName,
	NSString *host)
{
	[s.protocol joinChannelNamed:groupName lobbyId:TLLobbyIdFor(s, host)];
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:20.0];
	MSGChannel *channel = nil;
	while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
		channel = TLFindChannelNamed(s, groupName);
		if (channel != nil) {
			break;
		}
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
			beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
	}
	return channel;
}

static BOOL TLSendAndWaitEcho(MSGAccount *s, MSGChannel *channel,
	NSString *text)
{
	[s sendMessage:text toChannelId:channel.identifier];
	BOOL echoed = NO;
	BOOL resent = NO;
	NSDate *start = [NSDate date];
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:25.0];
	while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
		for (MSGMessage *m in channel.messages) {
			if ([[m text] isEqualToString:text]) {
				echoed = YES;
				break;
			}
		}
		if (echoed) {
			break;
		}
		// Allow the relay a moment to apply the kind 9021 join before posting.
		if (!resent && [start timeIntervalSinceNow] < -2.0) {
			[s sendMessage:text toChannelId:channel.identifier];
			resent = YES;
		}
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
			beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
	}
	return echoed;
}

static BOOL TLWaitForText(MSGChannel *channel, NSString *text,
	NSTimeInterval timeout)
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
		for (MSGMessage *m in channel.messages) {
			if ([[m text] isEqualToString:text]) {
				return YES;
			}
		}
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
			beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.25]];
	}
	return NO;
}

static BOOL TLNoDuplicateTexts(MSGChannel *channel)
{
	NSMutableSet *seen = [NSMutableSet set];
	for (MSGMessage *m in channel.messages) {
		NSString *t = [m text];
		if (t == nil) {
			continue;
		}
		if ([seen containsObject:t]) {
			return NO;
		}
		[seen addObject:t];
	}
	return YES;
}

int main(void)
{
	@autoreleasepool {
		const char *keyEnv = getenv("TL_NOSTERM_TEST_KEY");
		if (keyEnv == NULL || keyEnv[0] == '\0') {
			printf("SKIP: TL_NOSTERM_TEST_KEY is not set; "
			       "offline catch-up test not run.\n");
			return 0;
		}
		NSString *key = [NSString stringWithUTF8String:keyEnv];
		if ([key length] != 64) {
			printf("SKIP: TL_NOSTERM_TEST_KEY must be 64 hex chars; "
			       "offline catch-up test not run.\n");
			return 0;
		}

		NSString *relay = @"wss://chat.nosterm.com/relay";
		const char *relayEnv = getenv("TL_NOSTERM_TEST_RELAY");
		if (relayEnv != NULL && relayEnv[0] != '\0') {
			relay = [NSString stringWithUTF8String:relayEnv];
		}
		NSString *host = [[NSURL URLWithString:relay] host];

		[[MSGLogger sharedLogger] setLevel:MSGLogLevelWarning];
		if (getenv("TL_NOSTERM_TEST_DEBUG") != NULL) {
			[[MSGLogger sharedLogger] setLevel:MSGLogLevelDebug];
		}

		// One group shared by both identities; unique per run.
		NSString *groupName = [NSString stringWithFormat:@"catchup-%08x",
			(unsigned)arc4random()];
		NSString *textA = [NSString stringWithFormat:@"A-%08x",
			(unsigned)arc4random()];
		NSString *textB = [NSString stringWithFormat:@"B-%08x",
			(unsigned)arc4random()];

		LiveObserver *observer = [[LiveObserver alloc] init];
		NSNotificationCenter *center = nil;

		// --- Phase A: identity A connects, creates the group, posts textA ---
		MSGAccount *sA = TLConnect(relay, key, observer, &center);
		PASS(sA != nil, "phase A connected to relay");
		MSGChannel *chA = nil;
		if (sA != nil) {
			chA = TLJoinAndWait(sA, groupName, host);
			PASS(chA != nil, "phase A group visible");
			if (chA != nil) {
				PASS(TLSendAndWaitEcho(sA, chA, textA),
					"phase A message echoed by relay");
			}
			TLDisconnect(sA, observer, center);
			sA = nil;
		}

		// --- Phase B: identity B posts textB while A is offline ---
		NSString *keyB = TLRandomKey();
		MSGAccount *sB = TLConnect(relay, keyB, observer, &center);
		PASS(sB != nil, "phase B (second identity) connected");
		MSGChannel *chB = nil;
		if (sB != nil) {
			chB = TLJoinAndWait(sB, groupName, host);
			PASS(chB != nil, "phase B group visible");
			if (chB != nil) {
				// When B's own message echoes, it is on the relay and A was
				// offline, so this is the message A must later catch up on.
				PASS(TLSendAndWaitEcho(sB, chB, textB),
					"phase B message stored on relay while A offline");
			}
			TLDisconnect(sB, observer, center);
			sB = nil;
		}

		// --- Phase C: identity A reconnects and must catch up on textB ---
		MSGAccount *sC = TLConnect(relay, key, observer, &center);
		PASS(sC != nil, "phase C reconnected as identity A");
		MSGChannel *chC = nil;
		if (sC != nil) {
			chC = TLJoinAndWait(sC, groupName, host);
			PASS(chC != nil, "phase C group visible");
			if (chC != nil) {
				PASS(TLWaitForText(chC, textB, 30.0),
					"offline message from B replayed on reconnect (catch-up)");
				PASS(TLNoDuplicateTexts(chC),
					"no duplicate messages (id dedup across subscriptions)");
			}
			// Test hygiene: delete the shared group we published so it does
			// not accumulate on the shared relay and clutter the real client.
			if (chC != nil) {
				[sC.protocol deleteGroupChannelId:chC.identifier];
				// Let the delete events flush before tearing down the socket.
				[NSThread sleepForTimeInterval:2.0];
			}
			TLDisconnect(sC, observer, center);
			sC = nil;
		}

		[observer release];
		[g_failMessage release];
		g_failMessage = nil;
		return 0;
	}
}
