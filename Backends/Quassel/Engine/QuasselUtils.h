// Dual-Licensed, GPLv3 and Woboq GmbH's private license. See file "LICENSE"

#import <Foundation/Foundation.h>
#import "Message.h"


@interface QuasselUtils : NSObject

+ (NSString*) extractNick:(NSString*)nickUserHost;
+ (NSString*) extractTimestamp:(Message*)message;

+ (NSString*)transformedByteValue:(long)value;

+ (NSData*) qUncompress:(const char*) data count:(int)count;
+ (NSData*) qCompress:(const char*)data count:(int)nbytes;

+ (NSString*) trimStringForConsole:(NSString*)string;

// Returns a packed 0xRRGGBB value rather than a UIColor, so the protocol/util
// layer stays free of any UI framework. The AppKit layer wraps it in NSColor.
+ (uint32_t) rgbFromNick:(NSString*)nick;


@end
