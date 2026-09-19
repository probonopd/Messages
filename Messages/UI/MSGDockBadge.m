/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGDockBadge.h"

#import <Foundation/NSConnection.h>
#import <Foundation/NSDistantObject.h>
#import <Foundation/NSPortNameServer.h>

// The Dock service registers itself under this well-known name. Kept as a
// local constant because we do not link the workspace that defines it.
static NSString * const MSGDockServiceName = @"DockIcon";

// Only fetching the root proxy waits for the Dock; a stuck Dock must not
// freeze Messages, not even while it quits.
static const NSTimeInterval MSGDockTimeout = 1.0;

@implementation MSGDockBadge
{
	NSConnection *_connection;
	id<DockService> _proxy;
	NSInteger _lastCount;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		_lastCount = -1;
		// A private connection rather than +connectionWithRegisteredName:,
		// which returns the connection and root proxy shared with everything
		// else in the process: the theme mirrors progress bars into the Dock
		// through the same service and sets its own, smaller protocol on that
		// shared proxy. Without our protocol the proxy asks the Dock for each
		// method signature and waits, which defeats oneway.
		NSPort *sendPort = [[NSPortNameServer systemDefaultPortNameServer]
			portForName:MSGDockServiceName onHost:nil];
		if (sendPort) {
			_connection = [[NSConnection alloc] initWithReceivePort:[NSPort port]
				sendPort:sendPort];
			[_connection setRequestTimeout:MSGDockTimeout];
			[_connection setReplyTimeout:MSGDockTimeout];
			@try {
				NSDistantObject *root = [_connection rootProxy];
				[root setProtocolForProxy:@protocol(DockService)];
				_proxy = (id<DockService>)[root retain];
			}
			@catch (NSException *e) {
				NSLog(@"Dock badge unavailable: %@", [e reason]);
				[_connection invalidate];
				[_connection release];
				_connection = nil;
			}
		}
	}
	return self;
}

- (void)dealloc
{
	[_proxy release];
	[_connection invalidate];
	[_connection release];
	[super dealloc];
}

- (void)sendCount:(NSInteger)count
{
	if (!_proxy || count == _lastCount) {
		return;
	}
	_lastCount = count;
	// A oneway message can still raise when the Dock's port is gone or its
	// queue is full; the badge is decoration, so give up on it then.
	@try {
		[_proxy setBadgeCount:(int64_t)count];
		[_proxy setCountVisible:(count > 0)];
	}
	@catch (NSException *e) {
		NSLog(@"Dock badge disabled: %@", [e reason]);
		[_proxy release];
		_proxy = nil;
	}
}

- (void)updateWithUnreadCount:(NSInteger)count
{
	[self sendCount:(count > 0 ? count : 0)];
}

- (void)clear
{
	[self sendCount:0];
}

@end
