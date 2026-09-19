/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@protocol MSGTransportClient;

// Callbacks arrive on the transport's network thread; MSGAccount hops them
// to the main thread before touching the model.
@protocol MSGTransportClientDelegate <NSObject>

- (void)transportClientDidConnect:(id<MSGTransportClient>)client;
- (void)transportClient:(id<MSGTransportClient>)client
	didReceiveEvent:(NSString *)eventName arguments:(NSArray *)arguments;
- (void)transportClientDidDisconnect:(id<MSGTransportClient>)client;
- (void)transportClient:(id<MSGTransportClient>)client didFailWithError:(NSError *)error;

@end

// An event-oriented connection (Socket.IO, a NOSTR relay) that delivers
// named events with argument arrays, so MSGAccount can drive every such
// backend with the same connect/reconnect state machine.
@protocol MSGTransportClient <NSObject>

@property (nonatomic, assign) id<MSGTransportClientDelegate> delegate;
@property (nonatomic, readonly) BOOL isConnected;

- (void)connectToServerURL:(NSURL *)serverURL;
- (void)emitEvent:(NSString *)eventName withArguments:(NSArray *)arguments;
- (void)close;

@end
