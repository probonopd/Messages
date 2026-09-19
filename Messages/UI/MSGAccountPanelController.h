/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <AppKit/AppKit.h>

@class MSGAccountPanelController;
@class MSGBackendRegistry;

@protocol MSGAccountPanelDelegate <NSObject>
- (void)accountPanel:(MSGAccountPanelController *)panel
	didSubmitBackend:(NSString *)backendIdentifier
	settings:(NSDictionary *)settings;
@end

// Creates an account: a service pop-up above the backend's settings form
// (MSGSettingsFormView). Existing accounts are edited in Preferences.
@interface MSGAccountPanelController : NSWindowController

@property (nonatomic, assign) id<MSGAccountPanelDelegate> delegate;

- (instancetype)initWithRegistry:(MSGBackendRegistry *)registry;

- (void)prepareForNewAccountWithBackend:(NSString *)backendIdentifier;
- (void)setStatusText:(NSString *)text;

@end
