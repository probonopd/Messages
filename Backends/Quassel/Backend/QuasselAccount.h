/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "MSGAccount.h"

// A Quassel core login. Settings: host, port (default 4242), username and
// password. The legacy Quassel protocol has no session tokens, so the
// password is stored with the account.
@interface QuasselAccount : MSGAccount
@end
