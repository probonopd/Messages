/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLoungeProtocol_4_5.h"
#import "MSGServerState.h"
#import "MSGClientState.h"
#import "MSGNetwork.h"
#import "MSGChannel.h"
#import "MSGMessage.h"
#import "MSGUser.h"
#import "TLSocketIOClient.h"
#import "MSGEventDispatcher.h"
#import "MSGLogger.h"

// Forward declaration; defined near reconcileChannel below.
static void TLSeedUnseenFromMessages(MSGChannel *channel);

// Search-result messages get a private, negative id space so they never
// collide with real (positive) bouncer message ids when rendered alongside
// downloaded history.
static const NSInteger TLLoungeSearchResultIdBase = -100000000;

@implementation TLoungeProtocol_4_5

- (void)registerEventHandlers
{
	__block TLoungeProtocol_4_5 *weakSelf = self;

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		NSNumber *serverHash = [args count] > 0 ? args[0] : nil;
		if ([self.delegate respondsToSelector:@selector(protocol:didReceiveAuthStart:)]) {
			[self.delegate protocol:self didReceiveAuthStart:serverHash];
		}
		[self performAuthentication];
	} forEvent:@"auth:start"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self setAuthenticated:YES];
		if ([self.delegate respondsToSelector:@selector(protocolDidAuthenticate:)]) {
			[self.delegate protocolDidAuthenticate:self];
		}
	} forEvent:@"auth:success"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self setAuthenticated:NO];
		NSError *error = [NSError errorWithDomain:@"TLLoungeAuthErrorDomain"
			code:100
			userInfo:@{NSLocalizedDescriptionKey: @"Authentication failed"}];
		if ([self.delegate respondsToSelector:@selector(protocol:authenticationFailedWithError:)]) {
			[self.delegate protocol:self authenticationFailedWithError:error];
		}
	} forEvent:@"auth:failed"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		if ([args count] > 0 && [args[0] isKindOfClass:[NSDictionary class]]) {
			self.serverState.serverConfiguration = args[0];
		}
	} forEvent:@"configuration"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleInitEvent:args];
	} forEvent:@"init"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		if ([args count] > 0) {
			self.serverState.metadata[@"commands"] = args[0];
		}
	} forEvent:@"commands"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleMessageEvent:args];
	} forEvent:@"msg"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleMoreEvent:args];
	} forEvent:@"more"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleSearchResults:args];
	} forEvent:@"search:results"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleNamesEvent:args];
	} forEvent:@"names"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleUsersEvent:args];
	} forEvent:@"users"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleNetworkEvent:args];
	} forEvent:@"network"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleNetworkOptionsEvent:args];
	} forEvent:@"network:options"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleNetworkStatusEvent:args];
	} forEvent:@"network:status"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleNetworkNameEvent:args];
	} forEvent:@"network:name"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleNickEvent:args];
	} forEvent:@"nick"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		if ([args count] > 0) {
			self.serverState.activeChannelId = [args[0] integerValue];
		}
	} forEvent:@"open"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleJoinEvent:args];
	} forEvent:@"join"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handlePartEvent:args];
	} forEvent:@"part"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleQuitEvent:args];
	} forEvent:@"quit"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleTopicEvent:args];
	} forEvent:@"topic"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleChannelStateEvent:args];
	} forEvent:@"channel:state"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleMuteChangedEvent:args];
	} forEvent:@"mute:changed"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleHistoryClearEvent:args];
	} forEvent:@"history:clear"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleSyncSortNetworksEvent:args];
	} forEvent:@"sync_sort:networks"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		[self handleSyncSortChannelsEvent:args];
	} forEvent:@"sync_sort:channels"];

	[self.dispatcher registerHandler:^(NSArray *args) {
		TLoungeProtocol_4_5 *self = weakSelf;
		if (!self) {
			return;
		}
		NSError *error = [NSError errorWithDomain:@"TLLoungeServerErrorDomain"
			code:101
			userInfo:@{NSLocalizedDescriptionKey: args.count ? [args[0] description] : @"Server error"}];
		if ([self.delegate respondsToSelector:@selector(protocol:didFailWithError:)]) {
			[self.delegate protocol:self didFailWithError:error];
		}
	} forEvent:@"error"];
}

