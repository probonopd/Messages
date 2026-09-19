/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGAccountManager.h"
#import "MSGBackend.h"
#import "MSGBackendRegistry.h"
#import "MSGServerState.h"
#import "MSGClientState.h"
#import "MSGNetwork.h"
#import "MSGChannel.h"
#import "MSGLogger.h"

NSString *const MSGAccountListDidChangeNotification = @"MSGAccountListDidChangeNotification";

// 2^56 leaves room for 127 accounts in a signed 64-bit id and for protocols
// that hash native ids into their slot.
const NSInteger MSGAccountIdSlotSize = (NSInteger)1 << 56;

static NSString *const MSGEntryIdentifierKey = @"identifier";
static NSString *const MSGEntryBackendKey = @"backend";
static NSString *const MSGEntrySettingsKey = @"settings";

// The UI reads one model; each account keeps writing only its own state.
// This view resolves every query against the accounts at call time, so it
// never goes stale and needs no change notifications of its own.
@interface MSGCombinedServerState : MSGServerState
{
	MSGAccountManager *_manager;
}
- (instancetype)initWithManager:(MSGAccountManager *)manager;
@end

@interface MSGAccountManager ()
{
	NSMutableArray *_accounts;
	NSString *_storagePath;
	// Saved accounts whose backend is missing (e.g. an uninstalled bundle);
	// written back unchanged so they return once the backend does.
	NSMutableArray *_unloadedEntries;
}
- (MSGAccount *)accountForSlot:(NSInteger)slot;
@end

@implementation MSGCombinedServerState

- (instancetype)initWithManager:(MSGAccountManager *)manager
{
	self = [super init];
	if (self) {
		// The manager owns this object.
		_manager = manager;
	}
	return self;
}

- (NSMutableArray *)networks
{
	NSMutableArray *all = [NSMutableArray array];
	for (MSGAccount *account in _manager.accounts) {
		[all addObjectsFromArray:account.serverState.networks];
	}
	return all;
}

- (void)setNetworks:(NSMutableArray *)networks
{
	[NSException raise:NSInternalInconsistencyException
		format:@"The combined model is read-only; write to an account's state"];
}

- (MSGNetwork *)networkWithUuid:(NSString *)uuid
{
	for (MSGAccount *account in _manager.accounts) {
		MSGNetwork *network = [account.serverState networkWithUuid:uuid];
		if (network) {
			return network;
		}
	}
	return nil;
}

- (MSGChannel *)channelWithIdentifier:(NSInteger)identifier
{
	return [[_manager accountForChannelId:identifier].serverState
		channelWithIdentifier:identifier];
}

- (MSGNetwork *)networkContainingChannel:(NSInteger)identifier
{
	return [[_manager accountForChannelId:identifier].serverState
		networkContainingChannel:identifier];
}

- (void)addNetwork:(MSGNetwork *)network
{
	[self setNetworks:nil];
}

- (void)removeNetworkWithUuid:(NSString *)uuid
{
	[self setNetworks:nil];
}

@end

@implementation MSGAccountManager

- (instancetype)initWithRegistry:(MSGBackendRegistry *)registry
	storagePath:(NSString *)path
{
	self = [super init];
	if (self) {
		_registry = [registry retain];
		_storagePath = [path copy];
		_accounts = [[NSMutableArray alloc] init];
		_unloadedEntries = [[NSMutableArray alloc] init];
		_combinedState = [[MSGCombinedServerState alloc] initWithManager:self];
	}
	return self;
}

- (void)dealloc
{
	for (MSGAccount *account in _accounts) {
		account.delegate = nil;
		[account disconnect];
	}
	[_accounts release];
	[_unloadedEntries release];
	[_combinedState release];
	[_registry release];
	[_storagePath release];
	[super dealloc];
}

- (NSArray *)accounts
{
	return [NSArray arrayWithArray:_accounts];
}

- (MSGAccount *)accountWithIdentifier:(NSString *)identifier
{
	for (MSGAccount *account in _accounts) {
		if ([account.identifier isEqualToString:identifier]) {
			return account;
		}
	}
	return nil;
}

#pragma mark - Creating accounts

static NSError *MSGManagerError(NSString *message)
{
	return [NSError errorWithDomain:@"MSGAccountManagerErrorDomain" code:1
		userInfo:@{NSLocalizedDescriptionKey: message}];
}

- (MSGAccount *)accountForSlot:(NSInteger)slot
{
	for (MSGAccount *account in _accounts) {
		if (account.channelIdBase / MSGAccountIdSlotSize == slot) {
			return account;
		}
	}
	return nil;
}

