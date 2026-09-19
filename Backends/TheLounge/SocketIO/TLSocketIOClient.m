/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "TLSocketIOClient.h"
#import "TLEngineIOClient.h"
#import "TLSocketIOPacket.h"
#import "TLSocketIOParser.h"
#import "MSGLogger.h"

@interface TLSocketIOClient () <TLEngineIOClientDelegate>
{
	TLEngineIOClient *_engineIOClient;
	BOOL _isConnected;
	BOOL _closed;
	NSLock *_stateLock;
}
@end

@implementation TLSocketIOClient

- (instancetype)init
{
	self = [super init];
	if (self) {
		_engineIOClient = [[TLEngineIOClient alloc] init];
		_engineIOClient.delegate = self;
		_isConnected = NO;
		_closed = NO;
		_stateLock = [[NSLock alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[self close];
	[_engineIOClient release];
	[_stateLock release];
	[super dealloc];
}

- (void)connectToServerURL:(NSURL *)serverURL
{
	[_stateLock lock];
	_closed = NO;
	_isConnected = NO;
	[_stateLock unlock];

	// The Lounge serves the socket.io endpoint at <installation-path>socket.io/.
	NSString *path = serverURL.path;
	if ([path length] == 0) {
		path = @"/";
	}
	if (![path hasSuffix:@"/"]) {
		path = [path stringByAppendingString:@"/"];
	}
	NSString *socketIOPath = [path stringByAppendingString:@"socket.io/"];

	NSString *scheme = [serverURL.scheme lowercaseString];
	NSString *wsScheme;
	if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"ws"]) {
		wsScheme = @"ws";
	} else {
		wsScheme = @"wss";
	}

	NSMutableString *hostPart = [NSMutableString string];
	NSString *host = serverURL.host;
	if (!host) {
		host = @"localhost";
	}
	[hostPart appendString:host];
	NSNumber *port = serverURL.port;
	if (port) {
		[hostPart appendFormat:@":%@", port];
	} else if ([wsScheme isEqualToString:@"ws"]) {
		[hostPart appendString:@":80"];
	} else {
		[hostPart appendString:@":443"];
	}

	NSString *urlString = [NSString stringWithFormat:@"%@://%@%@?EIO=4&transport=websocket",
		wsScheme, hostPart, socketIOPath];
	NSURL *url = [NSURL URLWithString:urlString];
	if (!url) {
		NSError *error = [NSError errorWithDomain:@"TLSocketIOErrorDomain"
			code:10
			userInfo:@{NSLocalizedDescriptionKey: @"Invalid server URL"}];
		if ([_delegate respondsToSelector:@selector(transportClient:didFailWithError:)]) {
			[_delegate transportClient:self didFailWithError:error];
		}
		return;
	}

	[[MSGLogger sharedLogger] debug:@"Connecting to %@", [MSGLogger redactSensitiveString:urlString]];
	[_engineIOClient connectToURL:url];
}

- (void)emitEvent:(NSString *)eventName withArguments:(NSArray *)arguments
{
	TLSocketIOPacket *packet = [TLSocketIOPacket eventPacketWithName:eventName arguments:arguments];
	NSString *serialized = [TLSocketIOParser serializePacket:packet];
	[_engineIOClient sendMessageData:serialized];
}

- (void)close
{
	[_stateLock lock];
	if (_closed) {
		[_stateLock unlock];
		return;
	}
	_closed = YES;
	_isConnected = NO;
	[_stateLock unlock];

	if (_isConnected) {
		NSString *serialized = [TLSocketIOParser serializePacket:[TLSocketIOPacket disconnectPacket]];
		[_engineIOClient sendMessageData:serialized];
	}
	[_engineIOClient close];
}

- (BOOL)isConnected
{
	return _isConnected;
}

#pragma mark - TLEngineIOClientDelegate

- (void)engineIOClientDidOpen:(TLEngineIOClient *)client
{
	// Establish the Socket.IO connection on the default namespace.
	NSString *serialized = [TLSocketIOParser serializePacket:[TLSocketIOPacket connectPacket]];
	[_engineIOClient sendMessageData:serialized];
}

- (void)engineIOClient:(TLEngineIOClient *)client didReceiveMessageData:(NSString *)data
{
	TLSocketIOPacket *packet = [TLSocketIOParser parsePacketFromString:data];
	if (!packet) {
		[[MSGLogger sharedLogger] debug:@"Ignoring unparseable Socket.IO payload"];
		return;
	}

	[[MSGLogger sharedLogger] trace:@"[RX] SOCKET.IO %@", packet];

	switch (packet.type) {
		case TLSocketIOPacketTypeConnect:
			if ([packet.nsp isEqualToString:@"/"] || [packet.nsp length] == 0) {
				[_stateLock lock];
				_isConnected = YES;
				[_stateLock unlock];
				if ([_delegate respondsToSelector:@selector(transportClientDidConnect:)]) {
					[_delegate transportClientDidConnect:self];
				}
			}
			break;
		case TLSocketIOPacketTypeDisconnect:
			[_stateLock lock];
			_isConnected = NO;
			[_stateLock unlock];
			if ([_delegate respondsToSelector:@selector(transportClientDidDisconnect:)]) {
				[_delegate transportClientDidDisconnect:self];
			}
			break;
		case TLSocketIOPacketTypeConnectError:
		{
			NSError *error = [NSError errorWithDomain:@"TLSocketIOErrorDomain"
				code:11
				userInfo:@{NSLocalizedDescriptionKey: [packet.data description]}];
			if ([_delegate respondsToSelector:@selector(transportClient:didFailWithError:)]) {
				[_delegate transportClient:self didFailWithError:error];
			}
			break;
		}
		case TLSocketIOPacketTypeEvent:
		{
			NSString *name = [packet eventName];
			NSArray *args = [packet eventArguments];
			if ([_delegate respondsToSelector:@selector(transportClient:didReceiveEvent:arguments:)]) {
				[_delegate transportClient:self didReceiveEvent:name arguments:args];
			}
			break;
		}
		case TLSocketIOPacketTypeAck:
		case TLSocketIOPacketTypeBinaryEvent:
		case TLSocketIOPacketTypeBinaryAck:
		default:
			break;
	}
}

- (void)engineIOClientDidClose:(TLEngineIOClient *)client
{
	[_stateLock lock];
	BOOL wasConnected = _isConnected;
	_isConnected = NO;
	[_stateLock unlock];

	if (wasConnected && [_delegate respondsToSelector:@selector(transportClientDidDisconnect:)]) {
		[_delegate transportClientDidDisconnect:self];
	}
}

- (void)engineIOClient:(TLEngineIOClient *)client didFailWithError:(NSError *)error
{
	[_stateLock lock];
	_isConnected = NO;
	[_stateLock unlock];

	if ([_delegate respondsToSelector:@selector(transportClient:didFailWithError:)]) {
		[_delegate transportClient:self didFailWithError:error];
	}
}

@end