- (void)performAuthentication
{
	NSMutableDictionary *payload = [NSMutableDictionary dictionary];

	NSString *pw = self.pendingPassword;

	if ([pw length] > 0) {
		NSString *u = self.pendingUsername;
		if (u) { payload[@"user"] = u; }
		payload[@"password"] = pw;
	} else {
		NSString *tok = self.pendingToken;
		if ([tok length] > 0) {
			NSString *u = self.pendingUsername;
			if (u) { payload[@"user"] = u; }
			payload[@"token"] = tok;
			payload[@"lastMessage"] = @([self highestKnownMessageId]);
			payload[@"openChannel"] = self.clientState.selectedChannelId > 0
				? @(self.clientState.selectedChannelId)
				: [NSNull null];
			payload[@"hasConfig"] = @([self.serverState.serverConfiguration count] > 0);
		}
	}

	[[MSGLogger sharedLogger] debug:@"auth:perform %@",
		[MSGLogger redactSensitiveString:[payload description]]];
	[self.socketClient emitEvent:@"auth:perform" withArguments:@[payload]];
}

- (NSInteger)highestKnownMessageId
{
	NSInteger highest = -1;
	for (MSGNetwork *network in self.serverState.networks) {
		for (MSGChannel *channel in network.channels) {
			for (MSGMessage *message in channel.messages) {
				if (message.identifier > highest) {
					highest = message.identifier;
				}
			}
		}
	}
	return highest;
}

- (void)handleInitEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];

	[[MSGLogger sharedLogger] debug:@"[RX] INIT: parsing payload (%lu keys)",
		(unsigned long)[payload count]];

	MSGServerState *newState = [[[MSGServerState alloc] initWithInitPayload:payload] autorelease];

	if (payload[@"token"]) {
		newState.metadata[@"token"] = payload[@"token"];
	}

	if ([self.serverState.networks count] == 0) {
		// First connection: build a fresh state.
		self.serverState.networks = newState.networks;
		// Seed unseen from genuinely unread chat, excluding the bouncer's
		// over-counting of technical/server status lines.
		for (MSGNetwork *network in self.serverState.networks) {
			for (MSGChannel *channel in network.channels) {
				TLSeedUnseenFromMessages(channel);
			}
		}
	} else {
		// Reconnection: reconcile the incoming state with the existing local
		// model so no messages, channels or networks are lost or duplicated.
		[self reconcileWithState:newState];
	}

	self.serverState.activeChannelId = newState.activeChannelId;
	self.serverState.serverConfiguration = newState.serverConfiguration.count
		? newState.serverConfiguration
		: self.serverState.serverConfiguration;

	// Retain any session token for fast re-authentication after reconnect.
	if (newState.metadata[@"token"]) {
		self.serverState.metadata[@"token"] = newState.metadata[@"token"];
		// Promote the fresh token over the login credentials so the next
		// auth:perform resumes the session (token + lastMessage) instead
		// of replaying the raw password.
		[self adoptSessionToken:newState.metadata[@"token"]];
	}

	[self updateCurrentUserNick];

	[self setReady:YES];

	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGNetworkListDidChangeNotification object:self];

	if ([self.delegate respondsToSelector:@selector(protocolDidBecomeReady:)]) {
		[self.delegate protocolDidBecomeReady:self];
	}
}

- (void)updateCurrentUserNick
{
	for (MSGNetwork *network in self.serverState.networks) {
		if ([network.nick length] > 0) {
			self.serverState.currentUserNick = network.nick;
			return;
		}
	}
}

