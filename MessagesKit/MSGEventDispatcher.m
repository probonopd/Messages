/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGEventDispatcher.h"
#import "MSGLogger.h"

@interface MSGEventDispatcher ()
{
	NSMutableDictionary<NSString *, MSGEventHandler> *_handlers;
}
@end

@implementation MSGEventDispatcher

- (instancetype)init
{
	self = [super init];
	if (self) {
		_handlers = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)registerHandler:(MSGEventHandler)handler forEvent:(NSString *)eventName
{
	if (!handler || !eventName) {
		return;
	}
	_handlers[eventName] = [handler copy];
}

- (void)unregisterEvent:(NSString *)eventName
{
	[_handlers removeObjectForKey:eventName];
}

- (BOOL)hasHandlerForEvent:(NSString *)eventName
{
	return _handlers[eventName] != nil;
}

- (void)dispatchEvent:(NSString *)eventName arguments:(NSArray *)arguments
{
	MSGEventHandler h = _handlers[eventName];
	if (h) {
		h(arguments ? arguments : @[]);
	}
}

@end