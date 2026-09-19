/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

#import "MSGMessage.h"
#import "MSGUser.h"

typedef NS_ENUM(NSInteger, MSGChannelType) {
	MSGChannelTypeChannel,
	MSGChannelTypeLobby,
	MSGChannelTypeQuery,
	MSGChannelTypeSpecial,
};

typedef NS_ENUM(NSInteger, MSGChannelState) {
	MSGChannelStateParted = 0,
	MSGChannelStateJoined = 1,
};

NSString *MSGChannelTypeToString(MSGChannelType type);
MSGChannelType MSGChannelTypeFromString(NSString *s);

@interface MSGChannel : NSObject

@property (nonatomic, assign) NSInteger identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) MSGChannelType type;
@property (nonatomic, copy) NSString *topic;
@property (nonatomic, copy) NSString *key;
@property (nonatomic, assign) NSInteger unread;
@property (nonatomic, assign) NSInteger highlight;
// Client-side "not yet seen by the user" counts, independent of the bouncer's
// unread (which the server freezes at 0 for the open channel). These grow for
// every message the user has not looked at - including the active channel
// while the window is hidden - and are cleared when the channel is viewed.
@property (nonatomic, assign) NSInteger unseen;
@property (nonatomic, assign) NSInteger unseenHighlight;
@property (nonatomic, assign) NSInteger firstUnread;
@property (nonatomic, assign) BOOL muted;
@property (nonatomic, assign) MSGChannelState state;
@property (nonatomic, copy) NSString *specialType;
@property (nonatomic, strong) id data;
@property (nonatomic, assign) BOOL closed;
@property (nonatomic, assign) NSInteger numUsers;
@property (nonatomic, assign) NSInteger totalMessages;
@property (nonatomic, strong) NSMutableArray<MSGMessage *> *messages;
@property (nonatomic, strong) NSMutableArray<MSGMessage *> *pendingMessages;
@property (nonatomic, strong) NSMutableDictionary<NSString *, MSGUser *> *users;
@property (nonatomic, strong) NSMutableDictionary *metadata;

- (instancetype)initWithDictionary:(NSDictionary *)dict;

// The unread count the UI should surface for this channel, used by both the
// sidebar badge and the Dock badge so the two can never disagree. Muted and
// lobby channels report zero because the user opted out of noticing them and
// the lobby cannot receive messages - excluding them from one but not the
// other would break the invariant that the Dock count equals the window sum.
- (NSInteger)badgeCount;

- (MSGUser *)userWithNick:(NSString *)nick;
// The one user whose nick starts with the prefix (case-insensitive); nil
// when no user or more than one user matches.
- (MSGUser *)uniqueUserWithNickPrefix:(NSString *)prefix;
- (void)addUser:(MSGUser *)user;
- (void)removeUserWithNick:(NSString *)nick;
- (NSArray<MSGUser *> *)sortedUsers;

- (MSGMessage *)messageWithIdentifier:(NSInteger)identifier;
- (void)addMessage:(MSGMessage *)message;
- (void)removeMessageWithIdentifier:(NSInteger)identifier;
- (void)prependMessages:(NSArray<MSGMessage *> *)messages;

- (void)addPendingMessage:(MSGMessage *)message;
- (void)removePendingMessage:(MSGMessage *)message;
- (void)removeAllPendingMessages;
- (BOOL)hasPendingMessages;

- (BOOL)isChannel;
- (BOOL)isQuery;
- (BOOL)isLobby;

// Whether this channel should appear in the channel outline. Queries (private
// messages) are shown regardless of joined state because the bouncer reports
// them PARTED even while they are live conversations; other channels require a
// joined state. Closed channels never appear.
- (BOOL)isVisibleInOutline;

@end