- (void)reconcileWithState:(MSGServerState *)incoming
{
	// Merge networks that exist locally, add networks that are new.
	for (MSGNetwork *newNetwork in incoming.networks) {
		MSGNetwork *existing = [self.serverState networkWithUuid:newNetwork.uuid];
		if (existing) {
			[self reconcileNetwork:newNetwork into:existing];
		} else {
			[self.serverState addNetwork:newNetwork];
		}
	}

	// Remove networks the server no longer knows about.
	NSMutableArray *toRemove = [NSMutableArray array];
	for (MSGNetwork *existing in self.serverState.networks) {
		if (![incoming networkWithUuid:existing.uuid]) {
			[toRemove addObject:existing.uuid];
		}
	}
	for (NSString *uuid in toRemove) {
		[self.serverState removeNetworkWithUuid:uuid];
	}
}

- (void)reconcileNetwork:(MSGNetwork *)newNetwork into:(MSGNetwork *)existing
{
	existing.name = newNetwork.name;
	if ([newNetwork.nick length] > 0) {
		existing.nick = newNetwork.nick;
	}
	if (newNetwork.serverOptions) {
		existing.serverOptions = newNetwork.serverOptions;
	}
	existing.connected = newNetwork.connected;
	existing.secure = newNetwork.secure;

	// Merge channels.
	for (MSGChannel *newChannel in newNetwork.channels) {
		MSGChannel *existingChannel = [existing channelWithIdentifier:newChannel.identifier];
		if (existingChannel) {
			[self reconcileChannel:newChannel into:existingChannel];
		} else {
			[existing addChannel:newChannel];
			// Seed the client-side unseen count, excluding technical/server
			// messages, for a freshly added channel.
			TLSeedUnseenFromMessages(newChannel);
		}
	}

	// Remove channels the server no longer knows about.
	NSMutableArray *toRemove = [NSMutableArray array];
	for (MSGChannel *existingChannel in existing.channels) {
		if (![newNetwork channelWithIdentifier:existingChannel.identifier]) {
			[toRemove addObject:@(existingChannel.identifier)];
		}
	}
	for (NSNumber *chanId in toRemove) {
		[existing removeChannelWithIdentifier:[chanId integerValue]];
	}
}

// Seed the client-side unseen counts from the bouncer baseline, but exclude
// technical/server messages (which the bouncer counts in `unread`). We count
// only genuinely unread chat among the messages we actually received, then add
// the remainder of the server's unread total (messages not sent to us because
// they fall outside the loaded window) unchanged.
static void TLSeedUnseenFromMessages(MSGChannel *channel)
{
	if (channel.firstUnread == 0) {
		channel.unseen = 0;
		channel.unseenHighlight = 0;
		return;
	}
	NSInteger loadedUnread = 0;
	NSInteger loadedUnseen = 0;
	NSInteger loadedUnseenHl = 0;
	for (MSGMessage *m in channel.messages) {
		if (m.identifier < channel.firstUnread) {
			continue;
		}
		loadedUnread++;
		if ([m countsAsUnseen]) {
			loadedUnseen++;
			if (m.highlight) {
				loadedUnseenHl++;
			}
		}
	}
	NSInteger remainder = channel.unread - loadedUnread;
	if (remainder < 0) {
		remainder = 0;
	}
	channel.unseen = loadedUnseen + remainder;
	channel.unseenHighlight = loadedUnseenHl;
}

- (void)reconcileChannel:(MSGChannel *)newChannel into:(MSGChannel *)existing
{
	existing.name = newChannel.name;
	existing.topic = newChannel.topic;
	existing.key = newChannel.key;
	existing.unread = newChannel.unread;
	existing.highlight = newChannel.highlight;
	existing.firstUnread = newChannel.firstUnread;
	existing.muted = newChannel.muted;
	existing.state = newChannel.state;
	existing.specialType = newChannel.specialType;
	existing.closed = newChannel.closed;
	existing.numUsers = newChannel.numUsers;
	existing.totalMessages = newChannel.totalMessages;

	// The incoming channel carries messages newer than the client's last seen
	// id (plus up to 100). Append them, deduplicating by server id.
	for (MSGMessage *message in newChannel.messages) {
		[existing addMessage:message];
	}

	// Seed the client-side unseen from genuinely unread chat messages, so the
	// bouncer's over-counting of technical/server messages does not inflate
	// the badge. Only seed until we start counting locally, so later syncs do
	// not clobber counts accumulated while the window was hidden.
	if (existing.unseen == 0) {
		TLSeedUnseenFromMessages(existing);
	}
}

