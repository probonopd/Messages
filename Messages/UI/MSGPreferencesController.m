/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGPreferencesController.h"

#import "MSGAccount.h"
#import "MSGAccountManager.h"
#import "MSGBackend.h"
#import "MSGBackendRegistry.h"
#import "MSGApplicationDelegate.h"
#import "MSGLayoutMetrics.h"
#import "MSGSettingsFormView.h"

static const CGFloat MSGPrefsWidth = 620.0;
static const CGFloat MSGPrefsHeight = 420.0;
// Inside a tab the content is inset less than in a window: the tab view's
// own bezel already separates it from the window edge.
static const CGFloat MSGTabInset = 16.0;
static const CGFloat MSGAccountListWidth = 180.0;
static const CGFloat MSGDetailLabelWidth = 100.0;

static NSString *const MSGGeneralTab = @"General";
static NSString *const MSGAccountsTab = @"Accounts";

@implementation MSGPreferencesController

- (instancetype)initWithAccountManager:(MSGAccountManager *)manager
	registry:(MSGBackendRegistry *)registry
{
	NSWindow *window = [[NSWindow alloc]
		initWithContentRect:NSMakeRect(0, 0, MSGPrefsWidth, MSGPrefsHeight)
		styleMask:(NSTitledWindowMask | NSClosableWindowMask)
		backing:NSBackingStoreBuffered defer:NO];
	[window setTitle:@"Messages Preferences"];
	// The controller reuses its window across close/show cycles.
	[window setReleasedWhenClosed:NO];
	[window center];

	self = [super initWithWindow:window];
	[window release];
	if (self) {
		_manager = [manager retain];
		_registry = [registry retain];
		[window setDelegate:self];
		[self buildInterface];
		NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
		[center addObserver:self selector:@selector(accountListDidChange:)
			name:MSGAccountListDidChangeNotification object:_manager];
		[center addObserver:self selector:@selector(accountStateDidChange:)
			name:MSGAccountStateDidChangeNotification object:nil];
		[center addObserver:self selector:@selector(formDidChange:)
			name:MSGSettingsFormViewDidChangeNotification object:nil];
	}
	return self;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_manager release];
	[_registry release];
	[_tabView release];
	[_bubblesCheckbox release];
	[_soundCheckbox release];
	[_accountTable release];
	[_addButton release];
	[_removeButton release];
	[_detailView release];
	[_serviceValue release];
	[_form release];
	[_connectAtLaunchCheckbox release];
	[_statusValue release];
	[_applyButton release];
	[_revertButton release];
	[_shownAccount release];
	[super dealloc];
}

#pragma mark - Building

- (NSTextField *)labelWithTitle:(NSString *)title frame:(NSRect)frame
	alignment:(NSTextAlignment)alignment
{
	NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
	[label setStringValue:title];
	[label setEditable:NO];
	[label setSelectable:NO];
	[label setBezeled:NO];
	[label setDrawsBackground:NO];
	[label setAlignment:alignment];
	[label setAutoresizingMask:NSViewMinYMargin];
	return [label autorelease];
}

- (NSButton *)pushButtonWithTitle:(NSString *)title frame:(NSRect)frame
	action:(SEL)action
{
	NSButton *button = [[NSButton alloc] initWithFrame:frame];
	[button setBezelStyle:NSRoundedBezelStyle];
	[button setTitle:title];
	[button setTarget:self];
	[button setAction:action];
	return button;
}

// Tab item views are sized from the tab view's content rect so rows laid
// out from the top land inside the visible area.
- (NSView *)addTabWithIdentifier:(NSString *)identifier
{
	NSTabViewItem *item = [[[NSTabViewItem alloc] initWithIdentifier:identifier]
		autorelease];
	[item setLabel:identifier];
	NSRect contentRect = [_tabView contentRect];
	NSView *view = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0,
		NSWidth(contentRect), NSHeight(contentRect))] autorelease];
	[view setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[item setView:view];
	[_tabView addTabViewItem:item];
	return view;
}

- (void)buildInterface
{
	NSView *content = [[self window] contentView];
	CGFloat width = NSWidth([[self window] contentRectForFrameRect:[[self window] frame]]);
	_tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(MSGMetricsGroupGap,
		MSGMetricsGroupGap, width - 2.0 * MSGMetricsGroupGap,
		MSGPrefsHeight - MSGMetricsGroupGap - MSGMetricsGroupGap)];
	[_tabView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[_tabView setDelegate:self];
	[content addSubview:_tabView];

	[self buildGeneralTab:[self addTabWithIdentifier:MSGGeneralTab]];
	[self buildAccountsTab:[self addTabWithIdentifier:MSGAccountsTab]];
}

