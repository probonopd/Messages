/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGPreferencesController.h"

// Code-built preferences panel. Layout follows the Gershwin appearance
// metrics: 24px side margins, 15px top margin, 20px bottom margin.

@implementation MSGPreferencesController

- (instancetype)init
{
	NSRect contentRect = NSMakeRect(0, 0, 380, 160);
	NSWindow *window = [[NSWindow alloc]
		initWithContentRect:contentRect
		              styleMask:(NSTitledWindowMask | NSClosableWindowMask)
		                backing:NSBackingStoreBuffered
		                  defer:NO];
	[window setTitle:@"Messages Preferences"];
	[window setReleasedWhenClosed:NO];
	[window center];

	self = [super initWithWindow:window];
	[window release];
	if (self) {
		[self buildInterface];
	}
	return self;
}

- (void)buildInterface
{
	NSView *content = [[self window] contentView];
	CGFloat width = NSWidth([content bounds]);
	const CGFloat sideMargin = 24.0;
	const CGFloat topMargin = 15.0;

	_bubblesCheckbox = [[NSButton alloc] initWithFrame:
		NSMakeRect(sideMargin, NSHeight([content bounds]) - topMargin - 18.0,
			width - 2.0 * sideMargin, 18.0)];
	[_bubblesCheckbox setButtonType:NSSwitchButton];
	[_bubblesCheckbox setTitle:@"Show chat as speech bubbles"];
	[_bubblesCheckbox setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
	[_bubblesCheckbox setTarget:self];
	[_bubblesCheckbox setAction:@selector(toggleBubbles:)];
	[_bubblesCheckbox setState:MSGPreferencesUseBubbles() ? NSOnState : NSOffState];
	[content addSubview:_bubblesCheckbox];

	_soundCheckbox = [[NSButton alloc] initWithFrame:
		NSMakeRect(sideMargin, NSHeight([content bounds]) - topMargin - 18.0 - 28.0,
			width - 2.0 * sideMargin, 18.0)];
	[_soundCheckbox setButtonType:NSSwitchButton];
	[_soundCheckbox setTitle:@"Play sound on incoming messages"];
	[_soundCheckbox setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
	[_soundCheckbox setTarget:self];
	[_soundCheckbox setAction:@selector(toggleSound:)];
	[_soundCheckbox setState:MSGPreferencesPlaySoundOnIncomingMessages() ? NSOnState : NSOffState];
	[content addSubview:_soundCheckbox];

	NSTextField *hint = [[NSTextField alloc] initWithFrame:
		NSMakeRect(sideMargin, 30.0, width - 2.0 * sideMargin, 34.0)];
	[hint setEditable:NO];
	[hint setSelectable:NO];
	[hint setBordered:NO];
	[hint setBezeled:NO];
	[hint setDrawsBackground:NO];
	[hint setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[hint setTextColor:[NSColor disabledControlTextColor]];
	[hint setStringValue:@"Renders conversations in the iChat-style Aqua look "
		@"with avatars and tails instead of a plain text log."];
	[hint setAutoresizingMask:NSViewMinYMargin | NSViewWidthSizable];
	[content addSubview:hint];
	[hint release];
}

- (void)toggleBubbles:(id)sender
{
	MSGPreferencesSetUseBubbles([_bubblesCheckbox state] == NSOnState);
}

- (void)toggleSound:(id)sender
{
	MSGPreferencesSetPlaySoundOnIncomingMessages([_soundCheckbox state] == NSOnState);
}

- (void)showWindow:(id)sender
{
	// Reflect changes made elsewhere while the panel was closed.
	[_bubblesCheckbox setState:
		MSGPreferencesUseBubbles() ? NSOnState : NSOffState];
	[_soundCheckbox setState:
		MSGPreferencesPlaySoundOnIncomingMessages() ? NSOnState : NSOffState];
	[super showWindow:sender];
}

- (void)dealloc
{
	[_bubblesCheckbox release];
	[_soundCheckbox release];
	[super dealloc];
}

@end
