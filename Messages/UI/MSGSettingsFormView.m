/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "MSGSettingsFormView.h"
#import "MSGBackend.h"
#import "MSGLayoutMetrics.h"

NSString *const MSGSettingsFormViewDidChangeNotification =
	@"MSGSettingsFormViewDidChangeNotification";

@interface MSGSettingsFormView ()
{
	NSArray *_fields;
	// settings key -> NSTextField or NSButton, in field order
	NSMutableDictionary *_controls;
	NSMutableArray *_orderedControls;
}
@end

@implementation MSGSettingsFormView

+ (CGFloat)heightForFields:(NSArray *)fields
{
	if ([fields count] == 0) {
		return 0.0;
	}
	// The gap below the last row belongs to whatever follows the form.
	return MSGMetricsRowStep * [fields count] - MSGMetricsControlGap;
}

- (instancetype)initWithFields:(NSArray *)fields width:(CGFloat)width
	labelWidth:(CGFloat)labelWidth
{
	CGFloat height = [[self class] heightForFields:fields];
	self = [super initWithFrame:NSMakeRect(0, 0, width, height)];
	if (self) {
		_fields = [fields copy];
		_controls = [[NSMutableDictionary alloc] init];
		_orderedControls = [[NSMutableArray alloc] init];
		[self buildWithLabelWidth:labelWidth];
		[self setSettings:nil];
	}
	return self;
}

- (void)dealloc
{
	[_fields release];
	[_controls release];
	[_orderedControls release];
	[super dealloc];
}

- (NSTextField *)labelWithTitle:(NSString *)title frame:(NSRect)frame
{
	NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
	[label setStringValue:title];
	[label setEditable:NO];
	[label setSelectable:NO];
	[label setBezeled:NO];
	[label setDrawsBackground:NO];
	[label setAlignment:NSRightTextAlignment];
	[label setAutoresizingMask:NSViewMinYMargin];
	return [label autorelease];
}

- (void)buildWithLabelWidth:(CGFloat)labelWidth
{
	CGFloat width = NSWidth([self frame]);
	CGFloat fieldX = labelWidth + MSGMetricsControlGap;
	CGFloat fieldW = width - fieldX;
	CGFloat y = NSHeight([self frame]) - MSGMetricsFieldHeight;
	for (NSDictionary *field in _fields) {
		NSString *type = field[MSGSettingFieldType];
		NSView *control;
		if ([type isEqualToString:MSGSettingFieldTypeCheckbox]) {
			NSButton *box = [[[NSButton alloc] initWithFrame:
				NSMakeRect(fieldX, y + (MSGMetricsFieldHeight - MSGMetricsCheckboxHeight) / 2.0,
					fieldW, MSGMetricsCheckboxHeight)] autorelease];
			[box setButtonType:NSSwitchButton];
			[box setTitle:field[MSGSettingFieldLabel]];
			[box setTarget:self];
			[box setAction:@selector(checkboxChanged:)];
			control = box;
		} else {
			[self addSubview:[self labelWithTitle:field[MSGSettingFieldLabel]
				frame:NSMakeRect(0, y + 3.0, labelWidth, MSGMetricsLabelHeight)]];
			Class fieldClass = [type isEqualToString:MSGSettingFieldTypeSecure]
				? [NSSecureTextField class] : [NSTextField class];
			NSTextField *text = [[[fieldClass alloc] initWithFrame:
				NSMakeRect(fieldX, y, fieldW, MSGMetricsFieldHeight)] autorelease];
			// Explicit: on a white tab pane an unbordered field is invisible.
			[text setBezeled:YES];
			[text setBezelStyle:NSTextFieldSquareBezel];
			if (field[MSGSettingFieldPlaceholder]) {
				[text setPlaceholderString:field[MSGSettingFieldPlaceholder]];
			}
			[text setDelegate:self];
			control = text;
		}
		[control setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
		[self addSubview:control];
		[[_orderedControls lastObject] setNextKeyView:control];
		[_orderedControls addObject:control];
		_controls[field[MSGSettingFieldKey]] = control;
		y -= MSGMetricsRowStep;
	}
}

#pragma mark - Values

- (void)setSettings:(NSDictionary *)settings
{
	for (NSDictionary *field in _fields) {
		NSString *key = field[MSGSettingFieldKey];
		id value = settings[key] ?: field[MSGSettingFieldDefault];
		id control = _controls[key];
		if ([field[MSGSettingFieldType] isEqualToString:MSGSettingFieldTypeCheckbox]) {
			[control setState:[value boolValue] ? NSOnState : NSOffState];
		} else {
			[control setStringValue:value ? [value description] : @""];
		}
	}
}

- (NSString *)trimmedStringForKey:(NSString *)key
{
	return [[_controls[key] stringValue] stringByTrimmingCharactersInSet:
		[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSDictionary *)settingsByMergingInto:(NSDictionary *)base
{
	NSMutableDictionary *settings = [NSMutableDictionary dictionaryWithDictionary:base];
	for (NSDictionary *field in _fields) {
		NSString *key = field[MSGSettingFieldKey];
		NSString *type = field[MSGSettingFieldType];
		if ([type isEqualToString:MSGSettingFieldTypeCheckbox]) {
			settings[key] = @([_controls[key] state] == NSOnState);
			continue;
		}
		NSString *text = [self trimmedStringForKey:key];
		if ([text length] == 0) {
			[settings removeObjectForKey:key];
		} else if ([type isEqualToString:MSGSettingFieldTypeNumber]) {
			settings[key] = @([text integerValue]);
		} else {
			settings[key] = text;
		}
	}
	return settings;
}

- (NSString *)missingRequiredFieldLabel
{
	for (NSDictionary *field in _fields) {
		if ([field[MSGSettingFieldRequired] boolValue] &&
			[[self trimmedStringForKey:field[MSGSettingFieldKey]] length] == 0) {
			return [field[MSGSettingFieldLabel] stringByTrimmingCharactersInSet:
				[NSCharacterSet characterSetWithCharactersInString:@":"]];
		}
	}
	return nil;
}

- (NSView *)firstControl
{
	return [_orderedControls firstObject];
}

- (NSView *)lastControl
{
	return [_orderedControls lastObject];
}

- (NSView *)firstEmptyControl
{
	for (NSView *control in _orderedControls) {
		if ([control isKindOfClass:[NSTextField class]] &&
			[[(NSTextField *)control stringValue] length] == 0) {
			return control;
		}
	}
	return nil;
}

#pragma mark - Change tracking

- (void)announceChange
{
	[[NSNotificationCenter defaultCenter]
		postNotificationName:MSGSettingsFormViewDidChangeNotification object:self];
}

- (void)controlTextDidChange:(NSNotification *)notification
{
	[self announceChange];
}

- (void)checkboxChanged:(id)sender
{
	[self announceChange];
}

@end
