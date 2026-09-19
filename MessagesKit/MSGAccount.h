/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

#import "MSGProtocol.h"
#import "MSGTransportClient.h"

@class MSGServerState;
@class MSGClientState;
@class MSGAccount;

typedef NS_ENUM(NSInteger, MSGConnectionState) {
	MSGConnectionStateDisconnected = 0,
	MSGConnectionStateConnecting = 1,
	MSGConnectionStateTransportConnected = 2,
	MSGConnectionStateSocketConnected = 3,
	MSGConnectionStateAuthenticating = 4,
	MSGConnectionStateInitializing = 5,
	MSGConnectionStateReady = 6,
	MSGConnectionStateReconnecting = 7,
	MSGConnectionStateAuthenticationFailed = 8,
	MSGConnectionStateProtocolError = 9,
	MSGConnectionStateServerDisconnected = 10,
	MSGConnectionStateConnectionError = 11,
};

NSString *MSGConnectionStateDisplayString(MSGConnectionState state);

// All posted with the account as object, on the main thread.
extern NSString *const MSGAccountStateDidChangeNotification;   // userInfo: state
extern NSString *const MSGAccountDidBecomeReadyNotification;
extern NSString *const MSGAccountErrorNotification;            // userInfo: error, recoverable

// Settings key shared by all backends: NSNumber BOOL, default YES.
extern NSString *const MSGAccountConnectAtLaunchKey;

@protocol MSGAccountDelegate <NSObject>
// The account changed its persistent settings (e.g. obtained a token).
- (void)accountSettingsDidChange:(MSGAccount *)account;
@end

// One configured connection of one backend: owns the transport, the protocol
// and the model state that protocol fills, and runs the connect/reconnect
// state machine. Backends subclass it and supply transport and protocol.
@interface MSGAccount : NSObject <MSGProtocolDelegate, MSGTransportClientDelegate>

@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, copy) NSString *backendIdentifier;
@property (nonatomic, readonly) NSDictionary *settings;
@property (nonatomic, readonly) MSGServerState *serverState;
@property (nonatomic, readonly) MSGClientState *clientState;
@property (nonatomic, readonly) MSGProtocol *protocol;
@property (nonatomic, readonly) id<MSGTransportClient> transportClient;
@property (nonatomic, readonly) MSGConnectionState state;
@property (nonatomic, assign) id<MSGAccountDelegate> delegate;
@property (nonatomic, assign) NSInteger channelIdBase;

// YES when the protocol uses the server's channel ids verbatim and cannot
// shift them into a slot of its own; such an account gets the id slot 0,
// which only one account can hold at a time.
+ (BOOL)usesServerChannelIds;

// Setting keys that are used for the next connection only and never
// written to disk (e.g. a password that is traded for a token).
+ (NSSet *)transientSettingKeys;

- (instancetype)initWithIdentifier:(NSString *)identifier
	settings:(NSDictionary *)settings;

// Merges `settings` into the current settings (NSNull removes a key) and
// tells the delegate so it can persist them.
- (void)updateSettings:(NSDictionary *)settings;
- (NSDictionary *)persistentSettings;
// Restored accounts are known to have worked, so connection failures only
// trigger a silent reconnect instead of an error for the user.
- (void)setEstablished:(BOOL)established;

- (BOOL)connectsAtLaunch;
- (NSString *)displayName;
- (NSURL *)serverURL;
- (MSGCapabilities)capabilities;
// The networks this account put into its model.
- (NSArray *)networks;

- (void)connect;
- (void)disconnect;
- (BOOL)isConnected;

// Queues the text as a pending message while the account is offline and
// sends it once it is ready again.
- (void)sendMessage:(NSString *)text toChannelId:(NSInteger)channelId;
- (void)sendCommand:(NSString *)command toChannelId:(NSInteger)channelId;

// Subclass hooks. The base implementation of -openConnection and
// -closeConnection drives -transportClient; a backend whose engine is not
// an MSGTransportClient overrides both and reports through the
// -handleTransport... methods on the main thread.
- (id<MSGTransportClient>)newTransportClient;
- (MSGProtocol *)newProtocolWithTransportClient:(id<MSGTransportClient>)client;
- (void)configureProtocolCredentials;
- (void)openConnection;
- (void)closeConnection;
- (void)handleTransportConnected;
- (void)handleTransportDisconnected;
- (void)handleTransportFailure:(NSError *)error;

@end
