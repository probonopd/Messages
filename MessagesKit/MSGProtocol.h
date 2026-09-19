/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@class MSGServerState;
@class MSGClientState;
@class MSGEventDispatcher;
@class MSGNetwork;
@class MSGProtocol;

// Posted by protocols (object: the protocol) whenever the model they own
// changes. The UI observes these with a nil object, so it never needs to know
// which backend produced a change.
extern NSString *const MSGNetworkListDidChangeNotification;
extern NSString *const MSGChannelDidChangeNotification;
extern NSString *const MSGMessagesDidChangeNotification;
extern NSString *const MSGUserListDidChangeNotification;
extern NSString *const MSGNicknamesDidChangeNotification;
extern NSString *const MSGHistoryDidChangeNotification;
extern NSString *const MSGSearchResultsDidChangeNotification;

// What a protocol can do beyond sending and receiving messages. The UI
// enables commands from these flags instead of asking which backend it is
// talking to.
typedef NS_OPTIONS(NSUInteger, MSGCapabilities) {
	// Searching the stored backlog on the server.
	MSGCapabilityServerSearch = 1 << 0,
	// Asking the server for older messages page by page.
	MSGCapabilityHistoryPaging = 1 << 1,
	// Deleting the stored history of a channel on the server.
	MSGCapabilityClearHistory = 1 << 2,
	// Muting a channel on the server.
	MSGCapabilityMute = 1 << 3,
	// IRC semantics: slash commands, topic, whois, ignore/ban lists, modes,
	// kick, and an IRC /list channel directory.
	MSGCapabilityIRCCommands = 1 << 4,
	// A list of joinable groups the protocol already knows about
	// (-knownGroupNames), offered instead of an IRC channel directory.
	MSGCapabilityGroupDirectory = 1 << 5,
	// Networks are configured on the server; removing one is a server
	// command and does not remove the account.
	MSGCapabilityServerManagedNetworks = 1 << 6,
	// A dropped connection interrupts a session the user relies on (a
	// bouncer), so the UI tells the user instead of reconnecting silently.
	MSGCapabilityReportsConnectionLoss = 1 << 7,
};

@protocol MSGProtocolDelegate <NSObject>

@optional
- (void)protocol:(MSGProtocol *)protocol didReceiveAuthStart:(NSNumber *)serverHash;
- (void)protocolDidAuthenticate:(MSGProtocol *)protocol;
- (void)protocol:(MSGProtocol *)protocol authenticationFailedWithError:(NSError *)error;
- (void)protocolDidBecomeReady:(MSGProtocol *)protocol;
- (void)protocol:(MSGProtocol *)protocol didFailWithError:(NSError *)error;
// A credential the server handed out (e.g. a session token) that the account
// should persist in its settings for the next connection.
- (void)protocol:(MSGProtocol *)protocol didObtainSettings:(NSDictionary *)settings;

@end

// Maps one backend's wire protocol onto the model. Subclasses own their
// transport client and write only into their own serverState, which the
// account manager combines with the other accounts' state for the UI.
@interface MSGProtocol : NSObject

@property (nonatomic, readonly) MSGServerState *serverState;
@property (nonatomic, readonly) MSGClientState *clientState;
@property (nonatomic, readonly) MSGEventDispatcher *dispatcher;
@property (nonatomic, assign) id<MSGProtocolDelegate> delegate;

// Channel ids this protocol hands out start here, so ids of different
// accounts never collide (see MSGAccountManager).
@property (nonatomic, assign) NSInteger channelIdBase;

@property (nonatomic, readonly) BOOL isAuthenticated;
@property (nonatomic, readonly) BOOL isReady;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) NSString *pendingUsername;
@property (nonatomic, readonly) NSString *pendingPassword;
@property (nonatomic, readonly) NSString *pendingToken;

- (instancetype)initWithServerState:(MSGServerState *)serverState
	clientState:(MSGClientState *)clientState;

- (void)setAuthenticated:(BOOL)authenticated;
- (void)setReady:(BOOL)ready;

- (MSGCapabilities)capabilities;

// Called by the designated initializer; subclasses subscribe their event
// handlers on the dispatcher here.
- (void)registerEventHandlers;
- (void)resetSession;
// Called once the transport is open, for protocols that start the handshake
// themselves instead of waiting for a server greeting.
- (void)transportDidConnect;

- (void)setUsername:(NSString *)username password:(NSString *)password;
- (void)setUsername:(NSString *)username token:(NSString *)token;
// Replaces the pending credentials with a token obtained from the server,
// so reconnects resume the session instead of replaying the password.
- (void)adoptSessionToken:(NSString *)token;
- (void)performAuthentication;

- (void)sendMessage:(NSString *)text toChannelId:(NSInteger)channelId;
- (void)sendCommand:(NSString *)command toChannelId:(NSInteger)channelId;
- (void)openChannelId:(NSInteger)channelId;
- (void)requestNamesForChannelId:(NSInteger)channelId;
- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId;
// As above, but matches `query` against older messages so a live filter can
// search the server backlog as the user scrolls up.
- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
	query:(NSString *)query;
- (void)searchMessagesForChannelId:(NSInteger)channelId term:(NSString *)term
	offset:(NSInteger)offset;
- (void)clearHistoryForChannelId:(NSInteger)channelId;
- (void)setMuted:(BOOL)muted forChannelId:(NSInteger)channelId;

// Join (or create) a channel/group by name on the network whose lobby is
// `lobbyId`.
- (void)joinChannelNamed:(NSString *)name lobbyId:(NSInteger)lobbyId;
// Join only if it exists; protocols where joining can create a group
// (Nosterm) must not create one here.
- (void)joinExistingChannelNamed:(NSString *)name lobbyId:(NSInteger)lobbyId;
// Removes a network the server manages (MSGCapabilityServerManagedNetworks).
- (void)removeNetwork:(MSGNetwork *)network;
// Names of joinable groups (MSGCapabilityGroupDirectory).
- (NSArray *)knownGroupNames;
// Re-joins an already-known group if posting requires membership.
- (void)ensureJoinedChannelId:(NSInteger)channelId;
// Test hygiene: deletes groups this identity created.
- (void)deleteGroupChannelId:(NSInteger)channelId;
- (void)deleteAllOwnedGroups;

@end
