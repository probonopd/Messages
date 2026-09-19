/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGBackendRegistry.h"
#import "MSGBackend.h"
#import "MSGLogger.h"

static NSString *const MSGInfoIdentifierKey = @"MSGBackendIdentifier";
static NSString *const MSGInfoDisplayNameKey = @"MSGBackendDisplayName";
static NSString *const MSGInfoAPIVersionKey = @"MSGBackendAPIVersion";

@interface MSGBackendRegistry ()
{
	// identifier -> display name
	NSMutableDictionary *_displayNames;
	// identifier -> Class, for linked-in or already loaded backends
	NSMutableDictionary *_classes;
	// identifier -> NSBundle, not loaded until first use
	NSMutableDictionary *_bundles;
}
@end

@implementation MSGBackendRegistry

- (instancetype)init
{
	self = [super init];
	if (self) {
		_displayNames = [[NSMutableDictionary alloc] init];
		_classes = [[NSMutableDictionary alloc] init];
		_bundles = [[NSMutableDictionary alloc] init];
	}
	return self;
}

- (void)dealloc
{
	[_displayNames release];
	[_classes release];
	[_bundles release];
	[super dealloc];
}

- (void)addBackendsInDirectory:(NSString *)directory
{
	NSArray *entries = [[NSFileManager defaultManager]
		contentsOfDirectoryAtPath:directory error:NULL];
	for (NSString *entry in [entries sortedArrayUsingSelector:@selector(compare:)]) {
		if (![[entry pathExtension] isEqualToString:@"msgbackend"]) {
			continue;
		}
		NSString *path = [directory stringByAppendingPathComponent:entry];
		NSBundle *bundle = [NSBundle bundleWithPath:path];
		NSDictionary *info = [bundle infoDictionary];
		NSString *identifier = info[MSGInfoIdentifierKey];
		NSString *name = info[MSGInfoDisplayNameKey];
		NSInteger version = [info[MSGInfoAPIVersionKey] integerValue];
		if ([identifier length] == 0 || [name length] == 0) {
			[[MSGLogger sharedLogger] error:
				@"Backend %@ lacks %@ or %@ in its Info.plist; not loaded",
				path, MSGInfoIdentifierKey, MSGInfoDisplayNameKey];
			continue;
		}
		if (version != MSG_BACKEND_API_VERSION) {
			[[MSGLogger sharedLogger] error:
				@"Backend %@ was built for API version %ld, this is %d; not loaded",
				path, (long)version, MSG_BACKEND_API_VERSION];
			continue;
		}
		if (_displayNames[identifier] != nil) {
			[[MSGLogger sharedLogger] error:
				@"Backend %@ duplicates identifier %@; not loaded", path, identifier];
			continue;
		}
		_displayNames[identifier] = name;
		_bundles[identifier] = bundle;
	}
}

- (void)registerBackendClass:(Class)backendClass
{
	NSString *identifier = [backendClass backendIdentifier];
	_displayNames[identifier] = [backendClass displayName];
	_classes[identifier] = backendClass;
}

- (NSArray *)backendIdentifiers
{
	return [[_displayNames allKeys] sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
		return [_displayNames[a] localizedCaseInsensitiveCompare:_displayNames[b]];
	}];
}

- (NSString *)displayNameForBackend:(NSString *)identifier
{
	return _displayNames[identifier];
}

- (Class)backendClassForIdentifier:(NSString *)identifier
{
	Class cls = _classes[identifier];
	if (cls != Nil) {
		return cls;
	}
	NSBundle *bundle = _bundles[identifier];
	if (bundle == nil) {
		return Nil;
	}
	if (![bundle load]) {
		[[MSGLogger sharedLogger] error:@"Backend %@ could not be loaded",
			[bundle bundlePath]];
		return Nil;
	}
	cls = [bundle principalClass];
	if (![cls conformsToProtocol:@protocol(MSGBackend)] ||
		![[cls backendIdentifier] isEqualToString:identifier]) {
		[[MSGLogger sharedLogger] error:
			@"Backend %@: principal class %@ is not the MSGBackend %@",
			[bundle bundlePath], NSStringFromClass(cls), identifier];
		return Nil;
	}
	_classes[identifier] = cls;
	return cls;
}

@end
