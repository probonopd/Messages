/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "QuasselProtocol.h"
#import "QuasselAccount.h"

#import "QuasselCoreConnection.h"
#import "QuasselCoreConnectionDelegate.h"
#import "BufferInfo.h"
#import "Message.h"
#import "IrcUser.h"
#import "IrcChannel.h"
#import "SignedId.h"
#import "QuasselSocket.h"

#import "MSGServerState.h"
#import "MSGClientState.h"
#import "MSGNetwork.h"
#import "MSGChannel.h"
#import "MSGMessage.h"
#import "MSGUser.h"
#import "MSGLogger.h"

// The engine's own text for a rejected ClientLogin; it reports it through
// the generic disconnect callback, so this is the only way to tell.
static NSString *const QuasselLoginRejected = @"Wrong username or password";


// Lobbies of networks whose status buffer the core has not reported yet get
// ids above every real buffer id so they cannot collide.
static const NSInteger QuasselSyntheticLobbyBase = (NSInteger)1 << 40;

@interface QuasselProtocol () <QuasselCoreConnectionDelegate>
{
	QuasselCoreConnection *_core;
	// Set when the TCP connection to the core is up; a disconnect before
	// that is a failure to connect, after it a dropped session.
	BOOL _transportUp;
	// Buffers with a "more backlog" request in flight.
	NSMutableSet *_pagingBuffers;
}
@end

@implementation QuasselProtocol

