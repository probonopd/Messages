/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

#import "MSGChannel.h"
#import "MSGNetwork.h"
#import "MSGUser.h"
#import "MSGProtocol.h"

// What the capability-less entry points assume: the full IRC bouncer set
// the menus were modelled on.
static const MSGCapabilities MSGContextMenuAllCapabilities = (MSGCapabilities)~0UL;

@class MSGContextMenuBuilder;

// Receives the concrete actions behind context-menu items; implemented by
// the main window controller, which owns the session.
@protocol MSGContextMenuActionDelegate <NSObject>
- (void)contextMenuSwitchToChannelId:(NSInteger)channelId;
- (void)contextMenuRunCommand:(NSString *)command onChannelId:(NSInteger)channelId;
- (void)contextMenuSetMuted:(BOOL)muted forChannelId:(NSInteger)channelId;
- (void)contextMenuClearHistoryForChannelId:(NSInteger)channelId;
- (void)contextMenuCloseChannelId:(NSInteger)channelId isLobby:(BOOL)isLobby;
- (void)contextMenuJoinPromptForLobbyId:(NSInteger)lobbyId;
- (void)contextMenuEditTopicForChannelId:(NSInteger)channelId;
- (void)contextMenuForgetNetworkForChannelId:(NSInteger)channelId;
@end

@interface MSGContextMenuBuilder : NSObject

// Mirrors the web client's prefix-rank comparison used to gate the mode
// actions in the user menu: "~@" act on their own rank or below, everyone
// else strictly below.
+ (BOOL)mode:(NSString *)p1 canActOnMode:(NSString *)p2
	inSymbols:(NSArray<NSString *> *)symbols;

// "network", "channel", or "conversation" - used by the Mute labels.
+ (NSString *)humanTypeNameForChannel:(MSGChannel *)channel;

+ (NSMenu *)channelMenuForChannel:(MSGChannel *)channel
	network:(MSGNetwork *)network
	myNick:(NSString *)myNick
	delegate:(id<MSGContextMenuActionDelegate>)delegate;

+ (NSMenu *)userMenuForUser:(MSGUser *)user
	channel:(MSGChannel *)channel
	network:(MSGNetwork *)network
	myNick:(NSString *)myNick
	delegate:(id<MSGContextMenuActionDelegate>)delegate;

// As above, leaving out what the backend cannot do. The user menu is nil
// without MSGCapabilityIRCCommands.
+ (NSMenu *)channelMenuForChannel:(MSGChannel *)channel
	network:(MSGNetwork *)network
	myNick:(NSString *)myNick
	capabilities:(MSGCapabilities)capabilities
	delegate:(id<MSGContextMenuActionDelegate>)delegate;

+ (NSMenu *)userMenuForUser:(MSGUser *)user
	channel:(MSGChannel *)channel
	network:(MSGNetwork *)network
	myNick:(NSString *)myNick
	capabilities:(MSGCapabilities)capabilities
	delegate:(id<MSGContextMenuActionDelegate>)delegate;

@end
