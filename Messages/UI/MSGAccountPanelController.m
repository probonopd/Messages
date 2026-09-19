/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGAccountPanelController.h"
#import "MSGAccount.h"
#import "MSGBackend.h"
#import "MSGBackendRegistry.h"

// Gershwin appearance metrics for a labeled form.
static const CGFloat MSGPanelWidth = 420.0;
static const CGFloat MSGSideMargin = 24.0;
static const CGFloat MSGTopMargin = 15.0;
static const CGFloat MSGBottomMargin = 12.0;
static const CGFloat MSGLabelWidth = 110.0;
static const CGFloat MSGControlGap = 8.0;
static const CGFloat MSGFieldHeight = 22.0;
static const CGFloat MSGRowStep = 30.0;
static const CGFloat MSGCheckboxHeight = 18.0;
static const CGFloat MSGButtonHeight = 20.0;
static const CGFloat MSGButtonWidth = 100.0;
static const CGFloat MSGStatusHeight = 16.0;

@interface MSGAccountPanelController ()
{
	MSGBackendRegistry *_registry;
	NSString *_backendIdentifier;
	NSPopUpButton *_backendPopUp;
	// settings key -> NSTextField or NSButton
	NSMutableDictionary *_controls;
	NSArray *_fields;
	NSTextField *_statusLabel;
}
@end

@implementation MSGAccountPanelController

- (instancetype)initWithRegistry:(MSGBackendRegistry *)registry
{
	NSWindow *window = [[NSWindow alloc] initWithContentRect:
		NSMakeRect(0, 0, MSGPanelWidth, 200)
		styleMask:(NSTitledWindowMask | NSClosableWindowMask)
		backing:NSBackingStoreBuffered defer:NO];
	// The controller reuses its window across close/show cycles.
	[window setReleasedWhenClosed:NO];
	self = [super initWithWindow:window];
	[window release];
	if (self) {
		_registry = [registry retain];
		_controls = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_registry release];
	[_backendIdentifier release];
	[_backendPopUp release];
	[_controls release];
	[_fields release];
	[_statusLabel release];
	[_account release];
	[super dealloc];
}

#pragma mark - Preparing

- (void)prepareForNewAccountWithBackend:(NSString *)backendIdentifier
{
	[_account release];
	_account = nil;
	NSString *backend = backendIdentifier ?: [[_registry backendIdentifiers] firstObject];
	[self buildFormForBackend:backend settings:nil];
	[[self window] setTitle:@"New Account"];
}

- (void)prepareForEditingAccount:(MSGAccount *)account
{
	[_account release];
	_account = [account retain];
	[self buildFormForBackend:account.backendIdentifier settings:account.settings];
	[[self window] setTitle:[NSString stringWithFormat:@"Edit %@", [account displayName]]];
}

- (void)setStatusText:(NSString *)text
{
	[_statusLabel setStringValue:text ?: @""];
}

#pragma mark - Layout

- (NSTextField *)labelWithTitle:(NSString *)title frame:(NSRect)frame
{
	NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
	[label setStringValue:title];
	[label setEditable:NO];
	[label setSelectable:NO];
	[label setBezeled:NO];
	[label setDrawsBackground:NO];
	[label setAlignment:NSRightTextAlignment];
	[label setAutoresizingMask:NSViewMinYMargin];
	return [label autorelease];
}

- (CGFloat)heightForFields:(NSArray *)fields
{
	CGFloat rows = MSGRowStep * [fields count];
	// Service pop-up row, the field rows, a 20px gap, the button row and the
	// status line.
	return MSGTopMargin + MSGFieldHeight + rows + 20.0 + MSGButtonHeight
		+ MSGBottomMargin + MSGStatusHeight + MSGBottomMargin;
}

