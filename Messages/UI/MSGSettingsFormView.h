/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>

// Posted (object: the form) whenever the user edits a control.
extern NSString *const MSGSettingsFormViewDidChangeNotification;

// The rows for a backend's +accountSettingFields: a right-aligned label
// column and one control per field, top-anchored on the 30px rhythm. Used
// by the New Account panel and by the Accounts preferences, so every
// backend's settings look the same everywhere.
@interface MSGSettingsFormView : NSView <NSTextFieldDelegate>

+ (CGFloat)heightForFields:(NSArray *)fields;

- (instancetype)initWithFields:(NSArray *)fields width:(CGFloat)width
	labelWidth:(CGFloat)labelWidth;

// Fills every control; fields missing from `settings` show their default.
- (void)setSettings:(NSDictionary *)settings;
// `base` with the form's values on top; an emptied field removes its key.
- (NSDictionary *)settingsByMergingInto:(NSDictionary *)base;
// The label (without colon) of the first required field left empty.
- (NSString *)missingRequiredFieldLabel;

- (NSView *)firstControl;
- (NSView *)lastControl;
- (NSView *)firstEmptyControl;

@end
