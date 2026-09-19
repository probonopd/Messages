/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

#import "MSGAccountPanelController.h"

@class MSGAccount;
@class MSGAccountManager;

@interface MSGApplicationDelegate : NSObject <NSApplicationDelegate,
	MSGAccountPanelDelegate>

@property (nonatomic, readonly) MSGAccountManager *accountManager;

- (void)newAccount:(id)sender;
- (void)editAccount:(MSGAccount *)account;

@end
