/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class MSGAccountPanelController;
@class MSGBackendRegistry;
@class MSGAccount;

@protocol MSGAccountPanelDelegate <NSObject>
// `account` is the account being edited, or nil for a new one.
- (void)accountPanel:(MSGAccountPanelController *)panel
	didSubmitBackend:(NSString *)backendIdentifier
	settings:(NSDictionary *)settings
	forAccount:(MSGAccount *)account;
@end

// Creates or edits an account. The form is built from the backend's
// +accountSettingFields, so every backend gets the same layout and needs no
// AppKit code of its own.
@interface MSGAccountPanelController : NSWindowController

@property (nonatomic, assign) id<MSGAccountPanelDelegate> delegate;
@property (nonatomic, readonly) MSGAccount *account;

- (instancetype)initWithRegistry:(MSGBackendRegistry *)registry;

- (void)prepareForNewAccountWithBackend:(NSString *)backendIdentifier;
- (void)prepareForEditingAccount:(MSGAccount *)account;
- (void)setStatusText:(NSString *)text;

@end
