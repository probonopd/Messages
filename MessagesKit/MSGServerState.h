/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

#import "MSGNetwork.h"

@interface MSGServerState : NSObject

@property (nonatomic, strong) NSMutableArray<MSGNetwork *> *networks;
@property (nonatomic, assign) NSInteger activeChannelId;
@property (nonatomic, copy) NSString *currentUserNick;
@property (nonatomic, strong) NSDictionary *serverConfiguration;
@property (nonatomic, strong) NSMutableDictionary *metadata;

- (instancetype)initWithInitPayload:(NSDictionary *)payload;

- (MSGNetwork *)networkWithUuid:(NSString *)uuid;
- (void)addNetwork:(MSGNetwork *)network;
- (void)removeNetworkWithUuid:(NSString *)uuid;

- (MSGChannel *)channelWithIdentifier:(NSInteger)identifier;
- (MSGNetwork *)networkContainingChannel:(NSInteger)identifier;

- (void)clear;

@end