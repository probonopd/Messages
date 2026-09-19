/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGProtocol.h"
#import "MSGServerState.h"
#import "MSGClientState.h"
#import "MSGEventDispatcher.h"

NSString *const MSGNetworkListDidChangeNotification = @"MSGNetworkListDidChangeNotification";
NSString *const MSGChannelDidChangeNotification = @"MSGChannelDidChangeNotification";
NSString *const MSGMessagesDidChangeNotification = @"MSGMessagesDidChangeNotification";
NSString *const MSGUserListDidChangeNotification = @"MSGUserListDidChangeNotification";
NSString *const MSGNicknamesDidChangeNotification = @"MSGNicknamesDidChangeNotification";
NSString *const MSGHistoryDidChangeNotification = @"MSGHistoryDidChangeNotification";
NSString *const MSGSearchResultsDidChangeNotification = @"MSGSearchResultsDidChangeNotification";

@interface MSGProtocol ()
{
	NSString *_pendingUsername;
	NSString *_pendingPassword;
	NSString *_pendingToken;
	BOOL _isAuthenticated;
	BOOL _isReady;
}
@end

@implementation MSGProtocol

- (instancetype)initWithServerState:(MSGServerState *)serverState
	clientState:(MSGClientState *)clientState
{
	self = [super init];
	if (self) {
		// The account owns both states and outlives its protocol.
		_serverState = serverState;
		_clientState = clientState;
		_dispatcher = [[MSGEventDispatcher alloc] init];
		_pendingUsername = [@"" copy];
		_pendingPassword = [@"" copy];
		_pendingToken = [@"" copy];
		[self registerEventHandlers];
	}
	return self;
}

- (void)dealloc
{
	[_dispatcher release];
	[_pendingUsername release];
	[_pendingPassword release];
	[_pendingToken release];
	[super dealloc];
}

- (MSGCapabilities)capabilities
{
	return 0;
}

- (void)registerEventHandlers
{
}

- (void)transportDidConnect
{
}

- (void)resetSession
{
	_isAuthenticated = NO;
	_isReady = NO;
	// Credentials are kept: the automatic reconnect must be able to
	// re-authenticate.
}

- (void)setUsername:(NSString *)username password:(NSString *)password
{
	[_pendingUsername release];
	_pendingUsername = [(username ?: @"") copy];
	[_pendingPassword release];
	_pendingPassword = [(password ?: @"") copy];
	[_pendingToken release];
	_pendingToken = [@"" copy];
}

- (void)setUsername:(NSString *)username token:(NSString *)token
{
	[_pendingUsername release];
	_pendingUsername = [(username ?: @"") copy];
	[_pendingToken release];
	_pendingToken = [(token ?: @"") copy];
	[_pendingPassword release];
	_pendingPassword = [@"" copy];
}

- (void)adoptSessionToken:(NSString *)token
{
	[_pendingToken release];
	_pendingToken = [(token ?: @"") copy];
	[_pendingPassword release];
	_pendingPassword = [@"" copy];
}

- (void)performAuthentication
{
}

- (void)sendMessage:(NSString *)text toChannelId:(NSInteger)channelId
{
}

- (void)sendCommand:(NSString *)command toChannelId:(NSInteger)channelId
{
	[self sendMessage:command toChannelId:channelId];
}

- (void)openChannelId:(NSInteger)channelId
{
}

- (void)requestNamesForChannelId:(NSInteger)channelId
{
}

- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
{
	[self loadMoreHistoryForChannelId:channelId lastId:lastId query:nil];
}

- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
	query:(NSString *)query
{
}

- (void)searchMessagesForChannelId:(NSInteger)channelId term:(NSString *)term
	offset:(NSInteger)offset
{
}

- (void)clearHistoryForChannelId:(NSInteger)channelId
{
}

- (void)setMuted:(BOOL)muted forChannelId:(NSInteger)channelId
{
}

- (void)joinChannelNamed:(NSString *)name lobbyId:(NSInteger)lobbyId
{
}

- (void)joinExistingChannelNamed:(NSString *)name lobbyId:(NSInteger)lobbyId
{
	[self joinChannelNamed:name lobbyId:lobbyId];
}

- (void)removeNetwork:(MSGNetwork *)network
{
}

- (NSArray *)knownGroupNames
{
	return @[];
}

- (void)ensureJoinedChannelId:(NSInteger)channelId
{
}

- (void)deleteGroupChannelId:(NSInteger)channelId
{
}

- (void)deleteAllOwnedGroups
{
}

- (BOOL)isAuthenticated
{
	return _isAuthenticated;
}

- (BOOL)isReady
{
	return _isReady;
}

- (BOOL)isConnected
{
	return NO;
}

- (void)setAuthenticated:(BOOL)authenticated
{
	_isAuthenticated = authenticated;
}

- (void)setReady:(BOOL)ready
{
	_isReady = ready;
}

- (NSString *)pendingUsername
{
	return _pendingUsername;
}

- (NSString *)pendingPassword
{
	return _pendingPassword;
}

- (NSString *)pendingToken
{
	return _pendingToken;
}

@end