- (instancetype)initWithServerState:(MSGServerState *)serverState
	clientState:(MSGClientState *)clientState
{
	self = [super initWithServerState:serverState clientState:clientState];
	if (self) {
		_pagingBuffers = [[NSMutableSet alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[self close];
	[_pagingBuffers release];
	[super dealloc];
}

- (MSGCapabilities)capabilities
{
	return MSGCapabilityHistoryPaging | MSGCapabilityIRCCommands |
		MSGCapabilityReportsConnectionLoss;
}

- (BOOL)isConnected
{
	return _core != nil && [self isReady];
}

#pragma mark - Connection

- (void)connectToHost:(NSString *)host port:(int)port
	username:(NSString *)username password:(NSString *)password
{
	[self close];
	[_pagingBuffers removeAllObjects];
	// A fresh engine per connection: it resets its maps in -reConnect
	// anyway, and a dropped engine cannot call back into a newer session.
	_core = [[QuasselCoreConnection alloc] init];
	_core.delegate = self;
	[_core connectTo:host port:port userName:username passWord:password];
}

- (void)close
{
	if (_core == nil) {
		return;
	}
	// The engine holds its delegate strongly; clearing it first also keeps
	// the callbacks of the teardown below from reaching us.
	_core.delegate = nil;
	// The engine only disconnects an established socket; one that is still
	// resolving or connecting has to be stopped directly.
	[_core.socket disconnect];
	// Deferred: close is also reached from inside the engine's own
	// callbacks, and ARC does not keep the engine alive while it runs.
	[_core autorelease];
	_core = nil;
	_transportUp = NO;
	[self resetSession];
}

#pragma mark - Ids

- (NSInteger)channelIdForBufferId:(BufferId *)bufferId
{
	return self.channelIdBase + [bufferId intValue];
}

- (BufferId *)bufferIdForChannelId:(NSInteger)channelId
{
	NSInteger raw = channelId - self.channelIdBase;
	if (raw <= 0 || raw >= QuasselSyntheticLobbyBase) {
		return nil;
	}
	return [[[BufferId alloc] initWithInt:(int)raw] autorelease];
}

static NSString *QuasselNetworkUuid(NetworkId *networkId)
{
	return [NSString stringWithFormat:@"quassel-%d", [networkId intValue]];
}

#pragma mark - Message conversion

static MSGMessageType QuasselMessageType(enum MessageType type)
{
	switch (type) {
		case MessageTypePlain: return MSGMessageTypeMessage;
		case MessageTypeNotice: return MSGMessageTypeNotice;
		case MessageTypeAction: return MSGMessageTypeAction;
		case MessageTypeNick: return MSGMessageTypeNick;
		case MessageTypeMode: return MSGMessageTypeMode;
		case MessageTypeJoin:
		case MessageTypeNetsplitJoin: return MSGMessageTypeJoin;
		case MessageTypePart: return MSGMessageTypePart;
		case MessageTypeQuit:
		case MessageTypeKill:
		case MessageTypeNetsplitQuit: return MSGMessageTypeQuit;
		case MessageTypeKick: return MSGMessageTypeKick;
		case MessageTypeError: return MSGMessageTypeError;
		case MessageTypeTopic: return MSGMessageTypeTopic;
		case MessageTypeInvite: return MSGMessageTypeInvite;
		default: return MSGMessageTypeUnhandled;
	}
}

+ (MSGMessage *)messageFromQuasselMessage:(Message *)message
	channelId:(NSInteger)channelId
{
	MSGMessage *result = [[[MSGMessage alloc] init] autorelease];
	result.identifier = [message.messageId intValue];
	result.channelId = channelId;
	result.timestamp = message.messageDate;
	result.type = QuasselMessageType(message.messageType);
	result.text = message.contents ?: @"";
	result.rawText = result.text;
	result.self = (message.messageFlag & MessageFlagSelf) != 0;
	result.highlight = (message.messageFlag & MessageFlagHilight) != 0;

	// Quassel sends the sender as a full nick!user@host prefix.
	NSString *prefix = message.sender ?: @"";
	NSRange bang = [prefix rangeOfString:@"!"];
	MSGUser *sender = [[[MSGUser alloc] init] autorelease];
	sender.nick = bang.location == NSNotFound ? prefix
		: [prefix substringToIndex:bang.location];
	if (bang.location != NSNotFound) {
		result.hostmask = [prefix substringFromIndex:bang.location + 1];
	}
	result.sender = sender;
	if (result.type == MSGMessageTypeNick) {
		result.newNick = message.contents;
	}
	return result;
}

#pragma mark - Mirroring the engine's model

- (MSGChannel *)channelWithId:(NSInteger)identifier name:(NSString *)name
	type:(MSGChannelType)type inNetwork:(MSGNetwork *)network
{
	MSGChannel *channel = [network channelWithIdentifier:identifier];
	if (channel == nil) {
		channel = [[[MSGChannel alloc] init] autorelease];
		channel.identifier = identifier;
		[network addChannel:channel];
	}
	channel.name = name;
	channel.type = type;
	return channel;
}

- (void)syncUsersOfChannel:(MSGChannel *)channel bufferId:(BufferId *)bufferId
{
	NSArray *users = [_core ircUsersForChannelWithBufferId:bufferId];
	[channel.users removeAllObjects];
	for (IrcUser *ircUser in users) {
		if ([ircUser.nick length] == 0) {
			continue;
		}
		MSGUser *user = [[[MSGUser alloc] init] autorelease];
		user.nick = ircUser.nick;
		user.away = ircUser.away ? @"away" : nil;
		[channel addUser:user];
	}
	channel.numUsers = (NSInteger)[channel.users count];
}

// Rebuilds networks and buffers from the engine's maps, keeping existing
// channel objects (and their messages) so a reconnect loses nothing.
- (void)syncModel
{
	NSMutableArray *networks = [NSMutableArray array];
	for (NetworkId *networkId in _core.neworkIdList) {
		NSString *uuid = QuasselNetworkUuid(networkId);
		MSGNetwork *network = [self.serverState networkWithUuid:uuid];
		if (network == nil) {
			network = [[[MSGNetwork alloc] init] autorelease];
			network.uuid = uuid;
		}
		NSString *name = [_core.networkIdNetworkNameMap objectForKey:networkId];
		network.name = [name length] > 0 ? name
			: [NSString stringWithFormat:@"Network %d", [networkId intValue]];
		network.nick = [_core.networkIdMyNickMap objectForKey:networkId];
		network.connected = YES;

		NSMutableSet *keep = [NSMutableSet set];
		BufferInfo *status = [_core.networkIdServerBufferInfoMap objectForKey:networkId];
		NSInteger lobbyId = status
			? [self channelIdForBufferId:status.bufferId]
			: self.channelIdBase + QuasselSyntheticLobbyBase + [networkId intValue];
		MSGChannel *lobby = [self channelWithId:lobbyId name:network.name
			type:MSGChannelTypeLobby inNetwork:network];
		lobby.state = MSGChannelStateJoined;
		[keep addObject:@(lobbyId)];

		NSDictionary *ircChannels = [_core.networkIdChannelMapMap objectForKey:networkId];
		for (BufferId *bufferId in [_core.networkIdBufferIdListMap objectForKey:networkId]) {
			BufferInfo *info = [_core.bufferIdBufferInfoMap objectForKey:bufferId];
			if (info == nil || (info.bufferType != ChannelBuffer &&
				info.bufferType != QueryBuffer)) {
				continue;
			}
			NSInteger identifier = [self channelIdForBufferId:bufferId];
			BOOL isChannel = (info.bufferType == ChannelBuffer);
			MSGChannel *channel = [self channelWithId:identifier name:info.bufferName
				type:isChannel ? MSGChannelTypeChannel : MSGChannelTypeQuery
				inNetwork:network];
			IrcChannel *ircChannel = [ircChannels objectForKey:info.bufferName];
			// Quassel keeps buffers of channels the user left; only joined
			// ones belong in the sidebar.
			channel.state = (!isChannel || ircChannel != nil)
				? MSGChannelStateJoined : MSGChannelStateParted;
			if (ircChannel.topic) {
				channel.topic = ircChannel.topic;
			}
			if (isChannel) {
				[self syncUsersOfChannel:channel bufferId:bufferId];
			}
			[keep addObject:@(identifier)];
		}
		for (MSGChannel *channel in [NSArray arrayWithArray:network.channels]) {
			if (![keep containsObject:@(channel.identifier)]) {
				[network removeChannelWithIdentifier:channel.identifier];
			}
		}
		[networks addObject:network];
	}
	self.serverState.networks = networks;
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGNetworkListDidChangeNotification object:self];
}

- (MSGChannel *)channelForBufferId:(BufferId *)bufferId
{
	return [self.serverState channelWithIdentifier:[self channelIdForBufferId:bufferId]];
}

#pragma mark - Messages

- (void)countUnseen:(MSGMessage *)message inChannel:(MSGChannel *)channel
{
	if ([message isSelf] || ![message countsAsUnseen]) {
		return;
	}
	if (self.clientState.selectedChannelId != channel.identifier) {
		channel.unread += 1;
		if (message.highlight) {
			channel.highlight += 1;
		}
	}
	channel.unseen += 1;
	if (message.highlight) {
		channel.unseenHighlight += 1;
	}
}

- (void)appendMessages:(NSArray *)messages toChannel:(MSGChannel *)channel
	countUnseen:(BOOL)countUnseen
{
	for (Message *message in messages) {
		MSGMessage *converted = [QuasselProtocol messageFromQuasselMessage:message
			channelId:channel.identifier];
		if ([channel messageWithIdentifier:converted.identifier]) {
			continue;
		}
		MSGMessage *last = [channel.messages lastObject];
		if (last != nil && converted.identifier < last.identifier) {
			// Backlog that arrives after live traffic belongs before it.
			[channel prependMessages:@[converted]];
			continue;
		}
		[channel addMessage:converted];
		if (countUnseen) {
			[self countUnseen:converted inChannel:channel];
		}
	}
}

#pragma mark - Channel operations

- (void)sendMessage:(NSString *)text toChannelId:(NSInteger)channelId
{
	BufferId *bufferId = [self bufferIdForChannelId:channelId];
	if (bufferId == nil || ![_core.bufferIdBufferInfoMap objectForKey:bufferId]) {
		return;
	}
	[_core sendMessage:text toBuffer:bufferId];
}

- (void)openChannelId:(NSInteger)channelId
{
	BufferId *bufferId = [self bufferIdForChannelId:channelId];
	MSGChannel *channel = [self.serverState channelWithIdentifier:channelId];
	if (bufferId == nil || channel == nil || _core == nil) {
		return;
	}
	channel.unread = 0;
	channel.highlight = 0;
	// The engine prefetches the first page of every visible buffer; only
	// buffers it skipped need asking.
	if (![_core.backlogRequestedForAlreadyBufferIdSet containsObject:bufferId]) {
		[_core fetchSomeBacklog:bufferId];
	}
	// Other Quassel clients see the buffer as read, too. Only an advance
	// is sent: the engine reports every change straight back, and the
	// resulting refresh opens the channel again.
	MSGMessage *last = [channel.messages lastObject];
	if (last != nil && [[_core lastSeenMsgForBuffer:bufferId] intValue] < last.identifier) {
		[_core setLastSeenMsg:[[[MsgId alloc] initWithInt:(int)last.identifier]
			autorelease] forBuffer:bufferId];
	}
}

- (void)requestNamesForChannelId:(NSInteger)channelId
{
	BufferId *bufferId = [self bufferIdForChannelId:channelId];
	MSGChannel *channel = [self.serverState channelWithIdentifier:channelId];
	if (bufferId == nil || channel == nil || ![channel isChannel]) {
		return;
	}
	// The engine keeps the member lists current; this only copies them.
	[self syncUsersOfChannel:channel bufferId:bufferId];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGUserListDidChangeNotification object:self
		userInfo:@{@"channelId": @(channelId)}];
}

- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
	query:(NSString *)query
{
	BufferId *bufferId = [self bufferIdForChannelId:channelId];
	if (bufferId == nil || _core == nil || [_pagingBuffers containsObject:bufferId]) {
		return;
	}
	[_pagingBuffers addObject:bufferId];
	[_core fetchMoreBacklog:bufferId];
}

- (void)joinChannelNamed:(NSString *)name lobbyId:(NSInteger)lobbyId
{
	[self sendCommand:[NSString stringWithFormat:@"/join %@", name]
		toChannelId:lobbyId];
}

#pragma mark - QuasselCoreConnectionDelegate

- (void)quasselSocketFailedConnect:(NSString *)msg
{
	[_account handleTransportFailure:[NSError errorWithDomain:@"QuasselErrorDomain"
		code:1 userInfo:@{NSLocalizedDescriptionKey: msg ?: @"Cannot connect"}]];
}

- (void)quasselConnected
{
	_transportUp = YES;
	[_account handleTransportConnected];
	if ([self.delegate respondsToSelector:@selector(protocol:didReceiveAuthStart:)]) {
		[self.delegate protocol:self didReceiveAuthStart:@(0)];
	}
}

- (void)quasselEncrypted
{
}

- (void)quasselAuthenticated
{
	[self setAuthenticated:YES];
	if ([self.delegate respondsToSelector:@selector(protocolDidAuthenticate:)]) {
		[self.delegate protocolDidAuthenticate:self];
	}
}

- (void)quasselBufferListReceived
{
	[self syncModel];
}

- (void)quasselNetworkInitReceived:(NSString *)networkName
{
	[self syncModel];
}

- (void)quasselAllNetworkInitReceived
{
	[self syncModel];
}

- (void)quasselFullyConnected
{
	[self syncModel];
	[self setReady:YES];
	if ([self.delegate respondsToSelector:@selector(protocolDidBecomeReady:)]) {
		[self.delegate protocolDidBecomeReady:self];
	}
}

- (void)quasselBufferListUpdated
{
	[self syncModel];
}

- (void)quasselNetworkNameUpdated:(NetworkId *)networkId
{
	[self syncModel];
}

- (void)quasselSwitchToBuffer:(BufferId *)bufferId
{
}

- (void)quasselLastSeenMsgUpdated:(MsgId *)messageId forBuffer:(BufferId *)bufferId
{
	// Read on another client: nothing new is waiting here anymore.
	MSGChannel *channel = [self channelForBufferId:bufferId];
	MSGMessage *last = [channel.messages lastObject];
	if (channel != nil && last != nil && [messageId intValue] >= last.identifier &&
		(channel.unread > 0 || channel.highlight > 0)) {
		channel.unread = 0;
		channel.highlight = 0;
		[[NSNotificationCenter defaultCenter]
			postNotificationName:MSGChannelDidChangeNotification object:self
			userInfo:@{@"channelId": @(channel.identifier)}];
	}
}

- (void)quasselSocketDidDisconnect:(NSString *)msg
{
	BOOL wasUp = _transportUp;
	BOOL rejected = ![self isAuthenticated] && [msg isEqualToString:QuasselLoginRejected];
	[self close];
	if (rejected) {
		NSError *error = [NSError errorWithDomain:@"QuasselErrorDomain" code:2
			userInfo:@{NSLocalizedDescriptionKey: msg}];
		if ([self.delegate respondsToSelector:@selector(protocol:authenticationFailedWithError:)]) {
			[self.delegate protocol:self authenticationFailedWithError:error];
		}
		return;
	}
	for (MSGNetwork *network in self.serverState.networks) {
		network.connected = NO;
	}
	if (wasUp) {
		[_account handleTransportDisconnected];
	} else {
		[_account handleTransportFailure:[NSError errorWithDomain:@"QuasselErrorDomain"
			code:3 userInfo:@{NSLocalizedDescriptionKey: msg ?: @"Cannot connect"}]];
	}
}

- (void)quasselBacklogReceivedForBuffer:(BufferId *)bufferId
	count:(NSUInteger)count limit:(int)limit
{
	[_pagingBuffers removeObject:bufferId];
	MSGChannel *channel = [self channelForBufferId:bufferId];
	if (channel == nil) {
		return;
	}
	// Offer more history while the core keeps returning full pages.
	BOOL exhausted = (limit <= 0 || count < (NSUInteger)limit);
	channel.totalMessages = (NSInteger)[channel.messages count] + (exhausted ? 0 : 1);
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGHistoryDidChangeNotification object:self
		userInfo:@{@"channelId": @(channel.identifier)}];
}

