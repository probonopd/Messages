/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGProtocol.h"

@class NTNostrSocketClient;
@class MSGNetwork;

// Nosterm: the app's channel model mapped onto NOSTR relays (NIP-01, NIP-28,
// NIP-29, NIP-42); see Nosterm.md.
@interface NTNostermProtocol : MSGProtocol

@property (nonatomic, readonly) NTNostrSocketClient *socketClient;

- (instancetype)initWithSocketClient:(NTNostrSocketClient *)client
                         serverState:(MSGServerState *)serverState
                         clientState:(MSGClientState *)clientState;

// The one network (the relay) this protocol puts into its model.
- (MSGNetwork *)managedNetwork;

// NIP-19 identity of this relay connection, for the identity panel.
- (NSString *)nostermPublicKeyHex;
- (NSString *)nostermPublicKeyNpub;

@end
