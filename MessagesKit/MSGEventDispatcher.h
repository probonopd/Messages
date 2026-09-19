/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

typedef void (^MSGEventHandler)(NSArray *arguments);

@interface MSGEventDispatcher : NSObject

- (void)registerHandler:(MSGEventHandler)handler forEvent:(NSString *)eventName;
- (void)unregisterEvent:(NSString *)eventName;
- (BOOL)hasHandlerForEvent:(NSString *)eventName;
- (void)dispatchEvent:(NSString *)eventName arguments:(NSArray *)arguments;

@end