- (void)quasselMessageReceived:(Message *)msg received:(enum ReceiveStyle)style
	onIndex:(int)i
{
	MSGChannel *channel = [self channelForBufferId:msg.bufferInfo.bufferId];
	if (channel == nil) {
		// A buffer the model does not show yet (e.g. a new query).
		[self syncModel];
		channel = [self channelForBufferId:msg.bufferInfo.bufferId];
		if (channel == nil) {
			return;
		}
	}
	BOOL live = (style == ReceiveStyleAppended);
	[self appendMessages:@[msg] toChannel:channel countUnseen:live];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGMessagesDidChangeNotification object:self
		userInfo:@{@"channelId": @(channel.identifier)}];
}

- (void)quasselMessagesReceived:(NSArray *)messages received:(enum ReceiveStyle)style
{
	if ([messages count] == 0) {
		return;
	}
	BufferId *bufferId = [[[messages firstObject] bufferInfo] bufferId];
	MSGChannel *channel = [self channelForBufferId:bufferId];
	if (channel == nil) {
		return;
	}
	if (style == ReceiveStylePrepended) {
		NSMutableArray *older = [NSMutableArray array];
		for (Message *message in messages) {
			MSGMessage *converted = [QuasselProtocol messageFromQuasselMessage:message
				channelId:channel.identifier];
			if (![channel messageWithIdentifier:converted.identifier]) {
				[older addObject:converted];
			}
		}
		[older sortUsingComparator:^NSComparisonResult(MSGMessage *a, MSGMessage *b) {
			return a.identifier < b.identifier ? NSOrderedAscending
				: (a.identifier > b.identifier ? NSOrderedDescending : NSOrderedSame);
		}];
		[channel prependMessages:older];
	} else {
		[self appendMessages:messages toChannel:channel countUnseen:NO];
	}

	NSString *name = style == ReceiveStylePrepended
		? MSGHistoryDidChangeNotification : MSGMessagesDidChangeNotification;
	[[NSNotificationCenter defaultCenter] postNotificationName:name object:self
		userInfo:@{@"channelId": @(channel.identifier)}];
}

@end
