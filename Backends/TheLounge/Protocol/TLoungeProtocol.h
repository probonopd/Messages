/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

#import "MSGProtocol.h"

@class TLSocketIOClient;

// The Lounge client protocol on top of Socket.IO. Version-specific event
// handling lives in subclasses (TLoungeProtocol_4_5).
@interface TLoungeProtocol : MSGProtocol

@property (nonatomic, readonly) TLSocketIOClient *socketClient;

- (instancetype)initWithSocketClient:(TLSocketIOClient *)client
                         serverState:(MSGServerState *)serverState
                         clientState:(MSGClientState *)clientState;

@end