- (void)handleMessageEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"chan"] integerValue];
	NSDictionary *msgDict = payload[@"msg"];
	if (![msgDict isKindOfClass:[NSDictionary class]]) {
		return;
	}

	MSGChannel *channel = [self.serverState channelWithIdentifier:chanId];
	if (!channel) {
		[[MSGLogger sharedLogger] debug:@"msg for unknown channel %ld, ignoring", (long)chanId];
		return;
	}

	MSGMessage *message = [[MSGMessage alloc] initWithDictionary:msgDict];
	message.channelId = chanId;
	[channel addMessage:message];

	// The bouncer does not always include the absolute unread/highlight
	// counts on every `msg` event, so we maintain them locally (SPEC #24:
	// "maintain independently of the currently displayed view"). Use the
	// server value when supplied, otherwise count the message ourselves.
	// The channel being viewed is never counted as unread, matching the
	// bouncer, which stops incrementing it once the channel is open.
	BOOL isActiveChannel = (self.serverState.activeChannelId == chanId);

	if (payload[@"unread"]) {
		channel.unread = [payload[@"unread"] integerValue];
	} else if (!isActiveChannel && [message countsAsUnseen]) {
		channel.unread += 1;
	}

	if (payload[@"highlight"]) {
		channel.highlight = [payload[@"highlight"] integerValue];
	} else if (!isActiveChannel && [message countsAsUnseen] &&
		[message highlight]) {
		channel.highlight += 1;
	}

	// The unseen count is purely client-side and window-visibility aware: it
	// grows for every message the user has not actually looked at, including
	// the active channel while the window is hidden. The controller clears it
	// for the active channel once the window is on screen. Technical/server
	// status lines are excluded so they do not inflate the badge.
	if ([message countsAsUnseen]) {
		channel.unseen += 1;
		if ([message highlight]) {
			channel.unseenHighlight += 1;
		}
	}

	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGMessagesDidChangeNotification
		object:self
		userInfo:@{@"channelId": @(chanId), @"message": message}];
}

- (void)handleMoreEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"chan"] integerValue];
	NSArray *messages = payload[@"messages"];

	MSGChannel *channel = [self.serverState channelWithIdentifier:chanId];
	if (!channel) {
		return;
	}
	if (payload[@"totalMessages"]) {
		channel.totalMessages = [payload[@"totalMessages"] integerValue];
	}

	if ([messages isKindOfClass:[NSArray class]]) {
		NSMutableArray *newMessages = [NSMutableArray array];
		for (id m in messages) {
			if ([m isKindOfClass:[NSDictionary class]]) {
				MSGMessage *message = [[MSGMessage alloc] initWithDictionary:m];
				message.channelId = chanId;
				if (![channel messageWithIdentifier:message.identifier]) {
					[newMessages addObject:message];
				}
			}
		}
		[channel prependMessages:newMessages];
	}

	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGHistoryDidChangeNotification
		object:self
		userInfo:@{@"channelId": @(chanId)}];
}

// The bouncer answers a `search` event with `search:results`; each result is
// a stored message (type "message" only) whose `time` is a Unix millisecond
// epoch. Resolve the channel back from the echoed network uuid and channel
// name, build model messages with private ids, and hand them to the UI.
- (void)handleSearchResults:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSArray *results = payload[@"results"];
	if (![results isKindOfClass:[NSArray class]]) {
		return;
	}
	NSString *networkUuid = [payload[@"networkUuid"] description];
	NSString *channelName = [payload[@"channelName"] description];
	MSGNetwork *network = [self.serverState networkWithUuid:networkUuid];
	MSGChannel *channel = nil;
	if (network) {
		channel = [network channelWithName:channelName];
	}
	NSInteger chanId = channel ? channel.identifier : 0;

	NSMutableArray *messages = [NSMutableArray array];
	NSInteger index = 0;
	for (id m in results) {
		if (![m isKindOfClass:[NSDictionary class]]) {
			continue;
		}
		MSGMessage *message = [[MSGMessage alloc] initWithDictionary:m];
		message.channelId = chanId;
		message.identifier = TLLoungeSearchResultIdBase - index;
		index++;
		[messages addObject:message];
		[message release];
	}

	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGSearchResultsDidChangeNotification
		object:self
		userInfo:@{@"channelId": @(chanId), @"messages": messages,
			@"count": @([messages count])}];
}

