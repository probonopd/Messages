/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* t_quassel.m - the Quassel backend against Fixtures/quassel_mockcore.py, a
 * legacy-protocol core on localhost. Needs python3; no other network. */

#import <Foundation/Foundation.h>
#import "Testing.h"

#import "MSGAccount.h"
#import "MSGAccountManager.h"
#import "MSGServerState.h"
#import "MSGClientState.h"
#import "MSGNetwork.h"
#import "MSGChannel.h"
#import "MSGMessage.h"
#import "MSGUser.h"
#import "QuasselAccount.h"
#import "QuasselProtocol.h"
#import "Message.h"
#import "SignedId.h"

#include <signal.h>

// Runs the run loop until `condition` holds or `seconds` pass.
static BOOL RunUntil(NSTimeInterval seconds, BOOL (^condition)(void))
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
	while (!condition() && [deadline timeIntervalSinceNow] > 0) {
		NSAutoreleasePool *pool = [NSAutoreleasePool new];
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
			beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
		[pool release];
	}
	return condition();
}

static NSTask *StartMockCore(int port)
{
	NSTask *task = [[NSTask alloc] init];
	[task setLaunchPath:@"/usr/bin/env"];
	[task setArguments:@[@"python3", @"Fixtures/quassel_mockcore.py",
		[NSString stringWithFormat:@"%d", port]]];
	[task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
	[task launch];
	// Wait for the listening socket instead of a fixed delay.
	RunUntil(5.0, ^BOOL {
		NSTask *probe = [[[NSTask alloc] init] autorelease];
		[probe setLaunchPath:@"/usr/bin/env"];
		[probe setArguments:@[@"python3", @"-c", [NSString stringWithFormat:
			@"import socket;socket.create_connection(('127.0.0.1',%d),1)", port]]];
		[probe setStandardError:[NSFileHandle fileHandleWithNullDevice]];
		[probe launch];
		[probe waitUntilExit];
		return [probe terminationStatus] == 0;
	});
	return task;
}

static QuasselAccount *NewAccount(NSString *host, int port, NSString *password)
{
	QuasselAccount *account = [[QuasselAccount alloc] initWithIdentifier:@"test"
		settings:@{@"host": host, @"port": @(port), @"username": @"tester",
			@"password": password}];
	// A slot other than 0 proves buffer ids are shifted everywhere.
	account.channelIdBase = 3 * MSGAccountIdSlotSize;
	return account;
}

static MSGChannel *ChannelNamed(MSGAccount *account, NSString *name)
{
	for (MSGNetwork *network in account.serverState.networks) {
		MSGChannel *channel = [network channelWithName:name];
		if (channel) {
			return channel;
		}
	}
	return nil;
}

int main(void)
{
	NSAutoreleasePool *arp = [NSAutoreleasePool new];
	signal(SIGPIPE, SIG_IGN);

	START_SET("message conversion")
	Message *m = [[[Message alloc] init] autorelease];
	m.messageId = [[[MsgId alloc] initWithInt:42] autorelease];
	m.messageDate = [NSDate dateWithTimeIntervalSince1970:1700000000];
	m.messageType = MessageTypeAction;
	m.messageFlag = MessageFlagSelf | MessageFlagHilight;
	m.sender = @"alice!ali@example.org";
	m.contents = @"waves";
	MSGMessage *c = [QuasselProtocol messageFromQuasselMessage:m channelId:7];
	PASS(c.identifier == 42 && c.channelId == 7, "ids are carried over");
	PASS(c.type == MSGMessageTypeAction, "action type maps");
	PASS_EQUAL(c.sender.nick, @"alice", "nick is cut from the prefix");
	PASS_EQUAL(c.hostmask, @"ali@example.org", "hostmask is the rest");
	PASS([c isSelf] && c.highlight, "self and highlight flags map");
	m.messageType = MessageTypeNick;
	m.contents = @"alice2";
	c = [QuasselProtocol messageFromQuasselMessage:m channelId:7];
	PASS(c.type == MSGMessageTypeNick && [c.newNick isEqual:@"alice2"],
		"nick change carries the new nick");
	m.messageType = MessageTypeDayChange;
	c = [QuasselProtocol messageFromQuasselMessage:m channelId:7];
	PASS(c.type == MSGMessageTypeUnhandled, "unknown types are marked unhandled");
	END_SET("message conversion")

	int port = 42000 + getpid() % 1000;
	NSTask *core = StartMockCore(port);

	START_SET("session")
	QuasselAccount *account = NewAccount(@"127.0.0.1", port, @"secret");
	[account setEstablished:NO];
	NSInteger base = account.channelIdBase;
	[account connect];
	PASS(RunUntil(10.0, ^BOOL { return account.state == MSGConnectionStateReady; }),
		"account becomes ready");
	NSArray *networks = account.serverState.networks;
	PASS([networks count] == 2, "both networks are mirrored");
	MSGNetwork *testNet = [account.serverState networkWithUuid:@"quassel-1"];
	PASS_EQUAL(testNet.name, @"TestNet", "network name");
	PASS_EQUAL(testNet.nick, @"gnustep-tester", "own nick");
	PASS([testNet lobby].identifier == base + 10, "status buffer is the lobby, in the slot");
	MSGChannel *gnustep = ChannelNamed(account, @"#gnustep");
	PASS(gnustep.identifier == base + 11 && [gnustep isChannel], "channel buffer");
	PASS(gnustep.state == MSGChannelStateJoined, "joined channel is visible");
	PASS([gnustep.users count] == 5, "members are mirrored");
	PASS([ChannelNamed(account, @"alice") isQuery], "query buffer");

	MSGChannel *quassel = ChannelNamed(account, @"#quassel");
	PASS(RunUntil(5.0, ^BOOL { return [quassel.messages count] == 1; }),
		"live message arrives");
	PASS(quassel.unread == 1 && quassel.unseen == 1,
		"live message in another channel counts as unread");

	[account.protocol openChannelId:gnustep.identifier];
	PASS(RunUntil(5.0, ^BOOL { return [gnustep.messages count] == 70; }),
		"first backlog page arrives");
	MSGMessage *first = [gnustep.messages firstObject];
	MSGMessage *last = [gnustep.messages lastObject];
	PASS(first.identifier == 31 && last.identifier == 100,
		"backlog is ordered oldest first");
	PASS(gnustep.totalMessages > (NSInteger)[gnustep.messages count],
		"more history is offered");

	// The window reacts to channel changes by opening the channel again;
	// opening must not keep producing changes.
	__block NSUInteger changes = 0;
	id observer = [[NSNotificationCenter defaultCenter]
		addObserverForName:MSGChannelDidChangeNotification object:nil queue:nil
		usingBlock:^(NSNotification *note) {
			changes++;
			[account.protocol openChannelId:gnustep.identifier];
		}];
	[account.protocol openChannelId:gnustep.identifier];
	[account.protocol openChannelId:gnustep.identifier];
	RunUntil(1.0, ^BOOL { return changes > 5; });
	PASS(changes <= 1, "opening a read channel does not loop");
	[[NSNotificationCenter defaultCenter] removeObserver:observer];

	[account.protocol loadMoreHistoryForChannelId:gnustep.identifier lastId:31];
	PASS(RunUntil(5.0, ^BOOL { return [gnustep.messages count] == 100; }),
		"older page is prepended");
	PASS([[gnustep.messages firstObject] identifier] == 1, "oldest message first");
	PASS(gnustep.totalMessages > (NSInteger)[gnustep.messages count],
		"a full page still offers more history");

	[account.protocol loadMoreHistoryForChannelId:gnustep.identifier lastId:1];
	PASS(RunUntil(5.0, ^BOOL {
		return gnustep.totalMessages == (NSInteger)[gnustep.messages count];
	}), "an empty page ends the history");

	[account sendMessage:@"hi there" toChannelId:gnustep.identifier];
	PASS(RunUntil(5.0, ^BOOL {
		return [[[gnustep.messages lastObject] text] isEqual:@"hi there"];
	}), "sent message comes back from the core");
	PASS([[gnustep.messages lastObject] isSelf], "echo is marked as own");

	[account disconnect];
	PASS(account.state == MSGConnectionStateDisconnected, "disconnects");
	[account release];
	END_SET("session")

	START_SET("failures")
	QuasselAccount *rejected = NewAccount(@"127.0.0.1", port, @"wrong");
	[rejected connect];
	PASS(RunUntil(10.0, ^BOOL {
		return rejected.state == MSGConnectionStateAuthenticationFailed;
	}), "wrong password is an authentication failure");
	[rejected release];

	QuasselAccount *closed = NewAccount(@"127.0.0.1", 1, @"secret");
	[closed connect];
	PASS(RunUntil(10.0, ^BOOL {
		return closed.state == MSGConnectionStateConnectionError;
	}), "refused connection is a connection error");
	[closed release];

	QuasselAccount *unknown = NewAccount(@"nonexistent.invalid", port, @"secret");
	[unknown connect];
	PASS(unknown.state == MSGConnectionStateConnecting,
		"name resolution does not block the caller");
	PASS(RunUntil(20.0, ^BOOL {
		return unknown.state == MSGConnectionStateConnectionError;
	}), "unresolvable host is a connection error");
	[unknown release];
	END_SET("failures")

	[core terminate];
	[core waitUntilExit];
	[core release];
	[arp release];
	return 0;
}
