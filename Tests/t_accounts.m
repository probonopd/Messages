/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

/* t_accounts.m - ObjectTesting coverage for the MessagesKit account layer:
 * backend registry, id slots, routing, the combined model and persistence.
 * Headless, no network. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "MSGAccount.h"
#import "MSGAccountManager.h"
#import "MSGBackend.h"
#import "MSGBackendRegistry.h"
#import "MSGProtocol.h"
#import "MSGServerState.h"
#import "MSGClientState.h"
#import "MSGNetwork.h"
#import "MSGChannel.h"
#import "MSGMessage.h"

// A protocol that records what it was asked to do instead of talking to a
// server.
@interface FakeProtocol : MSGProtocol
@property (nonatomic, retain) NSMutableArray *calls;
@end

@implementation FakeProtocol
- (instancetype)initWithServerState:(MSGServerState *)s clientState:(MSGClientState *)c
{
	self = [super initWithServerState:s clientState:c];
	if (self) {
		_calls = [[NSMutableArray alloc] init];
	}
	return self;
}
- (void)dealloc
{
	[_calls release];
	[super dealloc];
}
- (BOOL)isConnected
{
	return [self isReady];
}
- (void)openChannelId:(NSInteger)channelId
{
	[_calls addObject:[NSString stringWithFormat:@"open %ld", (long)channelId]];
}
- (void)sendMessage:(NSString *)text toChannelId:(NSInteger)channelId
{
	[_calls addObject:[NSString stringWithFormat:@"send %ld %@", (long)channelId, text]];
}
@end

@interface FakeAccount : MSGAccount
@end

@implementation FakeAccount
+ (NSSet *)transientSettingKeys
{
	return [NSSet setWithObject:@"password"];
}
- (MSGProtocol *)newProtocolWithTransportClient:(id<MSGTransportClient>)client
{
	return [[FakeProtocol alloc] initWithServerState:self.serverState
		clientState:self.clientState];
}
- (void)openConnection
{
}
- (void)closeConnection
{
}
// Puts one network with a lobby and one channel into the account's model,
// using ids inside the account's slot the way a real protocol does.
- (void)populateWithName:(NSString *)name
{
	MSGNetwork *network = [[[MSGNetwork alloc] init] autorelease];
	network.uuid = name;
	network.name = name;
	MSGChannel *lobby = [[[MSGChannel alloc] init] autorelease];
	lobby.identifier = self.channelIdBase + 1;
	lobby.name = name;
	lobby.type = MSGChannelTypeLobby;
	[network addChannel:lobby];
	MSGChannel *channel = [[[MSGChannel alloc] init] autorelease];
	channel.identifier = self.channelIdBase + 2;
	channel.name = @"#general";
	[network addChannel:channel];
	[self.serverState addNetwork:network];
}
@end

@interface FakeServerIdAccount : FakeAccount
@end

@implementation FakeServerIdAccount
+ (BOOL)usesServerChannelIds
{
	return YES;
}
@end

@interface FakeBackend : NSObject <MSGBackend>
@end

@implementation FakeBackend
+ (NSString *)backendIdentifier { return @"test.fake"; }
+ (NSString *)displayName { return @"Fake"; }
+ (Class)accountClass { return [FakeAccount class]; }
+ (NSArray *)accountSettingFields
{
	return @[@{MSGSettingFieldKey: @"url", MSGSettingFieldLabel: @"Server",
		MSGSettingFieldType: MSGSettingFieldTypeText}];
}
+ (NSString *)validationErrorForSettings:(NSDictionary *)settings
{
	return [settings[@"url"] length] == 0 ? @"Enter a server." : nil;
}
@end

@interface FakeServerIdBackend : FakeBackend
@end

@implementation FakeServerIdBackend
+ (NSString *)backendIdentifier { return @"test.serverids"; }
+ (NSString *)displayName { return @"Another"; }
+ (Class)accountClass { return [FakeServerIdAccount class]; }
@end

static NSString *TempPath(NSString *tag)
{
	return [NSTemporaryDirectory() stringByAppendingPathComponent:
		[NSString stringWithFormat:@"t_accounts-%@-%d", tag, getpid()]];
}

static MSGAccountManager *NewManager(NSString *path)
{
	MSGBackendRegistry *registry = [[[MSGBackendRegistry alloc] init] autorelease];
	[registry registerBackendClass:[FakeBackend class]];
	[registry registerBackendClass:[FakeServerIdBackend class]];
	return [[MSGAccountManager alloc] initWithRegistry:registry storagePath:path];
}

int main(void)
{
	NSAutoreleasePool *arp = [NSAutoreleasePool new];
	NSFileManager *fm = [NSFileManager defaultManager];

	START_SET("registry")
	MSGBackendRegistry *registry = [[[MSGBackendRegistry alloc] init] autorelease];
	[registry registerBackendClass:[FakeBackend class]];
	[registry registerBackendClass:[FakeServerIdBackend class]];
	NSArray *expected = @[@"test.serverids", @"test.fake"];
	PASS_EQUAL([registry backendIdentifiers], expected,
		"backends are listed sorted by display name");
	PASS_EQUAL([registry displayNameForBackend:@"test.fake"], @"Fake",
		"display name comes from the backend");
	PASS([registry backendClassForIdentifier:@"test.fake"] == [FakeBackend class],
		"registered class is returned");
	PASS([registry backendClassForIdentifier:@"nope"] == Nil,
		"unknown backend yields Nil");

	NSString *dir = TempPath(@"plugins");
	[fm removeItemAtPath:dir error:NULL];
	NSString *good = [dir stringByAppendingPathComponent:@"Good.msgbackend/Resources"];
	NSString *bad = [dir stringByAppendingPathComponent:@"Old.msgbackend/Resources"];
	[fm createDirectoryAtPath:good withIntermediateDirectories:YES attributes:nil error:NULL];
	[fm createDirectoryAtPath:bad withIntermediateDirectories:YES attributes:nil error:NULL];
	NSDictionary *goodInfo = @{@"NSPrincipalClass": @"GoodBackend",
		@"MSGBackendIdentifier": @"test.good",
		@"MSGBackendDisplayName": @"Good",
		@"MSGBackendAPIVersion": @MSG_BACKEND_API_VERSION};
	NSDictionary *badInfo = @{@"NSPrincipalClass": @"OldBackend",
		@"MSGBackendIdentifier": @"test.old",
		@"MSGBackendDisplayName": @"Old",
		@"MSGBackendAPIVersion": @(MSG_BACKEND_API_VERSION + 1)};
	[goodInfo writeToFile:[good stringByAppendingPathComponent:@"Info-gnustep.plist"]
		atomically:YES];
	[badInfo writeToFile:[bad stringByAppendingPathComponent:@"Info-gnustep.plist"]
		atomically:YES];
	[registry addBackendsInDirectory:dir];
	PASS([[registry backendIdentifiers] containsObject:@"test.good"],
		"bundle with the current API version is registered from its Info.plist");
	PASS_EQUAL([registry displayNameForBackend:@"test.good"], @"Good",
		"display name is read without loading the bundle");
	PASS(![[registry backendIdentifiers] containsObject:@"test.old"],
		"bundle built for another API version is refused");
	PASS([registry backendClassForIdentifier:@"test.good"] == Nil,
		"a bundle without loadable code yields Nil instead of a guess");
	[fm removeItemAtPath:dir error:NULL];
	END_SET("registry")

	START_SET("slots and routing")
	NSString *path = TempPath(@"slots");
	[fm removeItemAtPath:path error:NULL];
	MSGAccountManager *manager = NewManager(path);
	NSError *error = nil;
	FakeAccount *a = (FakeAccount *)[manager addAccountWithBackend:@"test.fake"
		settings:@{@"url": @"a"} error:&error];
	FakeAccount *b = (FakeAccount *)[manager addAccountWithBackend:@"test.fake"
		settings:@{@"url": @"b"} error:&error];
	FakeAccount *s = (FakeAccount *)[manager addAccountWithBackend:@"test.serverids"
		settings:@{@"url": @"s"} error:&error];
	PASS(a != nil && b != nil && s != nil, "accounts are created");
	PASS(a.channelIdBase == MSGAccountIdSlotSize, "first account gets slot 1");
	PASS(b.channelIdBase == 2 * MSGAccountIdSlotSize, "second account gets slot 2");
	PASS(s.channelIdBase == 0, "server-id account gets slot 0");
	PASS(a.protocol.channelIdBase == a.channelIdBase, "protocol learns the base");
	PASS_EQUAL(a.backendIdentifier, @"test.fake", "account remembers its backend");

	error = nil;
	MSGAccount *s2 = [manager addAccountWithBackend:@"test.serverids"
		settings:@{@"url": @"s2"} error:&error];
	PASS(s2 == nil && error != nil, "a second server-id account is refused");
	error = nil;
	MSGAccount *invalid = [manager addAccountWithBackend:@"test.fake"
		settings:@{} error:&error];
	PASS(invalid == nil && [[error localizedDescription] isEqual:@"Enter a server."],
		"backend validation error is reported");
	error = nil;
	MSGAccount *unknown = [manager addAccountWithBackend:@"test.none"
		settings:@{@"url": @"x"} error:&error];
	PASS(unknown == nil && error != nil, "unknown backend is refused");

	[a populateWithName:@"A"];
	[b populateWithName:@"B"];
	[s populateWithName:@"S"];
	PASS([manager accountForChannelId:a.channelIdBase + 2] == a, "routes to account a");
	PASS([manager accountForChannelId:b.channelIdBase + 2] == b, "routes to account b");
	PASS([manager accountForChannelId:2] == s, "routes low ids to slot 0");
	PASS([manager accountForChannelId:9 * MSGAccountIdSlotSize] == nil,
		"unassigned slot routes nowhere");

	MSGServerState *combined = manager.combinedState;
	PASS([combined.networks count] == 3, "combined model lists every account's network");
	PASS([[combined channelWithIdentifier:b.channelIdBase + 2].name isEqual:@"#general"],
		"combined lookup finds a channel of another account");
	MSGNetwork *netB = [combined networkContainingChannel:b.channelIdBase + 1];
	PASS([netB.name isEqual:@"B"], "combined network lookup");
	PASS([manager accountForNetwork:netB] == b, "network maps to its account");

	[manager openChannelId:b.channelIdBase + 2];
	NSString *call = [NSString stringWithFormat:@"open %ld",
		(long)(b.channelIdBase + 2)];
	PASS([((FakeProtocol *)b.protocol).calls containsObject:call],
		"channel operation is routed to the owning protocol");
	PASS([((FakeProtocol *)a.protocol).calls count] == 0,
		"other accounts are not bothered");

	[manager removeAccount:b];
	PASS([manager.accounts count] == 2, "account removed");
	PASS([combined.networks count] == 2, "its networks leave the combined model");
	FakeAccount *c = (FakeAccount *)[manager addAccountWithBackend:@"test.fake"
		settings:@{@"url": @"c"} error:&error];
	PASS(c.channelIdBase == 2 * MSGAccountIdSlotSize, "a freed slot is reused");
	[manager release];
	[fm removeItemAtPath:path error:NULL];
	END_SET("slots and routing")

	START_SET("pending messages")
	NSString *path = TempPath(@"pending");
	[fm removeItemAtPath:path error:NULL];
	MSGAccountManager *manager = NewManager(path);
	FakeAccount *a = (FakeAccount *)[manager addAccountWithBackend:@"test.fake"
		settings:@{@"url": @"a"} error:NULL];
	[a populateWithName:@"A"];
	NSInteger cid = a.channelIdBase + 2;
	[manager sendMessage:@"hello" toChannelId:cid];
	MSGChannel *channel = [a.serverState channelWithIdentifier:cid];
	PASS([channel hasPendingMessages], "offline message is queued as pending");
	PASS([((FakeProtocol *)a.protocol).calls count] == 0, "nothing is sent offline");
	[a.protocol setReady:YES];
	[a protocolDidBecomeReady:a.protocol];
	NSString *sent = [NSString stringWithFormat:@"send %ld hello", (long)cid];
	PASS([((FakeProtocol *)a.protocol).calls containsObject:sent],
		"pending message is sent once the account is ready");
	PASS(![channel hasPendingMessages], "pending queue is empty afterwards");
	PASS(a.state == MSGConnectionStateReady, "account reports ready");
	[manager release];
	[fm removeItemAtPath:path error:NULL];
	END_SET("pending messages")

	START_SET("persistence")
	NSString *path = TempPath(@"persist");
	[fm removeItemAtPath:path error:NULL];
	MSGAccountManager *manager = NewManager(path);
	MSGAccount *a = [manager addAccountWithBackend:@"test.fake"
		settings:@{@"url": @"a", @"user": @"me", @"password": @"secret"} error:NULL];
	NSString *aid = [[a.identifier copy] autorelease];
	[a updateSettings:@{@"token": @"t0k"}];
	[manager addAccountWithBackend:@"test.serverids" settings:@{@"url": @"s"} error:NULL];
	[manager release];

	NSArray *onDisk = [NSArray arrayWithContentsOfFile:path];
	PASS([onDisk count] == 2, "both accounts are written");
	PASS(onDisk[0][@"settings"][@"password"] == nil, "transient keys are not written");
	PASS_EQUAL(onDisk[0][@"settings"][@"token"], @"t0k",
		"settings updated by the account are written");

	manager = NewManager(path);
	NSError *error = nil;
	PASS([manager loadAccounts:&error], "accounts load");
	PASS([manager.accounts count] == 2, "both accounts restored");
	MSGAccount *restored = [manager accountWithIdentifier:aid];
	PASS(restored != nil, "identifier survives a restart");
	PASS_EQUAL(restored.settings[@"user"], @"me", "settings survive a restart");
	PASS_EQUAL(restored.backendIdentifier, @"test.fake", "backend survives a restart");
	[manager release];

	NSMutableArray *withMissing = [[onDisk mutableCopy] autorelease];
	NSDictionary *orphan = @{@"identifier": @"orphan", @"backend": @"test.missing",
		@"settings": @{@"url": @"z"}};
	[withMissing addObject:orphan];
	[withMissing writeToFile:path atomically:YES];
	manager = NewManager(path);
	error = nil;
	PASS(![manager loadAccounts:&error] && error != nil,
		"an account of a missing backend is reported");
	PASS([manager.accounts count] == 2, "the other accounts still load");
	[manager saveAccounts:NULL];
	NSArray *rewritten = [NSArray arrayWithContentsOfFile:path];
	PASS([rewritten containsObject:orphan],
		"the account of a missing backend is kept on disk");
	[manager release];
	[fm removeItemAtPath:path error:NULL];
	END_SET("persistence")

	START_SET("connect at launch")
	NSString *path = TempPath(@"launch");
	[fm removeItemAtPath:path error:NULL];
	MSGAccountManager *manager = NewManager(path);
	MSGAccount *on = [manager addAccountWithBackend:@"test.fake"
		settings:@{@"url": @"a"} error:NULL];
	MSGAccount *off = [manager addAccountWithBackend:@"test.fake"
		settings:@{@"url": @"b", MSGAccountConnectAtLaunchKey: @NO} error:NULL];
	PASS([on connectsAtLaunch] && ![off connectsAtLaunch],
		"accounts connect at launch unless told not to");
	[manager connectAccountsForLaunch];
	PASS(on.state == MSGConnectionStateConnecting, "enabled account connects");
	PASS(off.state == MSGConnectionStateDisconnected, "disabled account stays offline");
	[manager release];
	[fm removeItemAtPath:path error:NULL];
	END_SET("connect at launch")

	[arp release];
	return 0;
}
