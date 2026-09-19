/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

/* Standalone accounts for the live tests: no account manager, id slot 0. */

#import "MSGAccount.h"
#import "NTNostermAccount.h"
#import "TLoungeAccount.h"

static inline MSGAccount *NewNostermAccount(NSURL *url, NSString *username,
	NSString *privateKey)
{
	NSMutableDictionary *settings = [NSMutableDictionary dictionary];
	settings[@"url"] = [url absoluteString];
	settings[@"username"] = username;
	if ([privateKey length] > 0) {
		settings[@"privateKey"] = privateKey;
	}
	return [[NTNostermAccount alloc] initWithIdentifier:@"test" settings:settings];
}

static inline MSGAccount *NewLoungeAccount(NSURL *url, NSString *username,
	NSString *password)
{
	return [[TLoungeAccount alloc] initWithIdentifier:@"test" settings:@{
		@"url": [url absoluteString], @"username": username ?: @"",
		@"password": password ?: @""}];
}
