/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "NTNostermAccount.h"
#import "NTNostermProtocol.h"
#import "NTNostrSocketClient.h"

@implementation NTNostermAccount

- (id<MSGTransportClient>)newTransportClient
{
	return [[NTNostrSocketClient alloc] init];
}

- (MSGProtocol *)newProtocolWithTransportClient:(id<MSGTransportClient>)client
{
	return [[NTNostermProtocol alloc] initWithSocketClient:(NTNostrSocketClient *)client
		serverState:self.serverState clientState:self.clientState];
}

- (void)configureProtocolCredentials
{
	[self.protocol setUsername:self.settings[@"username"]
		password:self.settings[@"privateKey"]];
}

- (NSString *)displayName
{
	NSString *name = self.settings[@"name"];
	return [name length] > 0 ? name : ([[self serverURL] host] ?: @"");
}

@end
