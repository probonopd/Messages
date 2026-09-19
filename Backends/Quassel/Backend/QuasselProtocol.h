/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "MSGProtocol.h"

@class QuasselAccount;
@class MSGMessage;
@class Message;

// Maps the iQuassel engine (QuasselCoreConnection) onto the Messages model:
// networks become MSGNetworks with their status buffer as lobby, channel and
// query buffers become MSGChannels, buffer ids are shifted into the
// account's id slot. The engine keeps its own maps; this class mirrors them
// whenever the engine reports a change.
@interface QuasselProtocol : MSGProtocol

// The owning account, told about transport events.
@property (nonatomic, assign) QuasselAccount *account;

- (void)connectToHost:(NSString *)host port:(int)port
	username:(NSString *)username password:(NSString *)password;
- (void)close;

// Exposed for tests.
+ (MSGMessage *)messageFromQuasselMessage:(Message *)message
	channelId:(NSInteger)channelId;

@end
