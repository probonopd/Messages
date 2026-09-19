/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGAccount.h"

// A The Lounge bouncer login. Settings: url, username, password (used once,
// never stored) and token (the session token the bouncer hands out).
@interface TLoungeAccount : MSGAccount
@end
