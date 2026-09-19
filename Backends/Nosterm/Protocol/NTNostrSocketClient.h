/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "MSGTransportClient.h"

// Hashed NOSTR ids are masked to fit inside the account's id slot.
extern const uint64_t NTNostrIdMask;

// The Nosterm project's public "Demo Relay" (relay.nosterm.com), used as a
// convenient default so the client can join the public Nosterm network.
extern NSString *const NTNostermDefaultRelayURL;

@interface NTNostrSocketClient : NSObject <NSCopying, MSGTransportClient>

@property (nonatomic, assign) id<MSGTransportClientDelegate> delegate;
@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) NSString *relayURLString;

- (void)connectToServerURL:(NSURL *)serverURL;
- (void)emitEvent:(NSString *)eventName withArguments:(NSArray *)arguments;
- (void)close;

@end
