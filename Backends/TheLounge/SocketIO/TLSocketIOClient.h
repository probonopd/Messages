/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

#import "MSGTransportClient.h"

@interface TLSocketIOClient : NSObject <MSGTransportClient>

@property (nonatomic, assign) id<MSGTransportClientDelegate> delegate;
@property (nonatomic, readonly) BOOL isConnected;

- (void)connectToServerURL:(NSURL *)serverURL;
- (void)emitEvent:(NSString *)eventName withArguments:(NSArray *)arguments;
- (void)close;

@end