- (void)handleNamesEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"id"] integerValue];
	NSArray *users = payload[@"users"];

	MSGChannel *channel = [self.serverState channelWithIdentifier:chanId];
	if (!channel) {
		return;
	}

	[channel.users removeAllObjects];
	if ([users isKindOfClass:[NSArray class]]) {
		for (id u in users) {
			if ([u isKindOfClass:[NSDictionary class]]) {
				[channel addUser:[[MSGUser alloc] initWithDictionary:u]];
			}
		}
	}
	channel.numUsers = [channel.users count];

	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGUserListDidChangeNotification
		object:self
		userInfo:@{@"channelId": @(chanId)}];
}

- (void)handleUsersEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"chan"] integerValue];

	MSGChannel *channel = [self.serverState channelWithIdentifier:chanId];
	if (!channel) {
		return;
	}
	// The user list changed; the server expects the client to request the new
	// list. Clear stale users so the UI reflects the transition immediately.
	[channel.users removeAllObjects];
	channel.numUsers = 0;

	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGUserListDidChangeNotification
		object:self
		userInfo:@{@"channelId": @(chanId)}];

	[self requestNamesForChannelId:chanId];
}

- (void)handleNetworkEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSDictionary *networkDict = payload[@"network"];
	if (![networkDict isKindOfClass:[NSDictionary class]]) {
		return;
	}

	MSGNetwork *network = [[MSGNetwork alloc] initWithDictionary:networkDict];
	[self.serverState addNetwork:network];

	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGNetworkListDidChangeNotification object:self];
}

- (void)handleNetworkOptionsEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	MSGNetwork *network = [self.serverState networkWithUuid:payload[@"network"]];
	if (network && [payload[@"serverOptions"] isKindOfClass:[NSDictionary class]]) {
		network.serverOptions = payload[@"serverOptions"];
		[[NSNotificationCenter defaultCenter]
			postNotificationName:MSGNetworkListDidChangeNotification object:self];
	}
}

- (void)handleNetworkStatusEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	MSGNetwork *network = [self.serverState networkWithUuid:payload[@"network"]];
	if (network) {
		network.connected = [payload[@"connected"] boolValue];
		network.secure = [payload[@"secure"] boolValue];
		[[NSNotificationCenter defaultCenter]
			postNotificationName:MSGNetworkListDidChangeNotification object:self];
	}
}

- (void)handleNetworkNameEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	MSGNetwork *network = [self.serverState networkWithUuid:payload[@"uuid"]];
	if (network) {
		if (payload[@"name"]) {
			network.name = [payload[@"name"] description];
		}
		[[NSNotificationCenter defaultCenter]
			postNotificationName:MSGNetworkListDidChangeNotification object:self];
	}
}

- (void)handleNickEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	MSGNetwork *network = [self.serverState networkWithUuid:payload[@"network"]];
	if (network) {
		if (payload[@"nick"]) {
			network.nick = [payload[@"nick"] description];
			self.serverState.currentUserNick = network.nick;
		}
		[[NSNotificationCenter defaultCenter]
			postNotificationName:MSGNetworkListDidChangeNotification object:self];
	}
}

- (void)handleJoinEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	MSGNetwork *network = [self.serverState networkWithUuid:payload[@"network"]];
	NSDictionary *chanDict = payload[@"chan"];
	if (!network || ![chanDict isKindOfClass:[NSDictionary class]]) {
		return;
	}

	MSGChannel *channel = [[MSGChannel alloc] initWithDictionary:chanDict];
	[network addChannel:channel];

	if ([payload[@"shouldOpen"] boolValue] && channel.identifier > 0) {
		self.clientState.selectedChannelId = channel.identifier;
	}

	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGNetworkListDidChangeNotification object:self];
}

