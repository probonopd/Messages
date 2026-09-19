/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGNetwork.h"

@implementation MSGNetwork

- (instancetype)init
{
	self = [super init];
	if (self) {
		_uuid = @"";
		_name = @"";
		_nick = @"";
		_serverOptions = [[NSDictionary alloc] init];
		_connected = NO;
		_secure = NO;
		_channels = [[NSMutableArray alloc] init];
		_metadata = [[NSMutableDictionary alloc] init];
	}
	return self;
}

static id MSGObject(id value)
{
	return ([value isKindOfClass:[NSNull class]] || value == nil) ? nil : value;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
	self = [self init];
	if (self) {
		if (MSGObject(dict[@"uuid"])) {
			[self setUuid:[dict[@"uuid"] description]];
		}
		if (MSGObject(dict[@"name"])) {
			[self setName:[dict[@"name"] description]];
		}
		if (MSGObject(dict[@"nick"])) {
			[self setNick:[dict[@"nick"] description]];
		}
		if (MSGObject(dict[@"serverOptions"])) {
			[self setServerOptions:dict[@"serverOptions"]];
		}
		if (MSGObject(dict[@"status"])) {
			NSDictionary *status = dict[@"status"];
			if (status[@"connected"]) {
				_connected = [status[@"connected"] boolValue];
			}
			if (status[@"secure"]) {
				_secure = [status[@"secure"] boolValue];
			}
		}
		if (dict[@"channels"] && [dict[@"channels"] isKindOfClass:[NSArray class]]) {
			for (id c in dict[@"channels"]) {
				if ([c isKindOfClass:[NSDictionary class]]) {
					[_channels addObject:[[[MSGChannel alloc] initWithDictionary:c] autorelease]];
				}
			}
		}
		NSArray *known = @[@"uuid", @"name", @"nick", @"serverOptions", @"status", @"channels"];
		NSMutableDictionary *rest = [dict mutableCopy];
		[rest removeObjectsForKeys:known];
		[_metadata release];
		_metadata = rest;
	}
	return self;
}

- (MSGChannel *)channelWithIdentifier:(NSInteger)identifier
{
	for (MSGChannel *c in _channels) {
		if (c.identifier == identifier) {
			return c;
		}
	}
	return nil;
}

- (MSGChannel *)channelWithName:(NSString *)name
{
	NSString *lower = [name lowercaseString];
	for (MSGChannel *c in _channels) {
		if ([c.name.lowercaseString isEqualToString:lower]) {
			return c;
		}
	}
	return nil;
}

- (void)addChannel:(MSGChannel *)channel
{
	MSGChannel *existing = [self channelWithIdentifier:channel.identifier];
	if (existing) {
		NSInteger idx = [_channels indexOfObject:existing];
		[_channels replaceObjectAtIndex:idx withObject:channel];
		return;
	}
	[_channels addObject:channel];
}

- (void)removeChannelWithIdentifier:(NSInteger)identifier
{
	MSGChannel *existing = [self channelWithIdentifier:identifier];
	if (existing) {
		[_channels removeObject:existing];
	}
}

- (MSGChannel *)lobby
{
	for (MSGChannel *c in _channels) {
		if (c.isLobby) {
			return c;
		}
	}
	return nil;
}

- (NSInteger)badgeTotal
{
	NSInteger total = 0;
	MSGChannel *lobbyChannel = [self lobby];
	if (lobbyChannel != nil) {
		total += [lobbyChannel unseen];
	}
	for (MSGChannel *channel in _channels) {
		total += [channel badgeCount];
	}
	return total;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<MSGNetwork %@ %@ (%lu channels)>", _uuid, _name,
		(unsigned long)[_channels count]];
}

@end