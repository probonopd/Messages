// Dual-Licensed, GPLv3 and Woboq GmbH's private license. See file "LICENSE"

#import <Foundation/Foundation.h>

#import "SignedId.h"

@interface AppState : NSObject


+ (void) setLastSelectedBufferId:(BufferId *)lastSelectedBufferId;
+ (BufferId*) getLastSelectedBufferId;

+ (NSUserDefaults*) preferences;

// Moved here from AppDelegate so that QuasselCoreConnection (the protocol
// engine) has no dependency on the UI layer. Both already read [AppState
// preferences]; AppDelegate was only ever a pass-through.
+ (BOOL) isBadgeForHilightsOnly:(BufferId*)bufferId;
+ (BOOL) toggleBadgeForHilightsOnly:(BufferId*)bufferId;

@end
