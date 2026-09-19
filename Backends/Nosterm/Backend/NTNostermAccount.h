/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGAccount.h"

// A NOSTR relay. Settings: url, username (display name) and an optional
// privateKey (64 hex digits); without one the relay's stored or a freshly
// generated key is used.
@interface NTNostermAccount : MSGAccount
@end
