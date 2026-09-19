//
//  QuasselSocket.h
//  Quassel for GNUstep
//
//  Drop-in replacement for the twelve-selector subset of the socket library
//  that QuasselCoreConnection uses. The original library's TLS depends on a
//  framework GNUstep does not have; rather than port 7,430 lines, this
//  implements the small surface the engine needs on a POSIX socket with
//  GNUstep's GnuTLS layer (GSTLSSession, see QuasselSocket.m).
//
//  Modified for Messages (2026): comments reworded.
//

#import <Foundation/Foundation.h>

@class QuasselSocket;

@protocol QuasselSocketDelegate <NSObject>
@optional
- (void)socket:(QuasselSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port;
- (void)socket:(QuasselSocket *)sock didReadData:(NSData *)data withTag:(long)tag;
- (void)socket:(QuasselSocket *)sock didReadPartialDataOfLength:(NSUInteger)partialLength tag:(long)tag;
- (void)socketDidSecure:(QuasselSocket *)sock;
- (void)socketDidDisconnect:(QuasselSocket *)sock withError:(NSError *)err;
@end


// Modified for Messages (2026): no GCD. The socket is watched by the main
// run loop (readiness events instead of a 10 ms polling timer) and the host
// name is resolved on a helper thread, so neither idle time nor a slow DNS
// server costs the UI anything.
@interface QuasselSocket : NSObject

@property (nonatomic, weak) id delegate;   // id, not id<...>: the engine does not formally adopt the protocol

- (instancetype)initWithDelegate:(id)aDelegate;

/// Starts resolving and connecting; returns NO only for a socket that is
/// already in use. Failures (including the timeout) arrive later through
/// -socketDidDisconnect:withError:.
- (BOOL)connectToHost:(NSString *)host
               onPort:(uint16_t)port
          withTimeout:(NSTimeInterval)timeout
                error:(NSError **)errPtr;

- (void)disconnect;

@property (nonatomic, readonly) BOOL isConnected;
@property (nonatomic, readonly) BOOL isDisconnected;
@property (nonatomic, readonly) BOOL isSecure;

- (void)writeData:(NSData *)data withTimeout:(NSTimeInterval)timeout tag:(long)tag;

/// One-shot read request, matching GCDAsyncSocket semantics: with timeout -1 and
/// tag -1 the engine is asking for "whatever arrives next". Delivered via
/// -socket:didReadData:withTag:, after which the engine asks again.
- (void)readDataWithTimeout:(NSTimeInterval)timeout tag:(long)tag;

/// Upgrade an open connection to TLS. Honours QuasselTLSValidatesCertificateChain
/// = NO, which is what the app passes.
- (void)startTLS:(NSDictionary *)tlsSettings;

/// GNUstep's NSObject has no -debugDescription; the engine logs with it.
- (NSString *)debugDescription;

/// GCDAsyncSocket ran this on its internal socket queue; here all work is on
/// the main run loop already, so the block is simply executed.
- (void)performBlock:(void (^)(void))block;

@end