// Returns the slot for a new account of `accountClass`, or -1 if none is
// free for it.
- (NSInteger)freeSlotForAccountClass:(Class)accountClass
{
	if ([accountClass usesServerChannelIds]) {
		return [self accountForSlot:0] == nil ? 0 : -1;
	}
	NSInteger maxSlot = NSIntegerMax / MSGAccountIdSlotSize;
	for (NSInteger slot = 1; slot <= maxSlot; slot++) {
		if ([self accountForSlot:slot] == nil) {
			return slot;
		}
	}
	return -1;
}

- (MSGAccount *)makeAccountWithBackend:(NSString *)backendIdentifier
	identifier:(NSString *)identifier settings:(NSDictionary *)settings
	error:(NSError **)error
{
	Class backend = [_registry backendClassForIdentifier:backendIdentifier];
	if (backend == Nil) {
		if (error) {
			*error = MSGManagerError([NSString stringWithFormat:
				@"The backend \"%@\" is not available.", backendIdentifier]);
		}
		return nil;
	}
	if ([backend respondsToSelector:@selector(validationErrorForSettings:)]) {
		NSString *problem = [backend validationErrorForSettings:settings];
		if (problem != nil) {
			if (error) {
				*error = MSGManagerError(problem);
			}
			return nil;
		}
	}
	Class accountClass = [backend accountClass];
	NSInteger slot = [self freeSlotForAccountClass:accountClass];
	if (slot < 0) {
		if (error) {
			*error = MSGManagerError([NSString stringWithFormat:
				@"Only one %@ account can be used at a time.",
				[backend displayName]]);
		}
		return nil;
	}
	MSGAccount *account = [[[accountClass alloc] initWithIdentifier:identifier
		settings:settings] autorelease];
	account.backendIdentifier = backendIdentifier;
	account.channelIdBase = slot * MSGAccountIdSlotSize;
	account.delegate = self;
	[_accounts addObject:account];
	return account;
}

- (MSGAccount *)addAccountWithBackend:(NSString *)backendIdentifier
	settings:(NSDictionary *)settings error:(NSError **)error
{
	NSString *identifier = [[NSProcessInfo processInfo] globallyUniqueString];
	MSGAccount *account = [self makeAccountWithBackend:backendIdentifier
		identifier:identifier settings:settings error:error];
	if (account == nil) {
		return nil;
	}
	[self saveAccounts:NULL];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGAccountListDidChangeNotification object:self];
	return account;
}

- (void)removeAccount:(MSGAccount *)account
{
	if (![_accounts containsObject:account]) {
		return;
	}
	[account retain];
	account.delegate = nil;
	[account disconnect];
	[_accounts removeObject:account];
	[self saveAccounts:NULL];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGAccountListDidChangeNotification object:self];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGNetworkListDidChangeNotification object:self];
	[account release];
}

#pragma mark - Persistence

- (BOOL)loadAccounts:(NSError **)error
{
	if (![[NSFileManager defaultManager] fileExistsAtPath:_storagePath]) {
		return YES;
	}
	NSArray *entries = [NSArray arrayWithContentsOfFile:_storagePath];
	if (entries == nil) {
		if (error) {
			*error = MSGManagerError([NSString stringWithFormat:
				@"The account list %@ is not readable.", _storagePath]);
		}
		return NO;
	}
	NSMutableArray *problems = [NSMutableArray array];
	for (NSDictionary *entry in entries) {
		NSError *entryError = nil;
		MSGAccount *account = [self makeAccountWithBackend:entry[MSGEntryBackendKey]
			identifier:entry[MSGEntryIdentifierKey]
			settings:entry[MSGEntrySettingsKey] error:&entryError];
		if (account == nil) {
			[problems addObject:[entryError localizedDescription]];
			[_unloadedEntries addObject:entry];
			continue;
		}
		[account setEstablished:YES];
	}
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGAccountListDidChangeNotification object:self];
	if ([problems count] > 0) {
		if (error) {
			*error = MSGManagerError([problems componentsJoinedByString:@"\n"]);
		}
		return NO;
	}
	return YES;
}

