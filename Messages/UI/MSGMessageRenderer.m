/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "MSGMessageRenderer.h"
#import "MSGMessage.h"
#import "MSGLinkDetector.h"

#import <string.h>

static NSColor *MSGDefaultTextColor(void)
{
	// The message surface follows the light system theme, so body text
	// uses the standard label color instead of a fixed near-white.
	return [NSColor controlTextColor];
}

// Dark theme approximation used as the foreground when reverse video has no
// explicit color pair to swap into.
static NSColor *MSGReverseForegroundColor(void)
{
	return [NSColor colorWithCalibratedWhite:0.13 alpha:1.0];
}

static NSFont *MSGFontFor(BOOL bold, BOOL italic)
{
	NSFont *font = bold ? [NSFont boldSystemFontOfSize:12.0] : [NSFont systemFontOfSize:12.0];
	if (italic) {
		font = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSItalicFontMask];
	}
	return font;
}

static NSColor *MSGColorFromRGB(NSInteger r, NSInteger g, NSInteger b)
{
	return [NSColor colorWithCalibratedRed:(r / 255.0) green:(g / 255.0) blue:(b / 255.0) alpha:1.0];
}

// Standard mIRC 16 color palette shared with the The Lounge web client.
static NSColor *MSGColorForCode(NSInteger code)
{
	static NSColor *table[16] = {0};
	// Retained once so the palette outlives the autorelease pool.
	if (!table[0]) {
		table[0] = [MSGColorFromRGB(255, 255, 255) retain];
		table[1] = [MSGColorFromRGB(0, 0, 0) retain];
		table[2] = [MSGColorFromRGB(0, 0, 128) retain];
		table[3] = [MSGColorFromRGB(0, 128, 0) retain];
		table[4] = [MSGColorFromRGB(128, 0, 0) retain];
		table[5] = [MSGColorFromRGB(128, 0, 128) retain];
		table[6] = [MSGColorFromRGB(255, 128, 0) retain];
		table[7] = [MSGColorFromRGB(128, 128, 0) retain];
		table[8] = [MSGColorFromRGB(255, 255, 0) retain];
		table[9] = [MSGColorFromRGB(0, 255, 0) retain];
		table[10] = [MSGColorFromRGB(0, 128, 128) retain];
		table[11] = [MSGColorFromRGB(0, 255, 255) retain];
		table[12] = [MSGColorFromRGB(0, 0, 255) retain];
		table[13] = [MSGColorFromRGB(255, 0, 255) retain];
		table[14] = [MSGColorFromRGB(128, 128, 128) retain];
		table[15] = [MSGColorFromRGB(192, 192, 192) retain];
	}
	if (code < 0 || code > 15) {
		return MSGDefaultTextColor();
	}
	return table[code];
}

// Bright material palette that stays readable on a dark background.
static NSArray *MSGNickColorPalette(void)
{
	static NSArray *palette;
	if (!palette) {
		NSColor *colors[] = {
			MSGColorFromRGB(229, 115, 115),
			MSGColorFromRGB(240, 98, 146),
			MSGColorFromRGB(186, 104, 200),
			MSGColorFromRGB(149, 117, 205),
			MSGColorFromRGB(100, 181, 246),
			MSGColorFromRGB(77, 208, 225),
			MSGColorFromRGB(129, 199, 132),
			MSGColorFromRGB(174, 213, 129),
			MSGColorFromRGB(255, 183, 77),
			MSGColorFromRGB(255, 138, 101),
		};
		palette = [[NSArray alloc] initWithObjects:colors count:10];
	}
	return palette;
}

static NSUInteger MSGNickHash(NSString *nick)
{
	NSString *lower = [nick lowercaseString];
	NSUInteger h = 0;
	for (NSUInteger i = 0; i < [lower length]; i++) {
		h = h * 31 + [lower characterAtIndex:i];
	}
	return h;
}

static NSInteger MSGDigitValue(unichar c)
{
	if (c >= '0' && c <= '9') {
		return c - '0';
	}
	if (c >= 'a' && c <= 'f') {
		return c - 'a' + 10;
	}
	if (c >= 'A' && c <= 'F') {
		return c - 'A' + 10;
	}
	return -1;
}

