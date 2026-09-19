/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGApplicationDelegate.h"

#import "MSGAccount.h"
#import "MSGAccountManager.h"
#import "MSGBackend.h"
#import "MSGBackendRegistry.h"
#import "MSGAccountPanelController.h"
#import "MSGMainWindowController.h"
#import "MSGPreferencesController.h"
#import "MSGPreferences.h"

@interface MSGApplicationDelegate ()
{
	MSGBackendRegistry *_registry;
	MSGAccountManager *_manager;
	MSGMainWindowController *_mainWindowController;
	MSGPreferencesController *_preferencesController;
	MSGAccountPanelController *_accountPanel;
	// The account the open panel is waiting for; a new account that fails
	// before it ever worked is removed again so a retry starts clean.
	MSGAccount *_panelAccount;
	BOOL _panelAccountIsNew;
}
@end

@implementation MSGApplicationDelegate

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_manager release];
	[_registry release];
	[_mainWindowController release];
	[_preferencesController release];
	[_accountPanel release];
	[_panelAccount release];
	[super dealloc];
}

- (MSGAccountManager *)accountManager
{
	return _manager;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
	_registry = [[MSGBackendRegistry alloc] init];
	[_registry addBackendsInDirectory:[[NSBundle mainBundle] builtInPlugInsPath]];
	_manager = [[MSGAccountManager alloc] initWithRegistry:_registry
		storagePath:[MSGApplicationSupportDirectory()
			stringByAppendingPathComponent:@"accounts.plist"]];

	NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
	[center addObserver:self selector:@selector(accountDidFail:)
		name:MSGAccountErrorNotification object:nil];
	[center addObserver:self selector:@selector(accountDidBecomeReady:)
		name:MSGAccountDidBecomeReadyNotification object:nil];

	[self buildMainMenu];

	NSError *error = nil;
	BOOL loaded = [_manager loadAccounts:&error];
	[self showMainInterface];
	if (!loaded) {
		[self showAlertWithTitle:@"Some accounts could not be restored"
			detail:[error localizedDescription]
			hint:@"They are kept and will return when their service is available again."];
	}
	if ([_manager.accounts count] == 0) {
		[self newAccount:nil];
	} else {
		[_manager connectAll];
	}
}

// Presets of all backends; loads each backend's code, which is small.
- (NSArray *)quickConnectPresets
{
	NSMutableArray *presets = [NSMutableArray array];
	for (NSString *identifier in [_registry backendIdentifiers]) {
		Class backend = [_registry backendClassForIdentifier:identifier];
		if (![backend respondsToSelector:@selector(quickConnectPresets)]) {
			continue;
		}
		for (NSDictionary *preset in [backend quickConnectPresets]) {
			NSMutableDictionary *entry = [[preset mutableCopy] autorelease];
			entry[@"backend"] = identifier;
			[presets addObject:entry];
		}
	}
	return presets;
}

