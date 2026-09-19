/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGAccount.h"
#import "MSGServerState.h"
#import "MSGClientState.h"
#import "MSGEventDispatcher.h"
#import "MSGNetwork.h"
#import "MSGChannel.h"
#import "MSGMessage.h"
#import "MSGUser.h"
#import "MSGLogger.h"

NSString *const MSGAccountStateDidChangeNotification = @"MSGAccountStateDidChangeNotification";
NSString *const MSGAccountDidBecomeReadyNotification = @"MSGAccountDidBecomeReadyNotification";
NSString *const MSGAccountErrorNotification = @"MSGAccountErrorNotification";

NSString *MSGConnectionStateDisplayString(MSGConnectionState state)
{
	switch (state) {
		case MSGConnectionStateDisconnected:
			return @"Disconnected";
		case MSGConnectionStateConnecting:
			return @"Connecting...";
		case MSGConnectionStateTransportConnected:
		case MSGConnectionStateSocketConnected:
		case MSGConnectionStateReady:
			return @"Connected";
		case MSGConnectionStateAuthenticating:
			return @"Authenticating...";
		case MSGConnectionStateInitializing:
			return @"Loading...";
		case MSGConnectionStateReconnecting:
			return @"Reconnecting...";
		case MSGConnectionStateAuthenticationFailed:
			return @"Authentication failed";
		case MSGConnectionStateProtocolError:
			return @"Protocol error";
		case MSGConnectionStateServerDisconnected:
			return @"Disconnected";
		case MSGConnectionStateConnectionError:
			return @"Connection error";
	}
	return @"";
}

@interface MSGAccount ()
{
	NSMutableDictionary *_settings;
	BOOL _manualDisconnect;
	BOOL _reconnectScheduled;
	NSInteger _reconnectAttempt;
	NSTimer *_probeTimer;
	// Set once the account reached Ready (or was restored from disk):
	// from then on failures are transient and trigger a silent reconnect
	// instead of sending the user back to the settings.
	BOOL _established;
}
@end

@implementation MSGAccount

+ (BOOL)usesServerChannelIds
{
	return NO;
}

+ (NSSet *)transientSettingKeys
{
	return [NSSet set];
}

- (instancetype)initWithIdentifier:(NSString *)identifier
	settings:(NSDictionary *)settings
{
	self = [super init];
	if (self) {
		_identifier = [identifier copy];
		_settings = [settings mutableCopy] ?: [[NSMutableDictionary alloc] init];
		_serverState = [[MSGServerState alloc] init];
		_clientState = [[MSGClientState alloc] init];
		_manualDisconnect = YES;
		_state = MSGConnectionStateDisconnected;
		_transportClient = [self newTransportClient];
		[_transportClient setDelegate:self];
		_protocol = [self newProtocolWithTransportClient:_transportClient];
		_protocol.delegate = self;
	}
	return self;
}

- (void)dealloc
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[self stopProbeTimer];
	[_transportClient setDelegate:nil];
	[_transportClient close];
	[_transportClient release];
	_protocol.delegate = nil;
	[_protocol release];
	[_serverState release];
	[_clientState release];
	[_settings release];
	[_identifier release];
	[_backendIdentifier release];
	[super dealloc];
}

#pragma mark - Settings

- (NSDictionary *)settings
{
	return [[_settings copy] autorelease];
}

- (void)updateSettings:(NSDictionary *)settings
{
	for (id key in settings) {
		id value = settings[key];
		if (value == [NSNull null]) {
			[_settings removeObjectForKey:key];
		} else {
			_settings[key] = value;
		}
	}
	[_delegate accountSettingsDidChange:self];
}

- (NSDictionary *)persistentSettings
{
	NSMutableDictionary *result = [[_settings mutableCopy] autorelease];
	[result removeObjectsForKeys:[[[self class] transientSettingKeys] allObjects]];
	return result;
}

