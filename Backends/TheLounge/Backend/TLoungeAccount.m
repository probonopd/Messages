/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLoungeAccount.h"
#import "TLoungeProtocol_4_5.h"
#import "TLSocketIOClient.h"
#import "MSGServerState.h"

@implementation TLoungeAccount

// The bouncer's channel ids are used verbatim on the wire and in every
// event, so they cannot be shifted into a slot.
+ (BOOL)usesServerChannelIds
{
	return YES;
}

// The password is traded for a session token at the first login; only the
// token is kept.
+ (NSSet *)transientSettingKeys
{
	return [NSSet setWithObject:@"password"];
}

- (id<MSGTransportClient>)newTransportClient
{
	return [[TLSocketIOClient alloc] init];
}

- (MSGProtocol *)newProtocolWithTransportClient:(id<MSGTransportClient>)client
{
	return [[TLoungeProtocol_4_5 alloc] initWithSocketClient:(TLSocketIOClient *)client
		serverState:self.serverState clientState:self.clientState];
}

- (void)configureProtocolCredentials
{
	NSDictionary *settings = self.settings;
	// A typed password is authoritative: the server can invalidate stored
	// tokens at any time, and preferring the token would then reject even
	// a correct password.
	if ([settings[@"password"] length] > 0) {
		[self.protocol setUsername:settings[@"username"] password:settings[@"password"]];
	} else {
		[self.protocol setUsername:settings[@"username"] token:settings[@"token"]];
	}
}

- (void)protocolDidBecomeReady:(MSGProtocol *)protocol
{
	NSString *token = self.serverState.metadata[@"token"];
	if ([token length] > 0 && ![token isEqualToString:self.settings[@"token"]]) {
		[self updateSettings:@{@"token": token, @"password": [NSNull null]}];
	}
	[super protocolDidBecomeReady:protocol];
}

- (void)protocol:(MSGProtocol *)protocol authenticationFailedWithError:(NSError *)error
{
	// A rejected token cannot recover on its own; drop it so the next
	// attempt asks for the password.
	if ([self.settings[@"password"] length] == 0 && self.settings[@"token"] != nil) {
		[self updateSettings:@{@"token": [NSNull null]}];
	}
	[super protocol:protocol authenticationFailedWithError:error];
}

@end
