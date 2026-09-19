/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

#import "MSGAccount.h"

@class MSGBackendRegistry;
@class MSGServerState;
@class MSGNetwork;

// Posted with the manager as object when accounts are added or removed.
extern NSString *const MSGAccountListDidChangeNotification;

// Every account's channel ids live in a slot of this size, so the owning
// account of any channel id is id / MSGAccountIdSlotSize.
extern const NSInteger MSGAccountIdSlotSize;

// Owns all accounts, persists them, gives the UI one combined model and
// routes channel operations to the account that owns the channel.
@interface MSGAccountManager : NSObject <MSGAccountDelegate>

@property (nonatomic, readonly) MSGBackendRegistry *registry;
@property (nonatomic, readonly) NSArray *accounts;
// Networks of all accounts, in account order. Read-only view for the UI.
@property (nonatomic, readonly) MSGServerState *combinedState;

- (instancetype)initWithRegistry:(MSGBackendRegistry *)registry
	storagePath:(NSString *)path;

// Creates, registers and saves an account; does not connect it. Returns nil
// and sets `error` when the backend is unknown, the settings are invalid or
// the account needs an id slot that is taken.
- (MSGAccount *)addAccountWithBackend:(NSString *)backendIdentifier
	settings:(NSDictionary *)settings error:(NSError **)error;
- (void)removeAccount:(MSGAccount *)account;
- (MSGAccount *)accountWithIdentifier:(NSString *)identifier;

// Loads the saved accounts; an entry that cannot be restored is an error
// that is reported and skipped, not silently dropped from disk.
- (BOOL)loadAccounts:(NSError **)error;
- (BOOL)saveAccounts:(NSError **)error;

- (void)connectAll;
- (void)disconnectAll;

- (MSGAccount *)accountForChannelId:(NSInteger)channelId;
- (MSGAccount *)accountForNetwork:(MSGNetwork *)network;

- (void)sendMessage:(NSString *)text toChannelId:(NSInteger)channelId;
- (void)sendCommand:(NSString *)command toChannelId:(NSInteger)channelId;
- (void)openChannelId:(NSInteger)channelId;
- (void)requestNamesForChannelId:(NSInteger)channelId;
- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId;
- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
	query:(NSString *)query;
- (void)searchMessagesForChannelId:(NSInteger)channelId term:(NSString *)term
	offset:(NSInteger)offset;
- (void)clearHistoryForChannelId:(NSInteger)channelId;
- (void)setMuted:(BOOL)muted forChannelId:(NSInteger)channelId;
- (void)ensureJoinedChannelId:(NSInteger)channelId;
- (void)joinChannelNamed:(NSString *)name forLobbyId:(NSInteger)lobbyId;
- (void)joinExistingChannelNamed:(NSString *)name forLobbyId:(NSInteger)lobbyId;
- (void)deleteGroupChannelId:(NSInteger)channelId;
- (void)deleteAllOwnedGroups;

@end
