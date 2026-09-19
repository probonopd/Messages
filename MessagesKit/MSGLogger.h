/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MSGLogLevel) {
	MSGLogLevelError = 0,
	MSGLogLevelWarning = 1,
	MSGLogLevelInfo = 2,
	MSGLogLevelDebug = 3,
	MSGLogLevelTrace = 4,
};

@interface MSGLogger : NSObject

@property (nonatomic, assign) MSGLogLevel level;
@property (nonatomic, assign) BOOL protocolTraceEnabled;

+ (instancetype)sharedLogger;

- (void)log:(MSGLogLevel)level message:(NSString *)message;
- (void)error:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (void)warning:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (void)info:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (void)debug:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
- (void)trace:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);

+ (NSString *)redactSensitiveString:(NSString *)string;

@end