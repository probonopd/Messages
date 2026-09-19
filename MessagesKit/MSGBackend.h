/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

// Bumped whenever MSGBackend, MSGAccount or MSGProtocol change in a way that
// breaks compiled backends. A bundle declares the version it was built
// against as MSGBackendAPIVersion in its Info.plist.
#define MSG_BACKEND_API_VERSION 1

// Keys of the dictionaries returned by +accountSettingFields.
extern NSString *const MSGSettingFieldKey;          // settings key
extern NSString *const MSGSettingFieldLabel;        // user-visible label
extern NSString *const MSGSettingFieldType;         // one of the types below
extern NSString *const MSGSettingFieldPlaceholder;  // optional
extern NSString *const MSGSettingFieldDefault;      // optional default value
extern NSString *const MSGSettingFieldRequired;     // optional NSNumber BOOL

extern NSString *const MSGSettingFieldTypeText;
extern NSString *const MSGSettingFieldTypeSecure;
extern NSString *const MSGSettingFieldTypeNumber;
extern NSString *const MSGSettingFieldTypeCheckbox;

// Keys of the dictionaries returned by +quickConnectPresets.
extern NSString *const MSGPresetTitle;
extern NSString *const MSGPresetSettings;

// The principal class of a .msgbackend bundle. Everything is class-side: the
// backend describes itself and creates accounts; it holds no state.
@protocol MSGBackend <NSObject>

+ (NSString *)backendIdentifier;
+ (NSString *)displayName;
// An MSGAccount subclass.
+ (Class)accountClass;
// The settings the user enters to create an account, in display order. The
// app renders them as a form, so backends need no AppKit code.
+ (NSArray *)accountSettingFields;

@optional
// A human-readable problem with `settings`, or nil when they can be used.
+ (NSString *)validationErrorForSettings:(NSDictionary *)settings;
// Ready-made accounts offered as one-click menu items.
+ (NSArray *)quickConnectPresets;

@end