// Consumes up to two decimal digits at pos, storing the value in codeOut.
// Returns the new position; leaves codeOut at -1 when no digit is present.
static NSUInteger MSGReadColorCode(NSString *text, NSUInteger pos, NSUInteger len, NSInteger *codeOut)
{
	if (pos >= len) {
		return pos;
	}
	NSInteger first = MSGDigitValue([text characterAtIndex:pos]);
	if (first < 0 || first > 9) {
		return pos;
	}
	pos++;
	NSInteger value = first;
	if (pos < len) {
		NSInteger second = MSGDigitValue([text characterAtIndex:pos]);
		if (second >= 0 && second <= 9) {
			value = first * 10 + second;
			pos++;
		}
	}
	*codeOut = value;
	return pos;
}

static NSUInteger MSGParseMIRCColor(NSString *text, NSUInteger i, NSColor **fgOut, NSColor **bgOut)
{
	NSUInteger len = [text length];
	NSUInteger p = i + 1;
	NSInteger fgCode = -1;
	NSInteger bgCode = -1;
	p = MSGReadColorCode(text, p, len, &fgCode);
	if (p < len && [text characterAtIndex:p] == ',') {
		p++;
		NSInteger bg;
		p = MSGReadColorCode(text, p, len, &bg);
		if (bg != -1) {
			bgCode = bg;
		}
	}
	// Codes above 15 are malformed and fall back to the default color.
	*fgOut = (fgCode != -1 && fgCode <= 15) ? MSGColorForCode(fgCode) : MSGDefaultTextColor();
	*bgOut = (bgCode != -1 && bgCode <= 15) ? MSGColorForCode(bgCode) : nil;
	return p;
}

static NSUInteger MSGParseHexColor(NSString *text, NSUInteger i, NSColor **fgOut, NSColor **bgOut)
{
	NSUInteger len = [text length];
	NSUInteger p = i + 1;
	NSColor *fg = MSGDefaultTextColor();
	NSColor *bg = nil;
	// A malformed hex sequence resets colors and leaves the digits as text.
	if (p + 5 < len) {
		NSInteger rgb[6];
		BOOL ok = YES;
		for (int k = 0; k < 6; k++) {
			NSInteger v = MSGDigitValue([text characterAtIndex:p + k]);
			if (v < 0) {
				ok = NO;
				break;
			}
			rgb[k] = v;
		}
		if (ok) {
			fg = MSGColorFromRGB(rgb[0] * 16 + rgb[1], rgb[2] * 16 + rgb[3], rgb[4] * 16 + rgb[5]);
			p += 6;
			if (p < len && [text characterAtIndex:p] == ',') {
				p++;
				if (p + 5 < len) {
					NSInteger rgb2[6];
					BOOL ok2 = YES;
					for (int k = 0; k < 6; k++) {
						NSInteger v = MSGDigitValue([text characterAtIndex:p + k]);
						if (v < 0) {
							ok2 = NO;
							break;
						}
						rgb2[k] = v;
					}
					if (ok2) {
						bg = MSGColorFromRGB(rgb2[0] * 16 + rgb2[1], rgb2[2] * 16 + rgb2[3], rgb2[4] * 16 + rgb2[5]);
						p += 6;
					}
				}
			}
		}
	}
	*fgOut = fg;
	*bgOut = bg;
	return p;
}

static NSString *MSGTimeString(NSDate *date)
{
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat:@"HH:mm"];
	NSString *result = [formatter stringFromDate:date];
	[formatter release];
	return result;
}

typedef struct {
	BOOL bold;
	BOOL italic;
	BOOL underline;
	BOOL strike;
	BOOL reverse;
	NSColor *fg;
	NSColor *bg;
} MSGFormatState;

static NSDictionary *MSGAttributesForState(MSGFormatState state, NSColor *defaultFG)
{
	NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
	[attrs setObject:MSGFontFor(state.bold, state.italic) forKey:NSFontAttributeName];
	NSColor *effFG = state.fg ? state.fg : defaultFG;
	NSColor *effBG = state.bg;
	if (state.reverse) {
		// Reverse video swaps the current pair; without explicit colors it
		// becomes a light highlight with dark text.
		NSColor *swap = effFG;
		effFG = effBG ? effBG : MSGReverseForegroundColor();
		effBG = swap;
	}
	[attrs setObject:effFG forKey:NSForegroundColorAttributeName];
	if (effBG) {
		[attrs setObject:effBG forKey:NSBackgroundColorAttributeName];
	}
	if (state.underline) {
		[attrs setObject:[NSNumber numberWithInteger:NSUnderlineStyleSingle] forKey:NSUnderlineStyleAttributeName];
	}
	if (state.strike) {
		[attrs setObject:[NSNumber numberWithInteger:NSUnderlineStyleSingle] forKey:NSStrikethroughStyleAttributeName];
	}
	return attrs;
}

