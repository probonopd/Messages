/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "MSGConnectingView.h"
#import "MSGAccount.h"
#import "MSGLayoutMetrics.h"

static const CGFloat MSGConnectingBarWidth = 240.0;
static const CGFloat MSGConnectingBarHeight = 20.0;

@interface MSGConnectingView ()
{
	NSTextField *_label;
	NSProgressIndicator *_progress;
}
@end

@implementation MSGConnectingView

+ (NSString *)messageForAccounts:(NSArray *)accounts hasNetworks:(BOOL)hasNetworks
{
	if (hasNetworks) {
		return nil;
	}
	NSMutableArray *busy = [NSMutableArray array];
	for (MSGAccount *account in accounts) {
		switch (account.state) {
			case MSGConnectionStateConnecting:
			case MSGConnectionStateTransportConnected:
			case MSGConnectionStateSocketConnected:
			case MSGConnectionStateAuthenticating:
			case MSGConnectionStateInitializing:
			case MSGConnectionStateReconnecting:
				[busy addObject:account];
				break;
			default:
				break;
		}
	}
	if ([busy count] == 0) {
		return nil;
	}
	if ([busy count] > 1) {
		return @"Connecting…";
	}
	MSGAccount *account = [busy firstObject];
	NSString *format = (account.state == MSGConnectionStateReconnecting)
		? @"Reconnecting to %@…" : @"Connecting to %@…";
	return [NSString stringWithFormat:format, [account displayName]];
}

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	if (self) {
		_label = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0,
			MSGConnectingBarWidth * 2.0, MSGMetricsLabelHeight)];
		[_label setEditable:NO];
		[_label setSelectable:NO];
		[_label setBezeled:NO];
		[_label setDrawsBackground:NO];
		[_label setAlignment:NSCenterTextAlignment];
		[self addSubview:_label];

		_progress = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0,
			MSGConnectingBarWidth, MSGConnectingBarHeight)];
		[_progress setStyle:NSProgressIndicatorBarStyle];
		[_progress setIndeterminate:YES];
		[_progress setDisplayedWhenStopped:NO];
		[self addSubview:_progress];
		[self layoutContent];
	}
	return self;
}

- (void)dealloc
{
	[_progress stopAnimation:self];
	[_label release];
	[_progress release];
	[super dealloc];
}

- (BOOL)isOpaque
{
	return YES;
}

- (void)drawRect:(NSRect)rect
{
	// Opaque, so the empty views underneath do not show through.
	[[NSColor windowBackgroundColor] set];
	NSRectFill(rect);
}

// The label and the bar form one group centered in the view, the label a
// small gap above the bar.
- (void)layoutContent
{
	NSRect bounds = [self bounds];
	CGFloat groupHeight = MSGMetricsLabelHeight + MSGMetricsControlGap
		+ MSGConnectingBarHeight;
	CGFloat bottom = floor(NSMidY(bounds) - groupHeight / 2.0);
	[_progress setFrame:NSMakeRect(floor(NSMidX(bounds) - MSGConnectingBarWidth / 2.0),
		bottom, MSGConnectingBarWidth, MSGConnectingBarHeight)];
	CGFloat labelWidth = MIN(NSWidth(bounds) - 2.0 * MSGMetricsSideMargin,
		MSGConnectingBarWidth * 2.0);
	[_label setFrame:NSMakeRect(floor(NSMidX(bounds) - labelWidth / 2.0),
		bottom + MSGConnectingBarHeight + MSGMetricsControlGap,
		labelWidth, MSGMetricsLabelHeight)];
}

- (void)setFrameSize:(NSSize)size
{
	[super setFrameSize:size];
	[self layoutContent];
}

// GNUstep's -setFrame: (used by autoresizing) does not go through
// -setFrameSize:.
- (void)setFrame:(NSRect)frame
{
	[super setFrame:frame];
	[self layoutContent];
}

- (void)setMessage:(NSString *)message
{
	[_label setStringValue:message ?: @""];
}

- (NSProgressIndicator *)progressIndicator
{
	return _progress;
}

// The animation runs only while the view is visible, so a hidden bar does
// not keep a timer waking the app.
- (void)setHidden:(BOOL)hidden
{
	[super setHidden:hidden];
	if (hidden) {
		[_progress stopAnimation:self];
	} else {
		[_progress startAnimation:self];
	}
}

@end