- (void)setEstablished:(BOOL)established
{
	_established = established;
}

- (void)setChannelIdBase:(NSInteger)base
{
	_channelIdBase = base;
	_protocol.channelIdBase = base;
}

- (NSString *)displayName
{
	NSString *name = _settings[@"name"];
	if ([name length] > 0) {
		return name;
	}
	NSString *host = [[self serverURL] host] ?: _settings[@"host"];
	NSString *user = _settings[@"username"];
	if ([host length] > 0 && [user length] > 0) {
		return [NSString stringWithFormat:@"%@@%@", user, host];
	}
	return host ?: @"";
}

- (NSURL *)serverURL
{
	NSString *url = _settings[@"url"];
	return [url length] > 0 ? [NSURL URLWithString:url] : nil;
}

- (MSGCapabilities)capabilities
{
	return [_protocol capabilities];
}

- (NSArray *)networks
{
	return [NSArray arrayWithArray:_serverState.networks];
}

#pragma mark - Subclass hooks

- (id<MSGTransportClient>)newTransportClient
{
	return nil;
}

- (MSGProtocol *)newProtocolWithTransportClient:(id<MSGTransportClient>)client
{
	return [[MSGProtocol alloc] initWithServerState:_serverState clientState:_clientState];
}

- (void)configureProtocolCredentials
{
}

- (void)openConnection
{
	[_transportClient connectToServerURL:[self serverURL]];
}

- (void)closeConnection
{
	[_transportClient close];
}

#pragma mark - Connection

- (void)connect
{
	_manualDisconnect = NO;
	_reconnectAttempt = 0;
	_reconnectScheduled = NO;
	[self configureProtocolCredentials];
	[self setState:MSGConnectionStateConnecting];
	[self openConnection];
}

- (void)disconnect
{
	_manualDisconnect = YES;
	_reconnectScheduled = NO;
	[self stopProbeTimer];
	[NSObject cancelPreviousPerformRequestsWithTarget:self
		selector:@selector(attemptReconnect) object:nil];
	[self closeConnection];
	[_protocol resetSession];
	[self setState:MSGConnectionStateDisconnected];
}

- (BOOL)isConnected
{
	return [_protocol isConnected];
}

- (void)setState:(MSGConnectionState)state
{
	if (_state == state) {
		return;
	}
	_state = state;
	[[MSGLogger sharedLogger] info:@"%@: %@", [self displayName],
		MSGConnectionStateDisplayString(state)];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGAccountStateDidChangeNotification
		object:self userInfo:@{@"state": @(state)}];
}

- (void)postError:(NSError *)error recoverable:(BOOL)recoverable
{
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGAccountErrorNotification
		object:self
		userInfo:@{@"error": error, @"recoverable": @(recoverable)}];
}

#pragma mark - Reconnect

- (void)attemptReconnect
{
	_reconnectScheduled = NO;
	if (_manualDisconnect) {
		return;
	}
	[[MSGLogger sharedLogger] info:@"%@: reconnect attempt %ld", [self displayName],
		(long)_reconnectAttempt];
	[self setState:MSGConnectionStateReconnecting];
	[self openConnection];
}

- (void)scheduleReconnect
{
	if (_manualDisconnect || _reconnectScheduled) {
		return;
	}
	_reconnectScheduled = YES;
	_reconnectAttempt++;

	NSTimeInterval delay = 1.0;
	for (NSInteger i = 1; i < _reconnectAttempt && delay < 30.0; i++) {
		delay *= 2.0;
	}
	delay = MIN(delay, 30.0);
	// Jitter keeps many accounts behind one outage from reconnecting in
	// lockstep.
	delay += ((double)(arc4random() % 1000) / 1000.0) * 0.3 * delay;

	[[MSGLogger sharedLogger] info:@"%@: reconnecting in %.1f seconds",
		[self displayName], delay];
	[self setState:MSGConnectionStateReconnecting];
	[self performSelector:@selector(attemptReconnect) withObject:nil afterDelay:delay];
	// The backoff can reach 30s; a fast probe notices a returning network
	// much earlier.
	if (!_probeTimer) {
		_probeTimer = [[NSTimer scheduledTimerWithTimeInterval:3.0
			target:self selector:@selector(probeConnectivity:) userInfo:nil
			repeats:YES] retain];
	}
}