- (BOOL)saveAccounts:(NSError **)error
{
	NSMutableArray *entries = [NSMutableArray array];
	for (MSGAccount *account in _accounts) {
		[entries addObject:@{
			MSGEntryIdentifierKey: account.identifier,
			MSGEntryBackendKey: account.backendIdentifier,
			MSGEntrySettingsKey: [account persistentSettings]}];
	}
	[entries addObjectsFromArray:_unloadedEntries];
	// Settings can hold passwords and tokens.
	NSString *dir = [_storagePath stringByDeletingLastPathComponent];
	[[NSFileManager defaultManager] createDirectoryAtPath:dir
		withIntermediateDirectories:YES
		attributes:@{NSFilePosixPermissions: @0700} error:NULL];
	if (![entries writeToFile:_storagePath atomically:YES]) {
		if (error) {
			*error = MSGManagerError([NSString stringWithFormat:
				@"The account list could not be written to %@.", _storagePath]);
		}
		[[MSGLogger sharedLogger] error:@"Could not write %@", _storagePath];
		return NO;
	}
	[[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0600}
		ofItemAtPath:_storagePath error:NULL];
	return YES;
}

- (void)accountSettingsDidChange:(MSGAccount *)account
{
	[self saveAccounts:NULL];
}

#pragma mark - Connections

- (void)connectAccountsForLaunch
{
	for (MSGAccount *account in _accounts) {
		if ([account connectsAtLaunch]) {
			[account connect];
		}
	}
}

- (void)disconnectAll
{
	for (MSGAccount *account in _accounts) {
		[account disconnect];
	}
}

#pragma mark - Routing

- (MSGAccount *)accountForChannelId:(NSInteger)channelId
{
	if (channelId < 0) {
		return nil;
	}
	return [self accountForSlot:channelId / MSGAccountIdSlotSize];
}

- (MSGAccount *)accountForNetwork:(MSGNetwork *)network
{
	for (MSGAccount *account in _accounts) {
		if ([account.serverState.networks indexOfObjectIdenticalTo:network] != NSNotFound) {
			return account;
		}
	}
	return nil;
}

- (MSGProtocol *)protocolForChannelId:(NSInteger)channelId
{
	return [self accountForChannelId:channelId].protocol;
}

- (void)sendMessage:(NSString *)text toChannelId:(NSInteger)channelId
{
	[[self accountForChannelId:channelId] sendMessage:text toChannelId:channelId];
}

- (void)sendCommand:(NSString *)command toChannelId:(NSInteger)channelId
{
	[[self accountForChannelId:channelId] sendCommand:command toChannelId:channelId];
}

- (void)openChannelId:(NSInteger)channelId
{
	MSGAccount *account = [self accountForChannelId:channelId];
	account.clientState.selectedChannelId = channelId;
	[account.protocol openChannelId:channelId];
}

- (void)requestNamesForChannelId:(NSInteger)channelId
{
	[[self protocolForChannelId:channelId] requestNamesForChannelId:channelId];
}

- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
{
	[[self protocolForChannelId:channelId] loadMoreHistoryForChannelId:channelId
		lastId:lastId];
}

- (void)loadMoreHistoryForChannelId:(NSInteger)channelId lastId:(NSInteger)lastId
	query:(NSString *)query
{
	[[self protocolForChannelId:channelId] loadMoreHistoryForChannelId:channelId
		lastId:lastId query:query];
}

- (void)searchMessagesForChannelId:(NSInteger)channelId term:(NSString *)term
	offset:(NSInteger)offset
{
	[[self protocolForChannelId:channelId] searchMessagesForChannelId:channelId
		term:term offset:offset];
}

- (void)clearHistoryForChannelId:(NSInteger)channelId
{
	[[self protocolForChannelId:channelId] clearHistoryForChannelId:channelId];
}

- (void)setMuted:(BOOL)muted forChannelId:(NSInteger)channelId
{
	[[self protocolForChannelId:channelId] setMuted:muted forChannelId:channelId];
}

- (void)ensureJoinedChannelId:(NSInteger)channelId
{
	[[self protocolForChannelId:channelId] ensureJoinedChannelId:channelId];
}

- (void)joinChannelNamed:(NSString *)name forLobbyId:(NSInteger)lobbyId
{
	[[self protocolForChannelId:lobbyId] joinChannelNamed:name lobbyId:lobbyId];
}

- (void)joinExistingChannelNamed:(NSString *)name forLobbyId:(NSInteger)lobbyId
{
	[[self protocolForChannelId:lobbyId] joinExistingChannelNamed:name lobbyId:lobbyId];
}

- (void)deleteGroupChannelId:(NSInteger)channelId
{
	[[self protocolForChannelId:channelId] deleteGroupChannelId:channelId];
}

- (void)deleteAllOwnedGroups
{
	for (MSGAccount *account in _accounts) {
		[account.protocol deleteAllOwnedGroups];
	}
}

@end
