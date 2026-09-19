/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "NTNostrSocketClient.h"

#import "MSGWebSocketTransport.h"
#import "MSGLogger.h"

@interface NTNostrSocketClient () <MSGWebSocketTransportDelegate>
{
	MSGWebSocketTransport *_transport;
	NSString *_relayURLString;
}
@end

// MSGAccountIdSlotSize - 1
const uint64_t NTNostrIdMask = 0x00FFFFFFFFFFFFFFULL;

NSString *const NTNostermDefaultRelayURL = @"wss://chat.nosterm.com/relay";

@implementation NTNostrSocketClient

- (instancetype)init
{
	self = [super init];
	if (self) {
		_transport = [[MSGWebSocketTransport alloc] init];
		_transport.delegate = self;
	}
	return self;
}

- (void)dealloc
{
	[_transport setDelegate:nil];
	[_transport release];
	[_relayURLString release];
	[super dealloc];
}

// GNUstep copies arguments passed through performSelectorOnMainThread: and
// performSelector:withObject:afterDelay: (to hand them safely across threads).
// A socket client is a stable per-connection handle, so copying returns the
// same instance retained rather than a true clone.
- (id)copyWithZone:(NSZone *)zone
{
	return [self retain];
}

- (BOOL)isConnected
{
	return _transport.state == MSGWebSocketStateOpen;
}

- (NSString *)relayURLString
{
	return _relayURLString;
}

- (void)connectToServerURL:(NSURL *)serverURL
{
	[_relayURLString release];
	_relayURLString = [[serverURL absoluteString] retain];
	[_transport connectToURL:serverURL];
}

- (void)close
{
	[_transport close];
}

- (void)emitEvent:(NSString *)eventName withArguments:(NSArray *)arguments
{
	NSMutableArray *frame = [NSMutableArray arrayWithObject:eventName ? eventName : @""];
	if (arguments) {
		[frame addObjectsFromArray:arguments];
	}
	NSError *error = nil;
	NSData *json = [NSJSONSerialization dataWithJSONObject:frame options:0 error:&error];
	if (!json) {
		return;
	}
	[_transport sendData:json isText:YES];
}

#pragma mark - MSGWebSocketTransportDelegate

- (void)webSocketDidOpen:(MSGWebSocketTransport *)transport
{
	if ([_delegate respondsToSelector:@selector(transportClientDidConnect:)]) {
		[_delegate transportClientDidConnect:self];
	}
}

- (void)webSocket:(MSGWebSocketTransport *)transport didReceiveData:(NSData *)data isText:(BOOL)isText
{
	NSError *error = nil;
	id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
	if (![obj isKindOfClass:[NSArray class]] || [obj count] == 0) {
		return;
	}
	NSString *verb = [obj[0] description];
	NSArray *arguments = ([obj count] > 1)
		? [obj subarrayWithRange:NSMakeRange(1, [obj count] - 1)]
		: @[];
	if ([_delegate respondsToSelector:@selector(transportClient:didReceiveEvent:arguments:)]) {
		[_delegate transportClient:self didReceiveEvent:verb arguments:arguments];
	}
}

- (void)webSocket:(MSGWebSocketTransport *)transport didFailWithError:(NSError *)error
{
	if ([_delegate respondsToSelector:@selector(transportClient:didFailWithError:)]) {
		[_delegate transportClient:self didFailWithError:error];
	}
}

- (void)webSocketDidClose:(MSGWebSocketTransport *)transport
{
	if ([_delegate respondsToSelector:@selector(transportClientDidDisconnect:)]) {
		[_delegate transportClientDidDisconnect:self];
	}
}

@end
