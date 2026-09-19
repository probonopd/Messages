/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLoungeProtocol.h"
#import "MSGServerState.h"
#import "MSGClientState.h"
#import "MSGNetwork.h"
#import "MSGChannel.h"
#import "TLSocketIOClient.h"
#import "MSGEventDispatcher.h"

@implementation TLoungeProtocol

- (instancetype)initWithSocketClient:(TLSocketIOClient *)client
                         serverState:(MSGServerState *)serverState
                         clientState:(MSGClientState *)clientState
{
	// Set before super's initializer, which registers the event handlers
	// that may capture the client.
	_socketClient = client;
	return [super initWithServerState:serverState clientState:clientState];
}

- (MSGCapabilities)capabilities
{
	return MSGCapabilityServerSearch | MSGCapabilityHistoryPaging |
		MSGCapabilityClearHistory | MSGCapabilityMute | MSGCapabilityIRCCommands |
		MSGCapabilityServerManagedNetworks | MSGCapabilityReportsConnectionLoss;
}

- (BOOL)isConnected
{
	return [_socketClient isConnected];
}

- (void)sendMessage:(NSString *)text toChannelId:(NSInteger)channelId
{
	[self.socketClient emitEvent:@"input"
		withArguments:@[@{@"target": @(channelId), @"text": text}]];
}

- (void)sendCommand:(NSString *)command toChannelId:(NSInteger)channelId
{
	[self sendMessage:command toChannelId:channelId];
}

- (void)openChannelId:(NSInteger)channelId
{
	[self.socketClient emitEvent:@"open" withArguments:@[@(channelId)]];
	// The bouncer does not always push a channel's backlog in response to
	// `open`; request the most recent page explicitly. Omitting `lastId` makes
	// the server return the tail (newest page) rather than older-than-0.
	NSMutableDictionary *payload = [NSMutableDictionary dictionary];
	[payload setObject:@(channelId) forKey:@"target"];
	[payload setObject:@NO forKey:@"condensed"];
	[self.socketClient emitEvent:@"more" withArguments:@[payload]];
}

- (void)requestNamesForChannelId:(NSInteger)channelId
{
	[self.socketClient emitEvent:@"names" withArguments:@[@{@"target": @(channelId)}]];
}

- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
	query:(NSString *)query
{
	NSMutableDictionary *payload = [NSMutableDictionary dictionary];
	[payload setObject:@(channelId) forKey:@"target"];
	[payload setObject:@(lastId) forKey:@"lastId"];
	[payload setObject:@NO forKey:@"condensed"];
	if ([query length] > 0) {
		[payload setObject:query forKey:@"query"];
	}
	[self.socketClient emitEvent:@"more" withArguments:@[payload]];
}

// The Lounge bouncer searches its stored backlog through a dedicated `search`
// event (distinct from `more`), keyed by network uuid and (lowercased) channel
// name rather than the channel id the client uses elsewhere.
- (void)searchMessagesForChannelId:(NSInteger)channelId term:(NSString *)term
	offset:(NSInteger)offset
{
	MSGChannel *channel = [self.serverState channelWithIdentifier:channelId];
	MSGNetwork *network = [self.serverState networkContainingChannel:channelId];
	if (!channel || !network || [term length] == 0) {
		return;
	}
	NSMutableDictionary *payload = [NSMutableDictionary dictionary];
	[payload setObject:term forKey:@"searchTerm"];
	[payload setObject:[network.uuid description] forKey:@"networkUuid"];
	[payload setObject:[[channel.name description] lowercaseString]
		forKey:@"channelName"];
	[payload setObject:@(offset) forKey:@"offset"];
	[self.socketClient emitEvent:@"search" withArguments:@[payload]];
}

- (void)clearHistoryForChannelId:(NSInteger)channelId
{
	[self.socketClient emitEvent:@"history:clear" withArguments:@[@{@"target": @(channelId)}]];
}

- (void)setMuted:(BOOL)muted forChannelId:(NSInteger)channelId
{
	[self.socketClient emitEvent:@"mute:change"
		withArguments:@[@{@"target": @(channelId), @"setMutedTo": @(muted)}]];
}

- (void)joinChannelNamed:(NSString *)name lobbyId:(NSInteger)lobbyId
{
	NSString *command = [NSString stringWithFormat:@"/join %@", name];
	[self sendCommand:command toChannelId:lobbyId];
}

- (void)joinExistingChannelNamed:(NSString *)name lobbyId:(NSInteger)lobbyId
{
	[self joinChannelNamed:name lobbyId:lobbyId];
}

// The bouncer owns the network configuration; quitting removes the network
// from it.
- (void)removeNetwork:(MSGNetwork *)network
{
	MSGChannel *lobby = [network lobby];
	if (lobby) {
		[self sendCommand:@"/quit" toChannelId:lobby.identifier];
	}
}

@end