- (NSButton *)checkboxWithTitle:(NSString *)title y:(CGFloat)y width:(CGFloat)width
	action:(SEL)action
{
	NSButton *box = [[NSButton alloc] initWithFrame:NSMakeRect(MSGTabInset, y,
		width - 2.0 * MSGTabInset, MSGMetricsCheckboxHeight)];
	[box setButtonType:NSSwitchButton];
	[box setTitle:title];
	[box setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
	[box setTarget:self];
	[box setAction:action];
	return box;
}

- (void)buildGeneralTab:(NSView *)view
{
	CGFloat width = NSWidth([view frame]);
	CGFloat y = NSHeight([view frame]) - MSGTabInset - MSGMetricsCheckboxHeight;

	_bubblesCheckbox = [self checkboxWithTitle:@"Show chat as speech bubbles"
		y:y width:width action:@selector(toggleBubbles:)];
	[view addSubview:_bubblesCheckbox];

	NSTextField *hint = [self labelWithTitle:@"Shows conversations as speech "
		@"bubbles next to the participants' pictures instead of a plain text log."
		frame:NSMakeRect(MSGTabInset + 20.0, y - 34.0,
			width - 2.0 * MSGTabInset - 20.0, 30.0)
		alignment:NSLeftTextAlignment];
	[hint setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[hint setTextColor:[NSColor disabledControlTextColor]];
	[hint setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
	[view addSubview:hint];

	y -= 34.0 + MSGMetricsGroupGap + MSGMetricsCheckboxHeight;
	_soundCheckbox = [self checkboxWithTitle:@"Play sound on incoming messages"
		y:y width:width action:@selector(toggleSound:)];
	[view addSubview:_soundCheckbox];
}

- (void)buildAccountsTab:(NSView *)view
{
	CGFloat width = NSWidth([view frame]);
	CGFloat height = NSHeight([view frame]);

	// Account list with the +/- buttons butting against its bottom edge.
	CGFloat buttonsY = MSGTabInset;
	CGFloat listY = buttonsY + MSGMetricsButtonHeight;
	NSScrollView *scroll = [[[NSScrollView alloc] initWithFrame:
		NSMakeRect(MSGTabInset, listY, MSGAccountListWidth,
			height - MSGTabInset - listY)] autorelease];
	[scroll setHasVerticalScroller:YES];
	[scroll setBorderType:NSBezelBorder];
	[scroll setAutoresizingMask:NSViewHeightSizable];
	_accountTable = [[NSTableView alloc] initWithFrame:[[scroll contentView] bounds]];
	NSTableColumn *column = [[[NSTableColumn alloc] initWithIdentifier:@"account"]
		autorelease];
	[[column headerCell] setStringValue:@"Accounts"];
	[column setWidth:MSGAccountListWidth - 4.0];
	[column setEditable:NO];
	[_accountTable addTableColumn:column];
	[_accountTable setDataSource:self];
	[_accountTable setDelegate:self];
	[_accountTable setAllowsEmptySelection:YES];
	[_accountTable setAllowsMultipleSelection:NO];
	[scroll setDocumentView:_accountTable];
	[view addSubview:scroll];

	_addButton = [[NSButton alloc] initWithFrame:NSMakeRect(MSGTabInset, buttonsY,
		MSGMetricsSmallButtonWidth, MSGMetricsButtonHeight)];
	[_addButton setBezelStyle:NSRegularSquareBezelStyle];
	[_addButton setTitle:@"+"];
	[_addButton setTarget:self];
	[_addButton setAction:@selector(addAccount:)];
	[_addButton setAutoresizingMask:NSViewMaxYMargin];
	[view addSubview:_addButton];
	// One pixel of overlap so the two outlines form a single line.
	_removeButton = [[NSButton alloc] initWithFrame:NSMakeRect(
		MSGTabInset + MSGMetricsSmallButtonWidth - 1.0, buttonsY,
		MSGMetricsSmallButtonWidth, MSGMetricsButtonHeight)];
	[_removeButton setBezelStyle:NSRegularSquareBezelStyle];
	[_removeButton setTitle:@"-"];
	[_removeButton setTarget:self];
	[_removeButton setAction:@selector(removeAccount:)];
	[_removeButton setAutoresizingMask:NSViewMaxYMargin];
	[view addSubview:_removeButton];

	CGFloat detailX = MSGTabInset + MSGAccountListWidth + MSGTabInset;
	_detailView = [[NSView alloc] initWithFrame:NSMakeRect(detailX, 0,
		width - detailX - MSGTabInset, height)];
	[_detailView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[view addSubview:_detailView];

	CGFloat detailW = NSWidth([_detailView frame]);
	_applyButton = [self pushButtonWithTitle:@"Apply"
		frame:NSMakeRect(detailW - MSGMetricsButtonWidth, buttonsY,
			MSGMetricsButtonWidth, MSGMetricsButtonHeight)
		action:@selector(applyChanges:)];
	[_applyButton setKeyEquivalent:@"\r"];
	[_applyButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
	[_detailView addSubview:_applyButton];
	_revertButton = [self pushButtonWithTitle:@"Revert"
		frame:NSMakeRect(NSMinX([_applyButton frame]) - MSGMetricsGroupGap
			- MSGMetricsButtonWidth, buttonsY,
			MSGMetricsButtonWidth, MSGMetricsButtonHeight)
		action:@selector(revertChanges:)];
	[_revertButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
	[_detailView addSubview:_revertButton];

	[self reloadAccounts];
}

// The rows that depend on the backend are rebuilt for each account: the
// service line, the backend's form, Connect at launch and the status.
- (void)rebuildDetailForAccount:(MSGAccount *)account
{
	for (NSView *subview in [[[_detailView subviews] copy] autorelease]) {
		if (subview != _applyButton && subview != _revertButton) {
			[subview removeFromSuperview];
		}
	}
	[_form release];
	_form = nil;
	[_serviceValue release];
	_serviceValue = nil;
	[_connectAtLaunchCheckbox release];
	_connectAtLaunchCheckbox = nil;
	[_statusValue release];
	_statusValue = nil;
	if (account == nil) {
		[_applyButton setHidden:YES];
		[_revertButton setHidden:YES];
		return;
	}
	[_applyButton setHidden:NO];
	[_revertButton setHidden:NO];

	CGFloat width = NSWidth([_detailView frame]);
	CGFloat valueX = MSGDetailLabelWidth + MSGMetricsControlGap;
	CGFloat y = NSHeight([_detailView frame]) - MSGTabInset - MSGMetricsFieldHeight;

	[_detailView addSubview:[self labelWithTitle:@"Service:"
		frame:NSMakeRect(0, y + 3.0, MSGDetailLabelWidth, MSGMetricsLabelHeight)
		alignment:NSRightTextAlignment]];
	_serviceValue = [[self labelWithTitle:[_registry displayNameForBackend:
			account.backendIdentifier] ?: account.backendIdentifier
		frame:NSMakeRect(valueX, y + 3.0, width - valueX, MSGMetricsLabelHeight)
		alignment:NSLeftTextAlignment] retain];
	[_serviceValue setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
	[_detailView addSubview:_serviceValue];

	Class backend = [_registry backendClassForIdentifier:account.backendIdentifier];
	NSArray *fields = [backend accountSettingFields] ?: @[];
	_form = [[MSGSettingsFormView alloc] initWithFields:fields width:width
		labelWidth:MSGDetailLabelWidth];
	y -= MSGMetricsRowStep;
	[_form setFrameOrigin:NSMakePoint(0, y + MSGMetricsFieldHeight - NSHeight([_form frame]))];
	[_form setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
	[_detailView addSubview:_form];
	y = NSMinY([_form frame]) - MSGMetricsGroupGap - MSGMetricsCheckboxHeight;

	_connectAtLaunchCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(valueX, y,
		width - valueX, MSGMetricsCheckboxHeight)];
	[_connectAtLaunchCheckbox setButtonType:NSSwitchButton];
	[_connectAtLaunchCheckbox setTitle:@"Connect when Messages starts"];
	[_connectAtLaunchCheckbox setTarget:self];
	[_connectAtLaunchCheckbox setAction:@selector(formDidChange:)];
	[_connectAtLaunchCheckbox setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
	[_detailView addSubview:_connectAtLaunchCheckbox];

	y -= MSGMetricsGroupGap + MSGMetricsLabelHeight;
	[_detailView addSubview:[self labelWithTitle:@"Status:"
		frame:NSMakeRect(0, y, MSGDetailLabelWidth, MSGMetricsLabelHeight)
		alignment:NSRightTextAlignment]];
	_statusValue = [[self labelWithTitle:@""
		frame:NSMakeRect(valueX, y - 2.0 * MSGMetricsLabelHeight, width - valueX,
			3.0 * MSGMetricsLabelHeight)
		alignment:NSLeftTextAlignment] retain];
	[_statusValue setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
	[_detailView addSubview:_statusValue];

	[self loadDetailFromAccount:account];
}

- (void)loadDetailFromAccount:(MSGAccount *)account
{
	[_form setSettings:account.settings];
	[_connectAtLaunchCheckbox setState:[account connectsAtLaunch] ? NSOnState : NSOffState];
	[self updateStatus];
	[self setDirty:NO];
}

- (void)updateStatus
{
	if (_shownAccount == nil || _statusValue == nil) {
		return;
	}
	[_statusValue setTextColor:[NSColor controlTextColor]];
	[_statusValue setStringValue:MSGConnectionStateDisplayString(_shownAccount.state)];
}

- (void)setDirty:(BOOL)dirty
{
	_dirty = dirty;
	[_applyButton setEnabled:dirty];
	[_revertButton setEnabled:dirty];
}

#pragma mark - Public

- (void)showAccount:(MSGAccount *)account
{
	[self showWindow:self];
	[_tabView selectTabViewItemWithIdentifier:MSGAccountsTab];
	NSUInteger row = [_manager.accounts indexOfObjectIdenticalTo:account];
	if (row != NSNotFound) {
		[_accountTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
			byExtendingSelection:NO];
	}
	[[self window] makeKeyAndOrderFront:self];
}

- (BOOL)isShowingAccount:(MSGAccount *)account
{
	return [[self window] isVisible] && _shownAccount == account &&
		[[[_tabView selectedTabViewItem] identifier] isEqual:MSGAccountsTab];
}

- (void)showAccountError:(NSString *)message
{
	[_statusValue setTextColor:[NSColor colorWithCalibratedRed:0.75
		green:0.15 blue:0.10 alpha:1.0]];
	[_statusValue setStringValue:message ?: @""];
}

- (void)showWindow:(id)sender
{
	// Reflect changes made elsewhere while the window was closed.
	[_bubblesCheckbox setState:MSGPreferencesUseBubbles() ? NSOnState : NSOffState];
	[_soundCheckbox setState:
		MSGPreferencesPlaySoundOnIncomingMessages() ? NSOnState : NSOffState];
	[self reloadAccounts];
	[super showWindow:sender];
}

#pragma mark - General

- (void)toggleBubbles:(id)sender
{
	MSGPreferencesSetUseBubbles([_bubblesCheckbox state] == NSOnState);
}

- (void)toggleSound:(id)sender
{
	MSGPreferencesSetPlaySoundOnIncomingMessages([_soundCheckbox state] == NSOnState);
}

#pragma mark - Accounts

- (void)reloadAccounts
{
	[_accountTable reloadData];
	NSUInteger row = _shownAccount
		? [_manager.accounts indexOfObjectIdenticalTo:_shownAccount] : NSNotFound;
	if (row == NSNotFound && [_manager.accounts count] > 0) {
		row = 0;
	}
	if (row != NSNotFound) {
		[_accountTable selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
			byExtendingSelection:NO];
	} else {
		[_accountTable deselectAll:self];
	}
	[self showSelectedAccount];
}

- (void)showSelectedAccount
{
	NSInteger row = [_accountTable selectedRow];
	NSArray *accounts = _manager.accounts;
	MSGAccount *account = (row >= 0 && row < (NSInteger)[accounts count])
		? accounts[(NSUInteger)row] : nil;
	[_removeButton setEnabled:account != nil];
	if (account == _shownAccount && _form != nil) {
		return;
	}
	[account retain];
	[_shownAccount release];
	_shownAccount = account;
	[self rebuildDetailForAccount:account];
}

- (void)accountListDidChange:(NSNotification *)notification
{
	[self reloadAccounts];
}

- (void)accountStateDidChange:(NSNotification *)notification
{
	[_accountTable reloadData];
	if (notification.object == _shownAccount) {
		[self updateStatus];
	}
}

- (void)formDidChange:(id)sender
{
	if ([sender isKindOfClass:[NSNotification class]] &&
		[(NSNotification *)sender object] != _form) {
		return;
	}
	[self setDirty:YES];
}

- (void)addAccount:(id)sender
{
	[(MSGApplicationDelegate *)[NSApp delegate] newAccount:sender];
}

- (void)removeAccount:(id)sender
{
	MSGAccount *account = _shownAccount;
	if (account == nil) {
		return;
	}
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:[NSString stringWithFormat:
		@"Remove the account \"%@\"?", [account displayName]]];
	[alert setInformativeText:@"Its settings are deleted from this computer. "
		@"Nothing is deleted on the server."];
	[alert addButtonWithTitle:@"Remove"];
	[alert addButtonWithTitle:@"Cancel"];
	if ([alert runModal] != NSAlertFirstButtonReturn) {
		return;
	}
	[self setDirty:NO];
	[_manager removeAccount:account];
}

// Applies the form to the shown account; returns NO and says why in the
// status line when the settings cannot be used.
- (BOOL)applyChanges:(id)sender
{
	MSGAccount *account = _shownAccount;
	if (account == nil || !_dirty) {
		return YES;
	}
	NSString *missing = [_form missingRequiredFieldLabel];
	if (missing != nil) {
		[self showAccountError:[NSString stringWithFormat:@"Please fill in %@.", missing]];
		return NO;
	}
	NSMutableDictionary *settings = [[[_form settingsByMergingInto:account.settings]
		mutableCopy] autorelease];
	settings[MSGAccountConnectAtLaunchKey] =
		@([_connectAtLaunchCheckbox state] == NSOnState);
	Class backend = [_registry backendClassForIdentifier:account.backendIdentifier];
	if ([backend respondsToSelector:@selector(validationErrorForSettings:)]) {
		NSString *problem = [backend validationErrorForSettings:settings];
		if (problem != nil) {
			[self showAccountError:problem];
			return NO;
		}
	}
	// updateSettings: merges; keys the form cleared are removed explicitly.
	NSMutableDictionary *update = [NSMutableDictionary dictionaryWithDictionary:settings];
	for (id key in account.settings) {
		if (settings[key] == nil) {
			update[key] = [NSNull null];
		}
	}
	// A connected (or failing) account picks the new settings up at once;
	// one the user took offline stays offline.
	BOOL reconnect = (account.state != MSGConnectionStateDisconnected);
	if (reconnect) {
		[account disconnect];
	}
	[account updateSettings:update];
	// New settings have not worked yet: a failure is reported here instead
	// of being retried silently like a dropped connection.
	[account setEstablished:NO];
	[self setDirty:NO];
	[_accountTable reloadData];
	if (reconnect) {
		[account connect];
	}
	[self updateStatus];
	return YES;
}

- (void)revertChanges:(id)sender
{
	[self loadDetailFromAccount:_shownAccount];
}

// Asks what to do with unapplied edits; YES when the caller may go on.
- (BOOL)resolveUnappliedChanges
{
	if (!_dirty || _shownAccount == nil) {
		return YES;
	}
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:[NSString stringWithFormat:
		@"Apply the changes to \"%@\"?", [_shownAccount displayName]]];
	[alert setInformativeText:@"Your changes are lost if you don't apply them."];
	[alert addButtonWithTitle:@"Apply"];
	[alert addButtonWithTitle:@"Cancel"];
	[alert addButtonWithTitle:@"Don't Apply"];
	NSInteger choice = [alert runModal];
	if (choice == NSAlertFirstButtonReturn) {
		return [self applyChanges:self];
	}
	if (choice == NSAlertThirdButtonReturn) {
		[self loadDetailFromAccount:_shownAccount];
		return YES;
	}
	return NO;
}

#pragma mark - NSTableViewDataSource / Delegate

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[_manager.accounts count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column
	row:(NSInteger)row
{
	NSArray *accounts = _manager.accounts;
	if (row < 0 || row >= (NSInteger)[accounts count]) {
		return nil;
	}
	return [accounts[(NSUInteger)row] displayName];
}

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)tableView
{
	return [self resolveUnappliedChanges];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
	[self showSelectedAccount];
}

#pragma mark - NSTabViewDelegate / NSWindowDelegate

- (BOOL)tabView:(NSTabView *)tabView shouldSelectTabViewItem:(NSTabViewItem *)item
{
	return [self resolveUnappliedChanges];
}

- (BOOL)windowShouldClose:(id)sender
{
	return [self resolveUnappliedChanges];
}

@end
