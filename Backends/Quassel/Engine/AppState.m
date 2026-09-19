// Dual-Licensed, GPLv3 and Woboq GmbH's private license. See file "LICENSE"

#import "AppState.h"

@implementation AppState

+ (NSUserDefaults*) preferences
{
    return [NSUserDefaults standardUserDefaults];
}

+ (BufferId*) getLastSelectedBufferId
{
    NSUserDefaults *prefs = [AppState preferences];
    int value = [prefs integerForKey:@"lastSelectedBufferId"];
    return [[BufferId alloc] initWithInt:value];
}

+ (void) setLastSelectedBufferId:(BufferId *)lastSelectedBufferId
{
    NSUserDefaults *prefs = [AppState preferences];
    [prefs setInteger:lastSelectedBufferId.intValue forKey:@"lastSelectedBufferId"];
    [prefs synchronize];
}



+ (BOOL) isBadgeForHilightsOnly:(BufferId*)bufferId
{
    NSUserDefaults *prefs = [AppState preferences];
    NSString *prefKey = [NSString stringWithFormat:@"%d.badgeForHilightsOnly", bufferId.intValue];
    NSNumber *n = [prefs objectForKey:prefKey];
    if (!n) return YES; // Default is true for channels, else we get too many notifications
    return [n boolValue];
}

+ (BOOL) toggleBadgeForHilightsOnly:(BufferId*)bufferId
{
    NSUserDefaults *prefs = [AppState preferences];
    BOOL b = ![AppState isBadgeForHilightsOnly:bufferId];
    NSString *prefKey = [NSString stringWithFormat:@"%d.badgeForHilightsOnly", bufferId.intValue];
    [prefs setBool:b forKey:prefKey];
    return b;
}

@end