- (void)stopProbeTimer
{
	[_probeTimer invalidate];
	[_probeTimer release];
	_probeTimer = nil;
}

- (void)probeConnectivity:(NSTimer *)timer
{
	if (_manualDisconnect || _state != MSGConnectionStateReconnecting) {
		return;
	}
	if (_reconnectScheduled) {
		[NSObject cancelPreviousPerformRequestsWithTarget:self
			selector:@selector(attemptReconnect) object:nil];
	}
	[self attemptReconnect];
}

#pragma mark - MSGTransportClientDelegate (network thread)

- (void)transportClientDidConnect:(id<MSGTransportClient>)client
{
	[self performSelectorOnMainThread:@selector(handleTransportConnected)
		withObject:nil waitUntilDone:NO];
}

- (void)transportClient:(id<MSGTransportClient>)client
	didReceiveEvent:(NSString *)eventName arguments:(NSArray *)arguments
{
	NSDictionary *payload = @{@"event": eventName, @"args": arguments ?: @[]};
	[self performSelectorOnMainThread:@selector(handleTransportEvent:)
		withObject:payload waitUntilDone:NO];
}

- (void)transportClientDidDisconnect:(id<MSGTransportClient>)client
{
	[self performSelectorOnMainThread:@selector(handleTransportDisconnected)
		withObject:nil waitUntilDone:NO];
}

- (void)transportClient:(id<MSGTransportClient>)client didFailWithError:(NSError *)error
{
	[self performSelectorOnMainThread:@selector(handleTransportFailure:)
		withObject:error waitUntilDone:NO];
}

#pragma mark - Transport handling (main thread)

- (void)handleTransportConnected
{
	if (_manualDisconnect) {
		return;
	}
	[self setState:MSGConnectionStateSocketConnected];
	[_protocol transportDidConnect];
}

- (void)handleTransportEvent:(NSDictionary *)payload
{
	// One malformed event must not stop event processing for the account.
	@try {
		[_protocol.dispatcher dispatchEvent:payload[@"event"]
			arguments:payload[@"args"]];
	}
	@catch (NSException *exception) {
		[[MSGLogger sharedLogger] error:@"%@: event '%@' failed: %@",
			[self displayName], payload[@"event"], [exception reason]];
	}
}

- (void)handleTransportDisconnected
{
	if (_manualDisconnect) {
		return;
	}
	BOOL wasReady = (_state == MSGConnectionStateReady);
	[_protocol resetSession];
	if (_state == MSGConnectionStateAuthenticationFailed ||
		_state == MSGConnectionStateProtocolError) {
		// Retrying cannot fix these; the user has to change something.
		return;
	}
	if (wasReady && ([self capabilities] & MSGCapabilityReportsConnectionLoss)) {
		NSError *error = [NSError errorWithDomain:@"MSGAccountErrorDomain" code:1
			userInfo:@{NSLocalizedDescriptionKey:
				@"The connection to the server was lost."}];
		[self postError:error recoverable:YES];
	}
	if (_established) {
		[self scheduleReconnect];
	} else {
		[self setState:MSGConnectionStateServerDisconnected];
	}
}

- (void)handleTransportFailure:(NSError *)error
{
	if (_manualDisconnect) {
		return;
	}
	[[MSGLogger sharedLogger] error:@"%@: %@", [self displayName],
		[error localizedDescription]];
	[_protocol resetSession];
	if (_established) {
		[self scheduleReconnect];
		return;
	}
	[self setState:MSGConnectionStateConnectionError];
	[self postError:error recoverable:NO];
}

