/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

#import "MSGPreferences.h"

@class MSGAccount;
@class MSGAccountManager;
@class MSGBackendRegistry;
@class MSGSettingsFormView;

// Preferences with a General and an Accounts tab. The Accounts tab lists
// every account and edits the selected one with the same form its backend
// uses in the New Account panel; edits take effect with Apply.
@interface MSGPreferencesController : NSWindowController <NSTableViewDataSource,
	NSTableViewDelegate, NSTabViewDelegate, NSWindowDelegate>
{
	MSGAccountManager *_manager;
	MSGBackendRegistry *_registry;
	NSTabView *_tabView;
	NSButton *_bubblesCheckbox;
	NSButton *_soundCheckbox;

	NSTableView *_accountTable;
	NSButton *_addButton;
	NSButton *_removeButton;
	NSView *_detailView;
	NSTextField *_serviceValue;
	MSGSettingsFormView *_form;
	NSButton *_connectAtLaunchCheckbox;
	NSTextField *_statusValue;
	NSButton *_applyButton;
	NSButton *_revertButton;
	MSGAccount *_shownAccount;
	BOOL _dirty;
}

- (instancetype)initWithAccountManager:(MSGAccountManager *)manager
	registry:(MSGBackendRegistry *)registry;

// Brings the window up on the Accounts tab with `account` selected.
- (void)showAccount:(MSGAccount *)account;
- (BOOL)isShowingAccount:(MSGAccount *)account;
// Shows a problem of the shown account next to its settings.
- (void)showAccountError:(NSString *)message;

@end
