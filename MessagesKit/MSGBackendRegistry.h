/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

// Knows the available backends. Bundles are described from their
// Info.plist alone; their code is loaded the first time a backend class is
// asked for, so unused backends cost nothing at launch.
@interface MSGBackendRegistry : NSObject

// Adds every *.msgbackend in `directory`. A bundle whose Info.plist lacks
// the required keys or declares another API version is an error: it is
// logged and not registered, never loaded on a guess.
- (void)addBackendsInDirectory:(NSString *)directory;
// Registers a backend class linked into the process (tests, tools).
- (void)registerBackendClass:(Class)backendClass;

// Sorted by display name.
- (NSArray *)backendIdentifiers;
- (NSString *)displayNameForBackend:(NSString *)identifier;
// Loads the bundle if needed; nil when unknown or when the bundle's
// principal class does not conform to MSGBackend.
- (Class)backendClassForIdentifier:(NSString *)identifier;

@end