static void MSGFlushChunk(NSMutableAttributedString *result, NSMutableString *chunk,
	MSGFormatState state, NSColor *defaultFG)
{
	if ([chunk length] == 0) {
		return;
	}
	NSDictionary *attrs = MSGAttributesForState(state, defaultFG);
	NSAttributedString *segment = [[NSAttributedString alloc] initWithString:chunk attributes:attrs];
	[result appendAttributedString:segment];
	[segment release];
	[chunk setString:@""];
}

// Collapse runs of three or more newlines down to two (a single blank line)
// so the transcript never shows more than one blank line in a row, e.g. when
// a multi-line message pastes several empty lines.
static NSString *MSGCollapseConsecutiveBlankLines(NSString *text)
{
	if (!text || [text length] == 0) {
		return text;
	}
	NSUInteger len = [text length];
	NSMutableString *out = [NSMutableString stringWithCapacity:len];
	NSInteger run = 0;
	for (NSUInteger i = 0; i < len; i++) {
		unichar c = [text characterAtIndex:i];
		if (c == '\n') {
			if (run >= 2) {
				continue;
			}
			[out appendFormat:@"%C", c];
			run++;
		} else {
			[out appendFormat:@"%C", c];
			run = 0;
		}
	}
	return out;
}

static NSAttributedString *MSGParseFormattedText(NSString *text, BOOL initialItalic, NSColor *defaultFG)
{
	if (!text) {
		text = @"";
	}
	text = MSGCollapseConsecutiveBlankLines(text);
	if (!defaultFG) {
		defaultFG = MSGDefaultTextColor();
	}
	NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
	NSMutableString *chunk = [[NSMutableString alloc] initWithCapacity:[text length] + 16];
	MSGFormatState state;
	state.bold = NO;
	state.italic = initialItalic;
	state.underline = NO;
	state.strike = NO;
	state.reverse = NO;
	state.fg = nil;
	state.bg = nil;
	NSUInteger i = 0;
	NSUInteger len = [text length];
	while (i < len) {
		unichar c = [text characterAtIndex:i];
		switch (c) {
			case 0x02:
				MSGFlushChunk(result, chunk, state, defaultFG);
				state.bold = YES;
				i++;
				break;
			case 0x1D:
				MSGFlushChunk(result, chunk, state, defaultFG);
				state.italic = YES;
				i++;
				break;
			case 0x1F:
				MSGFlushChunk(result, chunk, state, defaultFG);
				state.underline = YES;
				i++;
				break;
			case 0x1E:
				MSGFlushChunk(result, chunk, state, defaultFG);
				state.strike = YES;
				i++;
				break;
			case 0x16:
				MSGFlushChunk(result, chunk, state, defaultFG);
				state.reverse = YES;
				i++;
				break;
			case 0x0F:
				MSGFlushChunk(result, chunk, state, defaultFG);
				state.bold = NO;
				state.italic = initialItalic;
				state.underline = NO;
				state.strike = NO;
				state.reverse = NO;
				state.fg = nil;
				state.bg = nil;
				i++;
				break;
			case 0x03:
				MSGFlushChunk(result, chunk, state, defaultFG);
				i = MSGParseMIRCColor(text, i, &state.fg, &state.bg);
				break;
			case 0x04:
				MSGFlushChunk(result, chunk, state, defaultFG);
				i = MSGParseHexColor(text, i, &state.fg, &state.bg);
				break;
			default:
				[chunk appendFormat:@"%C", c];
				i++;
				break;
		}
	}
	MSGFlushChunk(result, chunk, state, defaultFG);
	[chunk release];
	return [result autorelease];
}

@implementation MSGMessageRenderer

+ (NSFont *)baseFont
{
	return [NSFont systemFontOfSize:12.0];
}

+ (NSColor *)colorForNick:(NSString *)nick
{
	if (!nick || [nick length] == 0) {
		return MSGDefaultTextColor();
	}
	return [MSGNickColorPalette() objectAtIndex:(MSGNickHash(nick) % [MSGNickColorPalette() count])];
}

