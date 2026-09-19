// Dual-Licensed, GPLv3 and Woboq GmbH's private license. See file "LICENSE"
// Modified for Messages (2026): byte order uses Foundation's NSSwap* functions.

#import "BufferInfo.h"
#import "SignedId.h"
#import "QVariant.h"

@implementation BufferInfo

@synthesize bufferName;
@synthesize bufferId;
@synthesize networkId;
@synthesize bufferType;
@synthesize groupId;
@synthesize bufferActivity;

- (id) initWithSerialization:(NSData*)s bytesRead:(int*)bytesRead
{
    self = [super init];
    int offset = 0;
    

    //            BufferInfo ret = new BufferInfo();
    //            ret.id = stream.readInt();
    bufferId = [[BufferId alloc] initWithInt:NSSwapBigIntToHost(*(int*)([s bytes] + offset))];
    offset += 4;
    
    //            ret.networkId = stream.readInt();
    networkId = [[NetworkId alloc] initWithInt:NSSwapBigIntToHost(*(int*)([s bytes] + offset))];
    offset += 4;
    
    //            ret.type = BufferInfo.Type.getType(stream.readShort());
    bufferType = NSSwapBigShortToHost(*(int*)([s bytes] + offset));
    offset += 2;
    
    //            ret.groupId = stream.readUInt(32); // FIXME What is a group ID?
    groupId = NSSwapBigIntToHost(*(int*)([s bytes] + offset));
    offset += 4;
    
    //            ret.name =  (String) QMetaTypeRegistry.instance().getTypeForName("QByteArray").getSerializer().unserialize(stream, version);
    //Otherwise: the array size (quint32) followed by the array bytes, i.e. size bytes
    unsigned int baSize = NSSwapBigIntToHost(*(int*)([s bytes] + offset));
    //NSLog(@"BufferInfo baSize=%u", baSize);
    offset += 4;
    if (baSize != 0xFFFFFFFF) {
        bufferName = [[NSString alloc] initWithBytes:[s bytes] + offset length:baSize encoding:NSUTF8StringEncoding];
        offset += baSize;
    }
    
    *bytesRead += offset;
    return self;
}

- (void) serialize:(NSMutableData*)data
{
    [bufferId serialize:data];
    
    [networkId serialize:data];
    
    short bufferTypeSerialization = NSSwapHostShortToBig(bufferType);
    [data appendBytes:(char*)&bufferTypeSerialization length:2];
    
    int groupIdSerialization = NSSwapHostIntToBig(groupId);
    [data appendBytes:(char*)&groupIdSerialization length:4];
    
    // serialize buffer name as byte array
    const char *bufferNameUtf8 = [bufferName UTF8String];
    if (!bufferNameUtf8)
        bufferNameUtf8 = "";
    int bufferNameUtf8Length = strlen(bufferNameUtf8);
    int bufferNameUtf8LengthNetwork = NSSwapBigIntToHost(bufferNameUtf8Length);
    [data appendBytes:&bufferNameUtf8LengthNetwork length:4];
    [data appendBytes:bufferNameUtf8 length:bufferNameUtf8Length];
}

- (NSString *)description
{
   // return [super description];
    //return bufferName;
    return [NSString stringWithFormat:@"BufferInfo(id=%d,type=%d,network=%d,group=%u,%@)",[bufferId intValue], bufferType, [networkId intValue], groupId, bufferName];
}

@end
