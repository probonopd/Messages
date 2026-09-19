/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "QuasselAccount.h"
#import "QuasselProtocol.h"

static const int QuasselDefaultPort = 4242;

@implementation QuasselAccount

- (MSGProtocol *)newProtocolWithTransportClient:(id<MSGTransportClient>)client
{
	QuasselProtocol *protocol = [[QuasselProtocol alloc]
		initWithServerState:self.serverState clientState:self.clientState];
	protocol.account = self;
	return protocol;
}

- (void)dealloc
{
	((QuasselProtocol *)self.protocol).account = nil;
	[super dealloc];
}

// The engine owns its socket, so the account drives the engine instead of
// an MSGTransportClient.
- (void)openConnection
{
	NSDictionary *settings = self.settings;
	int port = [settings[@"port"] intValue];
	[(QuasselProtocol *)self.protocol connectToHost:settings[@"host"]
		port:port > 0 ? port : QuasselDefaultPort
		username:settings[@"username"] password:settings[@"password"]];
}

- (void)closeConnection
{
	[(QuasselProtocol *)self.protocol close];
}

- (NSString *)displayName
{
	NSString *name = self.settings[@"name"];
	if ([name length] > 0) {
		return name;
	}
	return [NSString stringWithFormat:@"%@@%@", self.settings[@"username"] ?: @"",
		self.settings[@"host"] ?: @""];
}

@end
