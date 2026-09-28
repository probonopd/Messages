/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGInputTextView.h"

// The one font the whole window shares.  GNUstep takes a zero font size
// literally, so the default size is asked for by name.
static NSFont *MSGComposerFont(void)
{
	return [NSFont systemFontOfSize:[NSFont systemFontSize]];
}

@implementation MSGInputTextView

// Every other text in the app asks for this font itself.  The composer did
// not, so it kept NSTextView's process-wide default typing attributes, which
// are built once from +[NSFont userFontOfSize:0].  That is the one font entry
// point the desktop's font behaviours leave unenforced, so the resolved face
// is whatever fontconfig picks and the composer ended up drawn in a different
// weight from the rest of the window - bold here - with nothing in the app
// able to predict or override it.
- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		// -setFont: covers the typing attributes too, so text typed later
		// uses the same font as the text already in the box.
		[self setFont:MSGComposerFont()];
	}
	return self;
}

- (void)setSendTarget:(id)target action:(SEL)action
{
	_sendTarget = target;
	_sendAction = action;
}

- (void)insertNewline:(id)sender
{
	NSEvent *event = [NSApp currentEvent];
	if (event && ([event modifierFlags] & NSShiftKeyMask)) {
		[super insertNewline:sender];
		// The composer height follows the typed lines; the notification
		// the text system would post for programmatic edits is skipped,
		// so nudge the delegate here.
		if ([_delegate respondsToSelector:@selector(textDidChange:)]) {
			[(id)_delegate textDidChange:
			    [NSNotification notificationWithName:NSTextDidChangeNotification
			                                object:self]];
		}
		return;
	}
	if (_sendTarget && _sendAction) {
		[NSApp sendAction:_sendAction to:_sendTarget from:self];
	}
}

@end