- (void)buildMainMenu
{
	NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];

	// Application menu: the first submenu is treated as the app menu.
	NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"Messages"
		action:NULL keyEquivalent:@""];
	NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Messages"];
	[appMenu addItemWithTitle:@"About Messages"
		action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:@"Hide Messages"
		action:@selector(hide:) keyEquivalent:@"h"];
	[appMenu addItemWithTitle:@"Hide Others"
		action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
	[appMenu addItemWithTitle:@"Show All"
		action:@selector(unhideAllApplications:) keyEquivalent:@""];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:@"Preferences…"
		action:@selector(showPreferences:) keyEquivalent:@","];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItemWithTitle:@"Quit Messages"
		action:@selector(terminate:) keyEquivalent:@"q"];
	[appItem setSubmenu:appMenu];
	[mainMenu addItem:appItem];
	[NSApp setAppleMenu:appMenu];
	[appMenu release];
	[appItem release];

	NSMenuItem *fileItem = [[NSMenuItem alloc] initWithTitle:@"File"
		action:NULL keyEquivalent:@""];
	NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
	[fileMenu addItemWithTitle:@"Close Window"
		action:@selector(performClose:) keyEquivalent:@"w"];
	[fileItem setSubmenu:fileMenu];
	[mainMenu addItem:fileItem];
	[fileMenu release];
	[fileItem release];

	NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit"
		action:NULL keyEquivalent:@""];
	NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
	[editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
	[editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
	[editMenu addItem:[NSMenuItem separatorItem]];
	[editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
	[editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
	[editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
	[editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
	[editItem setSubmenu:editMenu];
	[mainMenu addItem:editItem];
	[editMenu release];
	[editItem release];

	// The empty View menu only confuses; drop it.
	// Window menu keeps Minimize/Zoom and doubles as the windows list.

	// Chat menu: mirrors the channel/user context menus.  Actions resolve
	// through the responder chain to the key window's controller, whose
	// validateMenuItem: enables them based on the current selection.
	NSMenuItem *chatItem = [[NSMenuItem alloc] initWithTitle:@"Chat"
		action:NULL keyEquivalent:@""];
	NSMenu *chatMenu = [[NSMenu alloc] initWithTitle:@"Chat"];

	// Account actions are owned by the app delegate; target it directly
	// because GNUstep's nil-target responder chain (firstResponder -> window
	// -> app) does not reach the app delegate.
	NSMenuItem *mi = [[NSMenuItem alloc] initWithTitle:@"New Account…"
		action:@selector(newAccount:) keyEquivalent:@""];
	[mi setTarget:self];
	[chatMenu addItem:mi];
	[mi release];
	for (NSDictionary *preset in [self quickConnectPresets]) {
		mi = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:
			@"Connect to %@", preset[MSGPresetTitle]]
			action:@selector(connectToPreset:) keyEquivalent:@""];
		[mi setTarget:self];
		[mi setRepresentedObject:preset];
		[chatMenu addItem:mi];
		[mi release];
	}
	[chatMenu addItemWithTitle:@"Edit Account…"
		action:@selector(chatEditAccount:) keyEquivalent:@""];
	[chatMenu addItemWithTitle:@"Remove Account…"
		action:@selector(chatRemoveAccount:) keyEquivalent:@""];
	[chatMenu addItem:[NSMenuItem separatorItem]];
	[chatMenu addItemWithTitle:@"Connect"
		action:@selector(chatToggleConnection:) keyEquivalent:@""];
	[chatMenu addItemWithTitle:@"Remove Network…"
		action:@selector(chatRemoveNetwork:) keyEquivalent:@""];
	[chatMenu addItem:[NSMenuItem separatorItem]];
	[chatMenu addItemWithTitle:@"Join a Channel…"
		action:@selector(chatJoinChannel:) keyEquivalent:@""];
	[chatMenu addItemWithTitle:@"List All Channels"
		action:@selector(chatListChannels:) keyEquivalent:@""];
	[chatMenu addItemWithTitle:@"List Ignored Users"
		action:@selector(chatListIgnoredUsers:) keyEquivalent:@""];
	[chatMenu addItemWithTitle:@"List Banned Users"
		action:@selector(chatListBannedUsers:) keyEquivalent:@""];
	[chatMenu addItemWithTitle:@"Edit Topic…"
		action:@selector(chatEditTopic:) keyEquivalent:@""];
	[chatMenu addItemWithTitle:@"Clear History…"
		action:@selector(chatClearHistory:) keyEquivalent:@""];
	[chatMenu addItemWithTitle:@"Mute Channel"
		action:@selector(chatToggleMuted:) keyEquivalent:@""];
	[chatMenu addItemWithTitle:@"Leave"
		action:@selector(chatCloseCurrent:) keyEquivalent:@""];
	[chatMenu addItem:[NSMenuItem separatorItem]];
	[chatMenu addItemWithTitle:@"User Information"
		action:@selector(chatWhoisSelectedUser:) keyEquivalent:@""];
	[chatMenu addItemWithTitle:@"Ignore User"
		action:@selector(chatIgnoreSelectedUser:) keyEquivalent:@""];
	[chatMenu addItemWithTitle:@"Direct Messages"
		action:@selector(chatQuerySelectedUser:) keyEquivalent:@""];

	NSMenuItem *operatorItem = [[NSMenuItem alloc] initWithTitle:@"Operator"
		action:NULL keyEquivalent:@""];
	NSMenu *operatorMenu = [[NSMenu alloc] initWithTitle:@"Operator"];
	// Standard IRC ranks; items enable only when the server actually has the
	// mode and our rank permits it (validated against PREFIX at use time).
	NSArray *ranks = @[
		@{@"mode": @"q", @"symbol": @"~", @"name": @"Owner"},
		@{@"mode": @"a", @"symbol": @"&", @"name": @"Admin"},
		@{@"mode": @"o", @"symbol": @"@", @"name": @"Operator"},
		@{@"mode": @"h", @"symbol": @"%", @"name": @"Half-op"},
		@{@"mode": @"v", @"symbol": @"+", @"name": @"Voice"}];
	for (NSDictionary *rank in ranks) {
		NSString *giveLabel = [NSString stringWithFormat:@"Give %@ (+%@)",
			rank[@"name"], rank[@"mode"]];
		NSMenuItem *give = (NSMenuItem *)[operatorMenu addItemWithTitle:giveLabel
			action:@selector(chatSetMode:) keyEquivalent:@""];
		[give setRepresentedObject:@{@"mode": rank[@"mode"],
			@"symbol": rank[@"symbol"], @"give": @YES}];
		NSString *revokeLabel = [NSString stringWithFormat:@"Revoke %@ (-%@)",
			rank[@"name"], rank[@"mode"]];
		NSMenuItem *revoke = (NSMenuItem *)[operatorMenu addItemWithTitle:revokeLabel
			action:@selector(chatSetMode:) keyEquivalent:@""];
		[revoke setRepresentedObject:@{@"mode": rank[@"mode"],
			@"symbol": rank[@"symbol"], @"give": @NO}];
	}
	[operatorItem setSubmenu:operatorMenu];
	[operatorMenu release];
	// The item is not retained until its menu adopts it, so release only
	// after it has been inserted.
	[chatMenu addItem:operatorItem];
	[operatorItem release];

	[chatMenu addItemWithTitle:@"Kick"
		action:@selector(chatKickSelectedUser:) keyEquivalent:@""];

	[chatItem setSubmenu:chatMenu];
	[mainMenu addItem:chatItem];
	[chatMenu release];
	[chatItem release];

	NSMenuItem *windowItem = [[NSMenuItem alloc] initWithTitle:@"Window"
		action:NULL keyEquivalent:@""];
	NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
	[windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:)
		keyEquivalent:@"m"];
	[windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
	[windowMenu addItem:[NSMenuItem separatorItem]];
	[windowMenu addItemWithTitle:@"Bring All to Front"
		action:@selector(arrangeInFront:) keyEquivalent:@""];
	[windowItem setSubmenu:windowMenu];
	[mainMenu addItem:windowItem];
	[NSApp setWindowsMenu:windowMenu];
	[windowMenu release];
	[windowItem release];

	[NSApp setMainMenu:mainMenu];
	[mainMenu release];
}

- (void)showPreferences:(id)sender
{
	if (!_preferencesController) {
		_preferencesController = [[MSGPreferencesController alloc] init];
	}
	[_preferencesController showWindow:self];
	[[_preferencesController window] makeKeyAndOrderFront:self];
	[NSApp activateIgnoringOtherApps:YES];
}

- (void)showMainInterface
{
	if (_mainWindowController) {
		return;
	}
	_mainWindowController = [[MSGMainWindowController alloc]
		initWithAccountManager:_manager];
	[_mainWindowController showWindow:self];
	[NSApp activateIgnoringOtherApps:YES];
}

// Quitting with the last closed window keeps the desktop tidy.
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
	return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
	// Drop the Dock badge before tearing down so no stale unread count is
	// left on the icon after the app is gone.
	[_mainWindowController clearDockBadge];
	[_manager disconnectAll];
}

#pragma mark - Accounts

- (MSGAccountPanelController *)accountPanel
{
	if (!_accountPanel) {
		_accountPanel = [[MSGAccountPanelController alloc] initWithRegistry:_registry];
		_accountPanel.delegate = self;
	}
	return _accountPanel;
}

// Centered before it is mapped: the form's height depends on the backend,
// and the window manager ignores moves of an already mapped window.
- (void)presentAccountPanel
{
	[_accountPanel setStatusText:@""];
	[[_accountPanel window] center];
	[_accountPanel showWindow:self];
	[[_accountPanel window] makeKeyAndOrderFront:self];
	[NSApp activateIgnoringOtherApps:YES];
}

- (void)setPanelAccount:(MSGAccount *)account isNew:(BOOL)isNew
{
	[account retain];
	[_panelAccount release];
	_panelAccount = account;
	_panelAccountIsNew = isNew;
}

- (void)newAccount:(id)sender
{
	[self setPanelAccount:nil isNew:NO];
	if ([[_registry backendIdentifiers] count] == 0) {
		[self showAlertWithTitle:@"No services installed"
			detail:@"Messages found no backends in its PlugIns folder."
			hint:@"Reinstall Messages."];
		return;
	}
	[[self accountPanel] prepareForNewAccountWithBackend:nil];
	[self presentAccountPanel];
}

- (void)editAccount:(MSGAccount *)account
{
	if (account == nil) {
		return;
	}
	[self setPanelAccount:nil isNew:NO];
	[[self accountPanel] prepareForEditingAccount:account];
	[self presentAccountPanel];
}

- (void)connectToPreset:(id)sender
{
	NSDictionary *preset = [sender representedObject];
	NSString *backend = preset[@"backend"];
	NSDictionary *settings = preset[MSGPresetSettings];
	// A preset that is already configured just reconnects.
	for (MSGAccount *account in _manager.accounts) {
		if ([account.backendIdentifier isEqualToString:backend] &&
			[account.settings[@"url"] isEqual:settings[@"url"]]) {
			[account connect];
			return;
		}
	}
	NSError *error = nil;
	MSGAccount *account = [_manager addAccountWithBackend:backend
		settings:settings error:&error];
	if (account == nil) {
		[self showAlertWithTitle:@"Could not add the account"
			detail:[error localizedDescription] hint:nil];
		return;
	}
	[account connect];
}

- (void)accountPanel:(MSGAccountPanelController *)panel
	didSubmitBackend:(NSString *)backendIdentifier
	settings:(NSDictionary *)settings
	forAccount:(MSGAccount *)account
{
	if (account != nil) {
		[account disconnect];
		[account updateSettings:settings];
		[self setPanelAccount:account isNew:NO];
		[account connect];
		return;
	}
	NSError *error = nil;
	MSGAccount *created = [_manager addAccountWithBackend:backendIdentifier
		settings:settings error:&error];
	if (created == nil) {
		[panel setStatusText:[error localizedDescription]];
		return;
	}
	[self setPanelAccount:created isNew:YES];
	[created connect];
}

- (void)accountDidBecomeReady:(NSNotification *)notification
{
	if (notification.object == _panelAccount) {
		[self setPanelAccount:nil isNew:NO];
		[_accountPanel close];
	}
}

- (void)accountDidFail:(NSNotification *)notification
{
	MSGAccount *account = notification.object;
	NSError *error = notification.userInfo[@"error"];
	NSString *message = [error localizedDescription];
	if ([message length] == 0) {
		message = @"The connection to the server failed.";
	}

	if (account == _panelAccount) {
		// The user is looking at the form; say it there and let them fix it.
		if (_panelAccountIsNew) {
			[_manager removeAccount:account];
		}
		[self setPanelAccount:nil isNew:NO];
		[_accountPanel setStatusText:message];
		return;
	}

	if ([notification.userInfo[@"recoverable"] boolValue]) {
		[self showAlertWithTitle:@"Connection Lost"
			detail:[NSString stringWithFormat:@"%@: %@", [account displayName], message]
			hint:@"Messages will keep trying to reconnect in the background."];
		return;
	}

	NSString *title = @"Connection Failed";
	NSString *hint = @"Check the server address and your network connection.";
	if (account.state == MSGConnectionStateAuthenticationFailed) {
		title = @"Authentication Failed";
		hint = @"Check your username and password.";
	} else if (account.state == MSGConnectionStateProtocolError) {
		title = @"Protocol Error";
		hint = @"The server sent an unexpected response. It may be running "
			"an incompatible version.";
	}
	[self showAlertWithTitle:title
		detail:[NSString stringWithFormat:@"%@: %@", [account displayName], message]
		hint:hint];
	[self editAccount:account];
}

- (void)showAlertWithTitle:(NSString *)title detail:(NSString *)detail hint:(NSString *)hint
{
	NSAlert *alert = [[NSAlert alloc] init];
	[alert setAlertStyle:NSCriticalAlertStyle];
	[alert setMessageText:title];
	NSString *text = detail ?: @"";
	if ([hint length] > 0) {
		text = [NSString stringWithFormat:@"%@\n\n%@", text, hint];
	}
	[alert setInformativeText:text];
	[alert addButtonWithTitle:@"OK"];
	[alert runModal];
	[alert release];
}

@end