- (void)handlePartEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"chan"] integerValue];

	MSGNetwork *network = [self.serverState networkContainingChannel:chanId];
	if (network) {
		[network removeChannelWithIdentifier:chanId];
		[[NSNotificationCenter defaultCenter]
			postNotificationName:MSGNetworkListDidChangeNotification object:self];
	}
}

- (void)handleQuitEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSString *uuid = payload[@"network"];
	if ([uuid isKindOfClass:[NSString class]]) {
		[self.serverState removeNetworkWithUuid:uuid];
		[[NSNotificationCenter defaultCenter]
			postNotificationName:MSGNetworkListDidChangeNotification object:self];
	}
}

- (void)handleTopicEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"chan"] integerValue];
	MSGChannel *channel = [self.serverState channelWithIdentifier:chanId];
	if (channel) {
		if (payload[@"topic"]) {
			channel.topic = [payload[@"topic"] description];
		}
		[[NSNotificationCenter defaultCenter]
			postNotificationName:MSGChannelDidChangeNotification
			object:self
			userInfo:@{@"channelId": @(chanId)}];
	}
}

- (void)handleChannelStateEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"chan"] integerValue];
	MSGChannel *channel = [self.serverState channelWithIdentifier:chanId];
	if (channel) {
		channel.state = [payload[@"state"] integerValue];
		[[NSNotificationCenter defaultCenter]
			postNotificationName:MSGChannelDidChangeNotification
			object:self
			userInfo:@{@"channelId": @(chanId)}];
	}
}

- (void)handleMuteChangedEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"target"] integerValue];
	MSGChannel *channel = [self.serverState channelWithIdentifier:chanId];
	if (channel) {
		channel.muted = [payload[@"status"] boolValue];
		[[NSNotificationCenter defaultCenter]
			postNotificationName:MSGChannelDidChangeNotification
			object:self
			userInfo:@{@"channelId": @(chanId)}];
	}
}

- (void)handleHistoryClearEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSInteger chanId = [payload[@"target"] integerValue];
	MSGChannel *channel = [self.serverState channelWithIdentifier:chanId];
	if (channel) {
		[channel.messages removeAllObjects];
		channel.unread = 0;
		channel.highlight = 0;
		channel.unseen = 0;
		channel.unseenHighlight = 0;
		channel.firstUnread = 0;
		[[NSNotificationCenter defaultCenter]
			postNotificationName:MSGMessagesDidChangeNotification
			object:self
			userInfo:@{@"channelId": @(chanId)}];
	}
}

- (void)handleSyncSortNetworksEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	NSArray *order = payload[@"order"];
	if (![order isKindOfClass:[NSArray class]]) {
		return;
	}
	NSMutableArray *reordered = [NSMutableArray array];
	for (NSString *uuid in order) {
		MSGNetwork *network = [self.serverState networkWithUuid:uuid];
		if (network) {
			[reordered addObject:network];
		}
	}
	for (MSGNetwork *network in self.serverState.networks) {
		if (![reordered containsObject:network]) {
			[reordered addObject:network];
		}
	}
	self.serverState.networks = reordered;
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGNetworkListDidChangeNotification object:self];
}

- (void)handleSyncSortChannelsEvent:(NSArray *)args
{
	if ([args count] == 0 || ![args[0] isKindOfClass:[NSDictionary class]]) {
		return;
	}
	NSDictionary *payload = args[0];
	MSGNetwork *network = [self.serverState networkWithUuid:payload[@"network"]];
	NSArray *order = payload[@"order"];
	if (!network || ![order isKindOfClass:[NSArray class]]) {
		return;
	}
	NSMutableArray *reordered = [NSMutableArray array];
	for (NSNumber *chanId in order) {
		MSGChannel *channel = [network channelWithIdentifier:[chanId integerValue]];
		if (channel) {
			[reordered addObject:channel];
		}
	}
	for (MSGChannel *channel in network.channels) {
		if (![reordered containsObject:channel]) {
			[reordered addObject:channel];
		}
	}
	network.channels = reordered;
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGNetworkListDidChangeNotification object:self];
}

@end