+ (NSString *)initialForNick:(NSString *)nick
{
	if (!nick || [nick length] == 0) {
		return @"?";
	}
	// Mode prefixes are list decoration, not part of the name.
	NSUInteger start = 0;
	while (start < [nick length] &&
	    strchr("@+~&%", [nick characterAtIndex:start]) != NULL) {
		start++;
	}
	if (start >= [nick length]) {
		return @"?";
	}
	// Take a whole composed character sequence so surrogate pairs and
	// accented letters survive the cut intact.
	NSRange unit = [nick rangeOfComposedCharacterSequenceAtIndex:start];
	return [[nick substringWithRange:unit] uppercaseString];
}

+ (NSAttributedString *)attributedStringForNick:(NSString *)nick mode:(NSString *)mode
{
	if (!nick) {
		nick = @"";
	}
	NSString *prefix = mode ? mode : @"";
	NSString *full = ([prefix length] > 0) ? [NSString stringWithFormat:@"%@%@", prefix, nick] : nick;
	NSDictionary *attrs = [NSDictionary dictionaryWithObjectsAndKeys:
		[self baseFont], NSFontAttributeName,
		[self colorForNick:nick], NSForegroundColorAttributeName,
		nil];
	return [[[NSAttributedString alloc] initWithString:full attributes:attrs] autorelease];
}

+ (NSAttributedString *)attributedStringForText:(NSString *)text
{
	return MSGParseFormattedText(text, NO, MSGDefaultTextColor());
}

+ (NSAttributedString *)rawAttributedStringForMessage:(MSGMessage *)message
{
	if (!message) {
		return [[[NSAttributedString alloc] initWithString:@""] autorelease];
	}
	if ([message isSystemMessage]) {
		NSString *text = [message displayText];
		if (!text || [text length] == 0) {
			text = [message text];
		}
		if (!text) {
			text = @"";
		}
		NSColor *gray = [NSColor colorWithCalibratedWhite:0.30 alpha:1.0];
		return MSGParseFormattedText(text, NO, gray);
	}
	if ([message isAction]) {
		NSMutableAttributedString *line = [[NSMutableAttributedString alloc] init];
		NSDictionary *italicAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
			MSGFontFor(NO, YES), NSFontAttributeName,
			MSGDefaultTextColor(), NSForegroundColorAttributeName,
			nil];
		[line appendAttributedString:[[[NSAttributedString alloc] initWithString:@"* " attributes:italicAttrs] autorelease]];
		if (message.sender) {
			NSString *nick = message.sender.nick ? message.sender.nick : @"";
			NSDictionary *nickAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
				MSGFontFor(NO, YES), NSFontAttributeName,
				[self colorForNick:nick], NSForegroundColorAttributeName,
				nil];
			[line appendAttributedString:[[[NSAttributedString alloc] initWithString:nick attributes:nickAttrs] autorelease]];
			[line appendAttributedString:[[[NSAttributedString alloc] initWithString:@" " attributes:italicAttrs] autorelease]];
		}
		NSString *text = [message text];
		if (text && [text length] > 0) {
			[line appendAttributedString:MSGParseFormattedText(text, YES, MSGDefaultTextColor())];
		}
		if ([message pending]) {
			NSDictionary *dimAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
				MSGFontFor(NO, YES), NSFontAttributeName,
				[NSColor colorWithCalibratedWhite:0.45 alpha:1.0],
					NSForegroundColorAttributeName,
				nil];
			[line appendAttributedString:[[[NSAttributedString alloc] initWithString:@" [sending...]" attributes:dimAttrs] autorelease]];
		}
		return [line autorelease];
	}
	NSDate *timestamp = message.timestamp ? message.timestamp : [NSDate date];
	NSString *nick = message.sender.nick ? message.sender.nick : @"";
	NSColor *textColor = [message pending]
		? [NSColor colorWithCalibratedWhite:0.45 alpha:1.0]
		: MSGDefaultTextColor();
	NSDictionary *defAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
		[self baseFont], NSFontAttributeName,
		textColor, NSForegroundColorAttributeName,
		nil];
	NSDictionary *nickAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
		[self baseFont], NSFontAttributeName,
		[self colorForNick:nick], NSForegroundColorAttributeName,
		nil];
	NSMutableAttributedString *line = [[NSMutableAttributedString alloc] init];
	[line appendAttributedString:[[[NSAttributedString alloc] initWithString:MSGTimeString(timestamp) attributes:defAttrs] autorelease]];
	[line appendAttributedString:[[[NSAttributedString alloc] initWithString:@"  " attributes:defAttrs] autorelease]];
	[line appendAttributedString:[[[NSAttributedString alloc] initWithString:nick attributes:nickAttrs] autorelease]];
	[line appendAttributedString:[[[NSAttributedString alloc] initWithString:@": " attributes:defAttrs] autorelease]];
	NSString *display = [message displayText];
	if (!display) {
		display = @"";
	}
	[line appendAttributedString:MSGParseFormattedText(display, NO, textColor)];
	if ([message pending]) {
		NSDictionary *dimAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
			MSGFontFor(NO, YES), NSFontAttributeName,
			[NSColor colorWithCalibratedWhite:0.45 alpha:1.0],
				NSForegroundColorAttributeName,
			nil];
		[line appendAttributedString:[[[NSAttributedString alloc] initWithString:@" [sending...]" attributes:dimAttrs] autorelease]];
	}
	return [line autorelease];
}

