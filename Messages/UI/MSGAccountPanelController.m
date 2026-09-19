/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGAccountPanelController.h"
#import "MSGBackend.h"
#import "MSGBackendRegistry.h"
#import "MSGLayoutMetrics.h"
#import "MSGSettingsFormView.h"

static const CGFloat MSGPanelWidth = 420.0;
static const CGFloat MSGLabelWidth = 110.0;

@interface MSGAccountPanelController ()
{
	MSGBackendRegistry *_registry;
	NSString *_backendIdentifier;
	NSPopUpButton *_backendPopUp;
	MSGSettingsFormView *_form;
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
	[window setTitle:@"New Account"];
	// The controller reuses its window across close/show cycles.
	[window setReleasedWhenClosed:NO];
	self = [super initWithWindow:window];
	[window release];
	if (self) {
		_registry = [registry retain];
	}
	return self;
}

- (void)dealloc
{
	[_registry release];
	[_backendIdentifier release];
	[_backendPopUp release];
	[_form release];
	[_statusLabel release];
	[super dealloc];
}

- (void)prepareForNewAccountWithBackend:(NSString *)backendIdentifier
{
	NSString *backend = backendIdentifier ?: [[_registry backendIdentifiers] firstObject];
	[self buildFormForBackend:backend];
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

- (NSButton *)buttonWithTitle:(NSString *)title x:(CGFloat)x action:(SEL)action
{
	NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(x,
		MSGMetricsBottomMargin + MSGMetricsStatusHeight + MSGMetricsGroupGap,
		MSGMetricsButtonWidth, MSGMetricsButtonHeight)] autorelease];
	[button setBezelStyle:NSRoundedBezelStyle];
	[button setTitle:title];
	[button setTarget:self];
	[button setAction:action];
	[button setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
	return button;
}

- (void)buildFormForBackend:(NSString *)backendIdentifier
{
	Class backend = [_registry backendClassForIdentifier:backendIdentifier];
	[_backendIdentifier release];
	_backendIdentifier = [backendIdentifier copy];
	NSArray *fields = [backend accountSettingFields] ?: @[];
	CGFloat contentWidth = MSGPanelWidth - 2.0 * MSGMetricsSideMargin;

	// Service row, the form, a 20px gap, the buttons and the status line.
	CGFloat formHeight = [MSGSettingsFormView heightForFields:fields];
	CGFloat height = MSGMetricsTopMargin + MSGMetricsFieldHeight
		+ ([fields count] ? MSGMetricsControlGap + formHeight : 0.0)
		+ 20.0 + MSGMetricsButtonHeight + MSGMetricsGroupGap
		+ MSGMetricsStatusHeight + MSGMetricsBottomMargin;

	// Keep the top edge in place while the height follows the backend.
	// The window manager ignores size changes of a window on screen, which
	// left the form laid out for a taller window and the buttons over its
	// last row; a window taken off screen gets the new size when it returns.
	NSWindow *window = [self window];
	BOOL visible = [window isVisible];
	if (visible) {
		[window orderOut:self];
	}
	NSRect content = [window contentRectForFrameRect:[window frame]];
	CGFloat top = NSMaxY(content);
	content.size = NSMakeSize(MSGPanelWidth, height);
	content.origin.y = top - height;
	[window setFrame:[window frameRectForContentRect:content] display:NO];

	NSView *view = [[[NSView alloc] initWithFrame:
		NSMakeRect(0, 0, MSGPanelWidth, height)] autorelease];
	[window setContentView:view];

	CGFloat fieldX = MSGMetricsSideMargin + MSGLabelWidth + MSGMetricsControlGap;
	CGFloat y = height - MSGMetricsTopMargin - MSGMetricsFieldHeight;
	[view addSubview:[self labelWithTitle:@"Service:" frame:NSMakeRect(
		MSGMetricsSideMargin, y + 3.0, MSGLabelWidth, MSGMetricsLabelHeight)]];
	[_backendPopUp release];
	_backendPopUp = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(fieldX, y,
		MSGPanelWidth - MSGMetricsSideMargin - fieldX, MSGMetricsFieldHeight)
		pullsDown:NO];
	for (NSString *identifier in [_registry backendIdentifiers]) {
		[_backendPopUp addItemWithTitle:[_registry displayNameForBackend:identifier]];
		[[_backendPopUp lastItem] setRepresentedObject:identifier];
	}
	[_backendPopUp selectItemAtIndex:
		[_backendPopUp indexOfItemWithRepresentedObject:backendIdentifier]];
	[_backendPopUp setTarget:self];
	[_backendPopUp setAction:@selector(backendChanged:)];
	[_backendPopUp setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
	[view addSubview:_backendPopUp];

	[_form release];
	_form = [[MSGSettingsFormView alloc] initWithFields:fields width:contentWidth
		labelWidth:MSGLabelWidth];
	[_form setFrameOrigin:NSMakePoint(MSGMetricsSideMargin,
		y - MSGMetricsControlGap - formHeight)];
	[_form setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
	[view addSubview:_form];

	NSButton *connect = [self buttonWithTitle:@"Connect"
		x:MSGPanelWidth - MSGMetricsSideMargin - MSGMetricsButtonWidth
		action:@selector(connect:)];
	[connect setKeyEquivalent:@"\r"];
	[view addSubview:connect];
	NSButton *cancel = [self buttonWithTitle:@"Cancel"
		x:NSMinX([connect frame]) - MSGMetricsGroupGap - MSGMetricsButtonWidth
		action:@selector(cancel:)];
	[cancel setKeyEquivalent:@"\e"];
	[view addSubview:cancel];

	[_statusLabel release];
	_statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(MSGMetricsSideMargin,
		MSGMetricsBottomMargin, contentWidth, MSGMetricsStatusHeight)];
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

	[_backendPopUp setNextKeyView:[_form firstControl] ?: (NSView *)connect];
	[[_form lastControl] setNextKeyView:cancel];
	[cancel setNextKeyView:connect];
	[connect setNextKeyView:_backendPopUp];
	[window makeFirstResponder:[_form firstEmptyControl] ?: (NSView *)_backendPopUp];
	if (visible) {
		[window makeKeyAndOrderFront:self];
	}
}

#pragma mark - Actions

- (void)backendChanged:(id)sender
{
	NSString *identifier = [[_backendPopUp selectedItem] representedObject];
	if (![identifier isEqualToString:_backendIdentifier]) {
		[self buildFormForBackend:identifier];
	}
}

- (void)connect:(id)sender
{
	NSString *missing = [_form missingRequiredFieldLabel];
	if (missing != nil) {
		[self setStatusText:[NSString stringWithFormat:@"Please fill in %@.", missing]];
		return;
	}
	NSDictionary *settings = [_form settingsByMergingInto:@{}];
	Class backend = [_registry backendClassForIdentifier:_backendIdentifier];
	if ([backend respondsToSelector:@selector(validationErrorForSettings:)]) {
		NSString *problem = [backend validationErrorForSettings:settings];
		if (problem != nil) {
			[self setStatusText:problem];
			return;
		}
	}
	[self setStatusText:@"Connecting..."];
	[_delegate accountPanel:self didSubmitBackend:_backendIdentifier settings:settings];
}

- (void)cancel:(id)sender
{
	[self close];
}

@end
