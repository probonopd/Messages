/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGLogger.h"

static MSGLogger *sharedInstance;
static NSLock *loggerLock;

@implementation MSGLogger

+ (instancetype)sharedLogger
{
	if (!loggerLock) {
		loggerLock = [[NSLock alloc] init];
	}
	[loggerLock lock];
	if (!sharedInstance) {
		sharedInstance = [[MSGLogger alloc] init];
	}
	[loggerLock unlock];
	return sharedInstance;
}

- (instancetype)init
{
	self = [super init];
	if (self) {
		_level = MSGLogLevelInfo;
		_protocolTraceEnabled = NO;
	}
	return self;
}

static NSString *MSGLevelName(MSGLogLevel level)
{
	switch (level) {
		case MSGLogLevelError:
			return @"ERROR";
		case MSGLogLevelWarning:
			return @"WARN";
		case MSGLogLevelInfo:
			return @"INFO";
		case MSGLogLevelDebug:
			return @"DEBUG";
		case MSGLogLevelTrace:
			return @"TRACE";
	}
	return @"?";
}

- (void)log:(MSGLogLevel)level message:(NSString *)message
{
	if (level > _level) {
		return;
	}
	NSLog(@"[%@] %@", MSGLevelName(level), message);
}

- (void)error:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	[self log:MSGLogLevelError message:msg];
	[msg release];
}

- (void)warning:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	[self log:MSGLogLevelWarning message:msg];
	[msg release];
}

- (void)info:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	[self log:MSGLogLevelInfo message:msg];
	[msg release];
}

- (void)debug:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	[self log:MSGLogLevelDebug message:msg];
	[msg release];
}

- (void)trace:(NSString *)format, ...
{
	va_list args;
	va_start(args, format);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	[self log:MSGLogLevelTrace message:msg];
	[msg release];
}

+ (NSString *)redactSensitiveString:(NSString *)string
{
	NSMutableString *s = [string mutableCopy];

	NSArray *patterns = @[
		@"(\"password\"\\s*:\\s*\")[^\"]*(\")",
		@"(\"token\"\\s*:\\s*\")[^\"]*(\")",
		@"(\"user\"\\s*:\\s*\")[^\"]*(\")",
		@"(password=)[^&\\s\"']+",
		@"(token=)[^&\\s\"']+",
		@"(AuthToken\\s*=\\s*)[^;\\r\\n]+",
		@"(\"sid\"\\s*:\\s*\")[^\"]*(\")",
	];

	for (NSString *pattern in patterns) {
		NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
			options:0
			error:NULL];
		NSString *replaced = [regex stringByReplacingMatchesInString:s
			options:0
			range:NSMakeRange(0, [s length])
			withTemplate:@"$1<redacted>$2"];
		s = [replaced mutableCopy];
	}

	return s;
}

@end