- (void)buildFormForBackend:(NSString *)backendIdentifier settings:(NSDictionary *)settings
{
	Class backend = [_registry backendClassForIdentifier:backendIdentifier];
	[_backendIdentifier release];
	_backendIdentifier = [backendIdentifier copy];
	[_fields release];
	_fields = [[backend accountSettingFields] copy] ?: [[NSArray alloc] init];
	[_controls removeAllObjects];

	NSWindow *window = [self window];
	CGFloat height = [self heightForFields:_fields];
	// Keep the top edge in place while the height follows the backend.
	NSRect frame = [window frame];
	NSRect content = [window contentRectForFrameRect:frame];
	CGFloat top = NSMaxY(content);
	content.size = NSMakeSize(MSGPanelWidth, height);
	content.origin.y = top - height;
	[window setFrame:[window frameRectForContentRect:content] display:NO];

	NSView *view = [[[NSView alloc] initWithFrame:
		NSMakeRect(0, 0, MSGPanelWidth, height)] autorelease];
	[window setContentView:view];

	CGFloat fieldX = MSGSideMargin + MSGLabelWidth + MSGControlGap;
	CGFloat fieldW = MSGPanelWidth - fieldX - MSGSideMargin;
	CGFloat y = height - MSGTopMargin - MSGFieldHeight;

	[view addSubview:[self labelWithTitle:@"Service:"
		frame:NSMakeRect(MSGSideMargin, y + 3.0, MSGLabelWidth, 17.0)]];
	[_backendPopUp release];
	_backendPopUp = [[NSPopUpButton alloc] initWithFrame:
		NSMakeRect(fieldX, y, fieldW, MSGFieldHeight) pullsDown:NO];
	for (NSString *identifier in [_registry backendIdentifiers]) {
		[_backendPopUp addItemWithTitle:[_registry displayNameForBackend:identifier]];
		[[_backendPopUp lastItem] setRepresentedObject:identifier];
	}
	[_backendPopUp selectItemAtIndex:
		[_backendPopUp indexOfItemWithRepresentedObject:backendIdentifier]];
	[_backendPopUp setTarget:self];
	[_backendPopUp setAction:@selector(backendChanged:)];
	// The backend of an existing account is fixed; its settings only make
	// sense for that backend.
	[_backendPopUp setEnabled:(_account == nil)];
	[_backendPopUp setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
	[view addSubview:_backendPopUp];

	NSView *firstControl = nil;
	NSView *previous = _backendPopUp;
	for (NSDictionary *field in _fields) {
		y -= MSGRowStep;
		NSString *key = field[MSGSettingFieldKey];
		NSString *type = field[MSGSettingFieldType];
		id value = settings[key] ?: field[MSGSettingFieldDefault];
		NSView *control;
		if ([type isEqualToString:MSGSettingFieldTypeCheckbox]) {
			NSButton *box = [[[NSButton alloc] initWithFrame:
				NSMakeRect(fieldX, y + (MSGFieldHeight - MSGCheckboxHeight) / 2.0,
					fieldW, MSGCheckboxHeight)] autorelease];
			[box setButtonType:NSSwitchButton];
			[box setTitle:field[MSGSettingFieldLabel]];
			[box setState:[value boolValue] ? NSOnState : NSOffState];
			control = box;
		} else {
			[view addSubview:[self labelWithTitle:field[MSGSettingFieldLabel]
				frame:NSMakeRect(MSGSideMargin, y + 3.0, MSGLabelWidth, 17.0)]];
			Class fieldClass = [type isEqualToString:MSGSettingFieldTypeSecure]
				? [NSSecureTextField class] : [NSTextField class];
			NSTextField *text = [[[fieldClass alloc] initWithFrame:
				NSMakeRect(fieldX, y, fieldW, MSGFieldHeight)] autorelease];
			[text setStringValue:value ? [value description] : @""];
			if (field[MSGSettingFieldPlaceholder]) {
				[text setPlaceholderString:field[MSGSettingFieldPlaceholder]];
			}
			control = text;
			if (firstControl == nil && [[text stringValue] length] == 0) {
				firstControl = text;
			}
		}
		[control setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
		[view addSubview:control];
		[previous setNextKeyView:control];
		previous = control;
		_controls[key] = control;
	}

	NSButton *connect = [[[NSButton alloc] initWithFrame:
		NSMakeRect(MSGPanelWidth - MSGSideMargin - MSGButtonWidth,
			MSGBottomMargin + MSGStatusHeight + MSGBottomMargin,
			MSGButtonWidth, MSGButtonHeight)] autorelease];
	[connect setBezelStyle:NSRoundedBezelStyle];
	[connect setTitle:@"Connect"];
	[connect setKeyEquivalent:@"\r"];
	[connect setTarget:self];
	[connect setAction:@selector(connect:)];
	[connect setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
	[view addSubview:connect];

	NSButton *cancel = [[[NSButton alloc] initWithFrame:
		NSMakeRect(NSMinX([connect frame]) - MSGControlGap - MSGButtonWidth,
			NSMinY([connect frame]), MSGButtonWidth, MSGButtonHeight)] autorelease];
	[cancel setBezelStyle:NSRoundedBezelStyle];
	[cancel setTitle:@"Cancel"];
	[cancel setKeyEquivalent:@"\e"];
	[cancel setTarget:self];
	[cancel setAction:@selector(cancel:)];
	[cancel setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
	[view addSubview:cancel];

	[_statusLabel release];
	_statusLabel = [[NSTextField alloc] initWithFrame:
		NSMakeRect(MSGSideMargin, MSGBottomMargin,
			MSGPanelWidth - 2.0 * MSGSideMargin, MSGStatusHeight)];
	[_statusLabel setEditable:NO];
	[_statusLabel setSelectable:NO];
	[_statusLabel setBezeled:NO];
	// A transparent label relies on its superview repainting behind it,
	// which misses areas under a fractional scale factor and leaves the
	// previous status text visible underneath the new one.
	[_statusLabel setDrawsBackground:YES];
	[_statusLabel setBackgroundColor:[NSColor windowBackgroundColor]];
	[_statusLabel setTextColor:[NSColor colorWithCalibratedWhite:0.30 alpha:1.0]];
	[_statusLabel setAutoresizingMask:NSViewMaxYMargin | NSViewWidthSizable];
	[view addSubview:_statusLabel];

	[previous setNextKeyView:_backendPopUp];
	[window makeFirstResponder:firstControl ?: (NSView *)_backendPopUp];
}

#pragma mark - Actions

- (void)backendChanged:(id)sender
{
	NSString *identifier = [[_backendPopUp selectedItem] representedObject];
	if (![identifier isEqualToString:_backendIdentifier]) {
		[self buildFormForBackend:identifier settings:nil];
	}
}

- (NSDictionary *)settingsFromForm
{
	NSMutableDictionary *settings = [NSMutableDictionary dictionary];
	if (_account) {
		// Keeps what the form does not show, such as a stored token.
		[settings addEntriesFromDictionary:_account.settings];
	}
	for (NSDictionary *field in _fields) {
		NSString *key = field[MSGSettingFieldKey];
		NSString *type = field[MSGSettingFieldType];
		id control = _controls[key];
		if ([type isEqualToString:MSGSettingFieldTypeCheckbox]) {
			settings[key] = @([control state] == NSOnState);
			continue;
		}
		NSString *text = [[control stringValue] stringByTrimmingCharactersInSet:
			[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if ([text length] == 0) {
			[settings removeObjectForKey:key];
		} else if ([type isEqualToString:MSGSettingFieldTypeNumber]) {
			settings[key] = @([text integerValue]);
		} else {
			settings[key] = text;
		}
	}
	return settings;
}

- (void)connect:(id)sender
{
	NSDictionary *settings = [self settingsFromForm];
	for (NSDictionary *field in _fields) {
		if ([field[MSGSettingFieldRequired] boolValue] &&
			settings[field[MSGSettingFieldKey]] == nil) {
			NSString *label = [field[MSGSettingFieldLabel]
				stringByTrimmingCharactersInSet:
					[NSCharacterSet characterSetWithCharactersInString:@":"]];
			[self setStatusText:[NSString stringWithFormat:@"Please fill in %@.", label]];
			return;
		}
	}
	Class backend = [_registry backendClassForIdentifier:_backendIdentifier];
	if ([backend respondsToSelector:@selector(validationErrorForSettings:)]) {
		NSString *problem = [backend validationErrorForSettings:settings];
		if (problem != nil) {
			[self setStatusText:problem];
			return;
		}
	}
	[self setStatusText:@"Connecting..."];
	[_delegate accountPanel:self didSubmitBackend:_backendIdentifier
		settings:settings forAccount:_account];
}

- (void)cancel:(id)sender
{
	[self close];
}

@end
