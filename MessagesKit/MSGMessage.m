/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGMessage.h"

static NSDictionary *MSGMessageTypeMap(void)
{
	static NSDictionary *map;
	if (!map) {
		// Static storage outlives the creating autorelease pool; the
		// literal must be retained to survive it.
		map = [@{
			@"unhandled": @(MSGMessageTypeUnhandled),
			@"action": @(MSGMessageTypeAction),
			@"away": @(MSGMessageTypeAway),
			@"back": @(MSGMessageTypeBack),
			@"error": @(MSGMessageTypeError),
			@"invite": @(MSGMessageTypeInvite),
			@"join": @(MSGMessageTypeJoin),
			@"kick": @(MSGMessageTypeKick),
			@"login": @(MSGMessageTypeLogin),
			@"logout": @(MSGMessageTypeLogout),
			@"message": @(MSGMessageTypeMessage),
			@"mode": @(MSGMessageTypeMode),
			@"mode_channel": @(MSGMessageTypeModeChannel),
			@"mode_user": @(MSGMessageTypeModeUser),
			@"monospace_block": @(MSGMessageTypeMonospaceBlock),
			@"nick": @(MSGMessageTypeNick),
			@"notice": @(MSGMessageTypeNotice),
			@"part": @(MSGMessageTypePart),
			@"quit": @(MSGMessageTypeQuit),
			@"ctcp": @(MSGMessageTypeCTCP),
			@"ctcp_request": @(MSGMessageTypeCTCPRequest),
			@"chghost": @(MSGMessageTypeChghost),
			@"topic": @(MSGMessageTypeTopic),
			@"topic_set_by": @(MSGMessageTypeTopicSetBy),
			@"whois": @(MSGMessageTypeWhois),
			@"raw": @(MSGMessageTypeRaw),
			@"plugin": @(MSGMessageTypePlugin),
			@"wallops": @(MSGMessageTypeWallops),
		} retain];
	}
	return map;
}

NSString *MSGMessageTypeToString(MSGMessageType type)
{
	for (NSString *key in MSGMessageTypeMap()) {
		if ([[MSGMessageTypeMap() objectForKey:key] integerValue] == type) {
			return key;
		}
	}
	return @"unhandled";
}

MSGMessageType MSGMessageTypeFromString(NSString *s)
{
	NSNumber *n = [MSGMessageTypeMap() objectForKey:s ? s : @"unhandled"];
	return n ? [n integerValue] : MSGMessageTypeUnhandled;
}

@implementation MSGMessage

- (instancetype)init
{
	self = [super init];
	if (self) {
		_identifier = 0;
		_msgid = @"";
		_timestamp = [[NSDate date] retain];
		_sender = [[MSGUser alloc] init];
		_channelId = 0;
		_type = MSGMessageTypeMessage;
		_rawText = @"";
		_text = @"";
		_hostmask = @"";
		_target = nil;
		_self = NO;
		_highlight = NO;
		_showInActive = NO;
		_newNick = @"";
		_newIdent = @"";
		_newHost = @"";
		_ctcpMessage = @"";
		_command = @"";
		_invitedYou = NO;
		_gecos = @"";
		_account = NO;
		_users = [[NSArray alloc] init];
		_statusmsgGroup = @"";
		_params = [[NSArray alloc] init];
		_metadata = [[NSMutableDictionary alloc] init];
		_pending = NO;
	}
	return self;
}

static id MSGObject(id value)
{
	return ([value isKindOfClass:[NSNull class]] || value == nil) ? nil : value;
}