#pragma mark - MSGProtocolDelegate (main thread)

- (void)protocol:(MSGProtocol *)protocol didReceiveAuthStart:(NSNumber *)serverHash
{
	[self setState:MSGConnectionStateAuthenticating];
}

- (void)protocolDidAuthenticate:(MSGProtocol *)protocol
{
	[self setState:MSGConnectionStateInitializing];
}

- (void)protocol:(MSGProtocol *)protocol authenticationFailedWithError:(NSError *)error
{
	_established = NO;
	_manualDisconnect = YES;
	[self stopProbeTimer];
	[self setState:MSGConnectionStateAuthenticationFailed];
	[self postError:error recoverable:NO];
}

- (void)protocolDidBecomeReady:(MSGProtocol *)protocol
{
	_established = YES;
	_clientState.authenticated = YES;
	_reconnectAttempt = 0;
	_reconnectScheduled = NO;
	[self stopProbeTimer];

	NSInteger restore = _clientState.selectedChannelId;
	if (restore > 0 && ![_serverState channelWithIdentifier:restore]) {
		_clientState.selectedChannelId = 0;
	}

	[self setState:MSGConnectionStateReady];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGAccountDidBecomeReadyNotification object:self];
	[self flushPendingMessages];
}

- (void)protocol:(MSGProtocol *)protocol didFailWithError:(NSError *)error
{
	[self setState:MSGConnectionStateProtocolError];
	[self postError:error recoverable:NO];
}

- (void)protocol:(MSGProtocol *)protocol didObtainSettings:(NSDictionary *)settings
{
	[self updateSettings:settings];
}

#pragma mark - Sending

- (void)queuePendingText:(NSString *)text toChannelId:(NSInteger)channelId
{
	MSGChannel *channel = [_serverState channelWithIdentifier:channelId];
	if (!channel) {
		return;
	}
	MSGMessage *msg = [[[MSGMessage alloc] init] autorelease];
	msg.channelId = channelId;
	msg.text = text;
	msg.rawText = text;
	msg.timestamp = [NSDate date];
	msg.type = MSGMessageTypeMessage;
	msg.self = YES;
	msg.pending = YES;
	MSGUser *me = [[[MSGUser alloc] init] autorelease];
	MSGNetwork *network = [_serverState networkContainingChannel:channelId];
	me.nick = [network.nick length] > 0 ? network.nick : _settings[@"username"];
	msg.sender = me;
	[channel addPendingMessage:msg];
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGMessagesDidChangeNotification
		object:self userInfo:@{@"channelId": @(channelId)}];
}

- (void)sendMessage:(NSString *)text toChannelId:(NSInteger)channelId
{
	if (![_protocol isConnected]) {
		[self queuePendingText:text toChannelId:channelId];
		return;
	}
	[_protocol sendMessage:text toChannelId:channelId];
}

- (void)sendCommand:(NSString *)command toChannelId:(NSInteger)channelId
{
	if (![_protocol isConnected]) {
		[self queuePendingText:command toChannelId:channelId];
		return;
	}
	[_protocol sendCommand:command toChannelId:channelId];
}

- (void)flushPendingMessages
{
	for (MSGNetwork *network in [NSArray arrayWithArray:_serverState.networks]) {
		for (MSGChannel *channel in [NSArray arrayWithArray:network.channels]) {
			NSArray *pending = [NSArray arrayWithArray:channel.pendingMessages];
			[channel removeAllPendingMessages];
			for (MSGMessage *msg in pending) {
				if ([_protocol isConnected]) {
					[_protocol sendMessage:msg.text toChannelId:channel.identifier];
				} else {
					// Dropped again while flushing; keep it for next time.
					[channel addPendingMessage:msg];
				}
			}
		}
	}
}

@end