// Public line renderer: raw output plus clickable link decoration.
+ (NSAttributedString *)attributedStringForMessage:(MSGMessage *)message
{
	return [MSGLinkDetector attributedStringWithLinksApplied:
	    [self rawAttributedStringForMessage:message]];
}

// Raw bubble body without link decoration; see the public method below.
+ (NSAttributedString *)bubbleBodyWithoutLinksOfMessage:(MSGMessage *)message
{
	if (!message) {
		return [[[NSAttributedString alloc] initWithString:@""] autorelease];
	}
	if ([message isSystemMessage]) {
		NSString *text = [message displayText];
		if (!text || [text length] == 0) {
			text = [message text];
		}
		if (!text) {
			text = @"";
		}
		NSColor *gray = [NSColor colorWithCalibratedWhite:0.30 alpha:1.0];
		return MSGParseFormattedText(text, NO, gray);
	}
	if ([message isAction]) {
		NSMutableAttributedString *line = [[NSMutableAttributedString alloc] init];
		NSDictionary *italicAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
			MSGFontFor(NO, YES), NSFontAttributeName,
			MSGDefaultTextColor(), NSForegroundColorAttributeName,
			nil];
		[line appendAttributedString:[[[NSAttributedString alloc] initWithString:@"* " attributes:italicAttrs] autorelease]];
		if (message.sender) {
			NSString *nick = message.sender.nick ? message.sender.nick : @"";
			NSDictionary *nickAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
				MSGFontFor(NO, YES), NSFontAttributeName,
				[self colorForNick:nick], NSForegroundColorAttributeName,
				nil];
			[line appendAttributedString:[[[NSAttributedString alloc] initWithString:nick attributes:nickAttrs] autorelease]];
			[line appendAttributedString:[[[NSAttributedString alloc] initWithString:@" " attributes:italicAttrs] autorelease]];
		}
		NSString *text = [message text];
		if (text && [text length] > 0) {
			[line appendAttributedString:MSGParseFormattedText(text, YES, MSGDefaultTextColor())];
		}
		return [line autorelease];
	}

	// Regular chat: small muted timestamp, then the formatted body. The
	// balloon itself already tells the reader who is speaking.
	NSDate *timestamp = message.timestamp ? message.timestamp : [NSDate date];
	NSDictionary *timeAttrs = [NSDictionary dictionaryWithObjectsAndKeys:
		[NSFont systemFontOfSize:10.0], NSFontAttributeName,
		[NSColor colorWithCalibratedWhite:0.45 alpha:1.0],
			NSForegroundColorAttributeName,
		nil];
	NSMutableAttributedString *line = [[NSMutableAttributedString alloc] init];
	[line appendAttributedString:
		[[[NSAttributedString alloc]
			initWithString:MSGTimeString(timestamp) attributes:timeAttrs]
			autorelease]];
	[line appendAttributedString:
		[[[NSAttributedString alloc] initWithString:@"  " attributes:timeAttrs]
			autorelease]];
	NSString *display = [message displayText];
	if (!display) {
		display = @"";
	}
	[line appendAttributedString:MSGParseFormattedText(display, NO, MSGDefaultTextColor())];
	return [line autorelease];
}

// Public bubble body: raw output plus clickable link decoration.
+ (NSAttributedString *)attributedStringForBubbleBodyOfMessage:(MSGMessage *)message
{
	return [MSGLinkDetector attributedStringWithLinksApplied:
	    [self bubbleBodyWithoutLinksOfMessage:message]];
}

@end