static NSDate *MSGParseISO8601(NSString *string)
{
	// The Lounge serializes message timestamps as ISO 8601 strings such as
	// "2025-06-01T12:00:00.000Z" via socket.io.
	NSArray *formats = @[
		@"yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
		@"yyyy-MM-dd'T'HH:mm:ssXXXXX",
		@"yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ",
		@"yyyy-MM-dd'T'HH:mm:ssZZZZZ",
	];
	NSDateFormatter *formatter = [[[NSDateFormatter alloc] init] autorelease];
	[formatter setLocale:[[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"] autorelease]];
	for (NSString *format in formats) {
		[formatter setDateFormat:format];
		NSDate *date = [formatter dateFromString:string];
		if (date) {
			return date;
		}
	}
	return nil;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict
{
	self = [self init];
	if (self) {
		if (dict[@"id"]) {
			_identifier = [dict[@"id"] integerValue];
		}
		if (MSGObject(dict[@"msgid"])) {
			[self setMsgid:[dict[@"msgid"] description]];
		}
		if (MSGObject(dict[@"text"])) {
			[self setRawText:[dict[@"text"] description]];
			_text = _rawText;
		}
		if (MSGObject(dict[@"type"])) {
			_type = MSGMessageTypeFromString([dict[@"type"] description]);
		}
		if (dict[@"time"]) {
			id t = MSGObject(dict[@"time"]);
			// Direct ivar writes bypass the retained setter, so every
			// assignment must take ownership itself.
			NSDate *newTimestamp = nil;
			if ([t isKindOfClass:[NSDate class]]) {
				newTimestamp = [t retain];
			} else if ([t isKindOfClass:[NSString class]]) {
				newTimestamp = [MSGParseISO8601(t) retain];
				if (!newTimestamp) {
					newTimestamp = [[NSDate dateWithString:t] retain];
				}
			} else if ([t isKindOfClass:[NSNumber class]]) {
				// The Lounge stores message time as a Unix millisecond
				// epoch; the history `more` event instead sends an ISO
				// string. Normalize milliseconds to seconds here.
				NSTimeInterval ti = [t doubleValue];
				if (ti > 1e11) {
					ti /= 1000.0;
				}
				newTimestamp = [[NSDate dateWithTimeIntervalSince1970:ti] retain];
			}
			if (newTimestamp) {
				[_timestamp release];
				_timestamp = newTimestamp;
			}
		}
		if (MSGObject(dict[@"from"])) {
			// init already installed a default sender; take it over before
			// replacing the ivar so the default does not leak.
			[_sender release];
			_sender = [[MSGUser alloc] initWithDictionary:dict[@"from"]];
		}
		if (MSGObject(dict[@"target"])) {
			_target = [[MSGUser alloc] initWithDictionary:dict[@"target"]];
		}
		if (MSGObject(dict[@"hostmask"])) {
			[self setHostmask:[dict[@"hostmask"] description]];
		}
		if (dict[@"self"]) {
			_self = [dict[@"self"] boolValue];
		}
		if (dict[@"highlight"]) {
			_highlight = [dict[@"highlight"] boolValue];
		}
		if (dict[@"showInActive"]) {
			_showInActive = [dict[@"showInActive"] boolValue];
		}
		if (MSGObject(dict[@"new_nick"])) {
			[self setNewNick:[dict[@"new_nick"] description]];
		}
		if (MSGObject(dict[@"new_ident"])) {
			[self setNewIdent:[dict[@"new_ident"] description]];
		}
		if (MSGObject(dict[@"new_host"])) {
			[self setNewHost:[dict[@"new_host"] description]];
		}
		if (MSGObject(dict[@"ctcpMessage"])) {
			[self setCtcpMessage:[dict[@"ctcpMessage"] description]];
		}
		if (MSGObject(dict[@"command"])) {
			[self setCommand:[dict[@"command"] description]];
		}
		if (dict[@"invitedYou"]) {
			_invitedYou = [dict[@"invitedYou"] boolValue];
		}
		if (MSGObject(dict[@"gecos"])) {
			[self setGecos:[dict[@"gecos"] description]];
		}
		if (dict[@"account"]) {
			_account = [dict[@"account"] boolValue];
		}
		if (dict[@"users"] && [dict[@"users"] isKindOfClass:[NSArray class]]) {
			NSMutableArray *u = [[NSMutableArray alloc] init];
			for (id n in dict[@"users"]) {
				[u addObject:[n description]];
			}
			_users = u;
		}
		if (MSGObject(dict[@"statusmsgGroup"])) {
			[self setStatusmsgGroup:[dict[@"statusmsgGroup"] description]];
		}
		if (dict[@"params"] && [dict[@"params"] isKindOfClass:[NSArray class]]) {
			[self setParams:dict[@"params"]];
		}
		NSArray *known = @[
			@"id", @"msgid", @"text", @"type", @"time", @"from", @"target", @"hostmask",
			@"self", @"highlight", @"showInActive", @"new_nick", @"new_ident", @"new_host",
			@"ctcpMessage", @"command", @"invitedYou", @"gecos", @"account", @"users",
			@"statusmsgGroup", @"params"
		];
		NSMutableDictionary *rest = [dict mutableCopy];
		[rest removeObjectsForKeys:known];
		[_metadata release];
		_metadata = rest;
	}
	return self;
}

- (BOOL)isSelf
{
	return _self;
}

- (BOOL)isAction
{
	return _type == MSGMessageTypeAction;
}

- (BOOL)countsAsUnseen
{
	if (_self) {
		return NO;
	}
	if (_type != MSGMessageTypeMessage && _type != MSGMessageTypeAction) {
		return NO;
	}
	if (_sender == nil || [[_sender nick] length] == 0) {
		return NO;
	}
	return YES;
}

- (BOOL)isSystemMessage
{
	switch (_type) {
		case MSGMessageTypeJoin:
		case MSGMessageTypePart:
		case MSGMessageTypeQuit:
		case MSGMessageTypeNick:
		case MSGMessageTypeTopic:
		case MSGMessageTypeTopicSetBy:
		case MSGMessageTypeMode:
		case MSGMessageTypeModeChannel:
		case MSGMessageTypeModeUser:
		case MSGMessageTypeAway:
		case MSGMessageTypeBack:
		case MSGMessageTypeKick:
		case MSGMessageTypeInvite:
		case MSGMessageTypeChghost:
		case MSGMessageTypeRaw:
		case MSGMessageTypeWallops:
		case MSGMessageTypeError:
			return YES;
		default:
			return NO;
	}
}

- (NSString *)displayText
{
	if (_type == MSGMessageTypeAction && [_text length] > 0) {
		return [NSString stringWithFormat:@"%@ %@", _sender.nick, _text];
	}
	return _text;
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<MSGMessage %ld %@ %@>", (long)_identifier,
		MSGMessageTypeToString(_type), _text];
}

@end