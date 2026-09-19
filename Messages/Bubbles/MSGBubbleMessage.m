/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGBubbleMessage.h"

@implementation MSGBubbleMessage

+ (instancetype)messageWithText:(NSString *)text
                     senderName:(NSString *)senderName
                       outgoing:(BOOL)outgoing
{
	MSGBubbleMessage *m = [[MSGBubbleMessage alloc] init];
	m.text = text;
	m.senderName = senderName;
	m.outgoing = outgoing;
	return [m autorelease];
}

+ (instancetype)dateSeparatorWithText:(NSString *)text
{
	MSGBubbleMessage *m = [[MSGBubbleMessage alloc] init];
	m.text = text;
	m.isDateSeparator = YES;
	return [m autorelease];
}

- (void)dealloc
{
	[_senderName release];
	[_text release];
	[_attributedText release];
	[_senderColor release];
	[_avatar release];
	[_timestamp release];
	[super dealloc];
}

@end
