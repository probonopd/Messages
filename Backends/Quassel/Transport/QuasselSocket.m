//
//  QuasselSocket.m
//  Quassel for GNUstep
//
//  POSIX socket transport with GNUstep's own TLS layer (GSTLSSession) layered
//  on when the Quassel handshake calls for STARTTLS.
//
//  Why not NSStream: gnustep-base installs its TLS handler inside -open
//  (GSSocketStream.m:2064, +[GSTLSHandler tryInput:output:], called immediately
//  before connect()), reading NSStreamSocketSecurityLevelKey at that instant.
//  Setting the property afterwards is silently ignored -- no handler is ever
//  installed and nothing re-checks it. Quassel's legacy handshake *requires*
//  upgrading partway through: ClientInit goes out in the clear and TLS starts
//  only after ClientInitAck reports SupportSsl. NSStream cannot express that,
//  and cores refuse a plaintext session outright (verified: UseSsl=false gets
//  ClientInitReject).
//
//  So the fd is ours, and GSTLSSession rides on it via push/pull callbacks.
//  That reuses GNUstep's tested GnuTLS integration rather than hand-rolling
//  gnutls calls, and honours the usual GSTLS* options.
//
//  Modified for Messages (2026): the 10 ms polling NSTimer is replaced by
//  run-loop descriptor watchers, getaddrinfo() runs on a helper thread, the
//  connect has a timeout, and TLS data GnuTLS already decrypted is drained
//  without waiting for the descriptor. No libdispatch and no libs-corebase;
//  comments reworded, TLS key renamed.
//

#import "QuasselSocket.h"

#import <GNUstepBase/GSTLS.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <netdb.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <poll.h>

// Declared in the GCDAsyncSocket compatibility shim.
NSString * const QuasselTLSValidatesCertificateChain = @"QuasselTLSValidatesCertificateChain";

static NSString * const QuasselSocketErrorDomain = @"QuasselSocketErrorDomain";

typedef NS_ENUM(NSInteger, QSState) {
    QSStateIdle,
    QSStateResolving,
    QSStateConnecting,
    QSStateConnected,
    QSStateHandshaking,
    QSStateSecure,
    QSStateClosed
};

// GSTLSSession drives TLS through these; the transport pointer is our fd.
static ssize_t qs_push(gnutls_transport_ptr_t h, const void *buf, size_t len)
{
    return send((int)(intptr_t)h, buf, len, MSG_NOSIGNAL);
}

static ssize_t qs_pull(gnutls_transport_ptr_t h, void *buf, size_t len)
{
    return recv((int)(intptr_t)h, buf, len, 0);
}

// Traffic must keep flowing while an alert or a menu runs its own mode.
static NSArray *QSRunLoopModes(void)
{
    return @[NSDefaultRunLoopMode, @"NSModalPanelRunLoopMode",
             @"NSEventTrackingRunLoopMode"];
}


@interface QuasselSocket () <RunLoopEvents>
@end

@implementation QuasselSocket
{
    int             _fd;
    QSState         _state;

    NSMutableData  *_writeQueue;
    BOOL            _wantsRead;
    long            _readTag;

    BOOL            _watchingRead;
    BOOL            _watchingWrite;
    NSTimer        *_connectTimer;

    NSString       *_host;
    uint16_t        _port;

    GSTLSSession   *_tls;
}

- (instancetype)initWithDelegate:(id)aDelegate
{
    if ((self = [super init])) {
        _delegate   = aDelegate;
        _writeQueue = [[NSMutableData alloc] init];
        _readTag    = -1;
        _fd         = -1;
        _state      = QSStateIdle;
    }
    return self;
}

- (void)dealloc
{
    [self _teardown];
}

#pragma mark - Connect

- (BOOL)connectToHost:(NSString *)host
               onPort:(uint16_t)port
          withTimeout:(NSTimeInterval)timeout
                error:(NSError **)errPtr
{
    if (_state != QSStateIdle) {
        if (errPtr) *errPtr = [self _errno:EISCONN message:@"Socket is already in use"];
        return NO;
    }

    _host  = [host copy];
    _port  = port;
    _state = QSStateResolving;

    if (timeout > 0) {
        _connectTimer = [NSTimer timerWithTimeInterval:timeout target:self
            selector:@selector(_connectTimedOut:) userInfo:nil repeats:NO];
        for (NSString *mode in QSRunLoopModes()) {
            [[NSRunLoop currentRunLoop] addTimer:_connectTimer forMode:mode];
        }
    }

    // getaddrinfo() blocks for as long as the DNS server takes; the thread
    // keeps the socket alive until its answer is delivered back here.
    [NSThread detachNewThreadSelector:@selector(_resolveInBackground:)
                             toTarget:self withObject:@[_host, @(port)]];
    return YES;
}

- (void)_resolveInBackground:(NSArray *)hostAndPort
{
    @autoreleasepool {
        struct addrinfo hints, *res = NULL;
        memset(&hints, 0, sizeof(hints));
        hints.ai_family   = AF_UNSPEC;
        hints.ai_socktype = SOCK_STREAM;

        char portstr[16];
        snprintf(portstr, sizeof(portstr), "%u", [hostAndPort[1] unsignedIntValue]);

        int gai = getaddrinfo([hostAndPort[0] UTF8String], portstr, &hints, &res);
        NSMutableArray *addresses = [NSMutableArray array];
        if (gai == 0) {
            for (struct addrinfo *ai = res; ai != NULL; ai = ai->ai_next) {
                [addresses addObject:@[@(ai->ai_family), @(ai->ai_protocol),
                    [NSData dataWithBytes:ai->ai_addr length:ai->ai_addrlen]]];
            }
            freeaddrinfo(res);
        }
        NSDictionary *result = @{@"gai": @(gai), @"addresses": addresses};
        [self performSelectorOnMainThread:@selector(_resolved:)
                               withObject:result waitUntilDone:NO];
    }
}

- (void)_resolved:(NSDictionary *)result
{
    if (_state != QSStateResolving) return;   // disconnected meanwhile

    int gai = [result[@"gai"] intValue];
    NSArray *addresses = result[@"addresses"];
    if (gai != 0 || [addresses count] == 0) {
        [self _failWithError:[NSError errorWithDomain:QuasselSocketErrorDomain code:gai
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Cannot resolve %@: %s",
                    _host, gai_strerror(gai)]}]];
        return;
    }

    int fd = -1;
    int lastErr = 0;
    for (NSArray *address in addresses) {
        NSData *sockaddr = address[2];
        fd = socket([address[0] intValue], SOCK_STREAM, [address[1] intValue]);
        if (fd < 0) { lastErr = errno; continue; }

        int flags = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);

        int one = 1;
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));

        if (connect(fd, [sockaddr bytes], (socklen_t)[sockaddr length]) == 0
            || errno == EINPROGRESS) {
            break;
        }
        lastErr = errno;
        close(fd);
        fd = -1;
    }

    if (fd < 0) {
        [self _failWithError:[self _errno:lastErr message:
            [NSString stringWithFormat:@"Cannot connect to %@:%u", _host, (unsigned)_port]]];
        return;
    }

    _fd    = fd;
    _state = QSStateConnecting;
    [self _updateWatchers];
}

- (void)_connectTimedOut:(NSTimer *)timer
{
    _connectTimer = nil;
    if (_state == QSStateResolving || _state == QSStateConnecting) {
        [self _failWithError:[self _errno:ETIMEDOUT message:
            [NSString stringWithFormat:@"Cannot connect to %@:%u", _host, (unsigned)_port]]];
    }
}

- (void)disconnect
{
    if (_state == QSStateClosed) return;
    _state = QSStateClosed;
    [self _teardown];
    [self _notifyDisconnected:nil];
}

- (void)_teardown
{
    [_connectTimer invalidate];
    _connectTimer = nil;
    [self _setWatchRead:NO write:NO];

    if (_tls) {
        [_tls disconnect:NO];
        _tls = nil;
    }
    if (_fd >= 0) {
        close(_fd);
        _fd = -1;
    }
}

#pragma mark - State

- (BOOL)isConnected
{
    return (_state == QSStateConnected
            || _state == QSStateHandshaking
            || _state == QSStateSecure);
}
- (BOOL)isDisconnected { return ![self isConnected]; }
- (BOOL)isSecure       { return (_state == QSStateSecure); }

#pragma mark - IO API

- (void)writeData:(NSData *)data withTimeout:(NSTimeInterval)timeout tag:(long)tag
{
    if (data.length == 0 || _state == QSStateClosed) return;
    [_writeQueue appendData:data];
    [self _pumpOnce];
}

- (void)readDataWithTimeout:(NSTimeInterval)timeout tag:(long)tag
{
    _wantsRead = YES;
    _readTag   = tag;
    [self _pumpOnce];
}

#pragma mark - TLS

- (void)startTLS:(NSDictionary *)tlsSettings
{
    if (_fd < 0 || _state == QSStateClosed) return;

    id validates = [tlsSettings objectForKey:QuasselTLSValidatesCertificateChain];
    BOOL validateChain = (validates == nil) || [validates boolValue];

    NSMutableDictionary *opts = [NSMutableDictionary dictionary];
    // Quassel cores are routinely self-signed and the app deliberately does not
    // validate the chain -- preserve that rather than inventing a trust policy.
    [opts setObject:(validateChain ? @"YES" : @"NO") forKey:GSTLSVerify];
    if (_host.length) {
        [opts setObject:_host forKey:GSTLSServerName];
    }

    _tls = [GSTLSSession sessionWithOptions:opts
                                  direction:YES            // outgoing / client
                                  transport:(void *)(intptr_t)_fd
                                       push:qs_push
                                       pull:qs_pull];
    if (_tls == nil) {
        [self _failWithError:[NSError errorWithDomain:QuasselSocketErrorDomain code:-1
            userInfo:@{NSLocalizedDescriptionKey: @"Could not create a TLS session"}]];
        return;
    }

    _state = QSStateHandshaking;
    [self _pumpOnce];
}

#pragma mark - performBlock

- (void)performBlock:(void (^)(void))block
{
    if (block) block();
}

- (NSString *)debugDescription
{
    return [NSString stringWithFormat:
            @"<%@ %p host=%@:%u fd=%d state=%ld secure=%d pendingWrite=%lu>",
            NSStringFromClass([self class]), self, _host, (unsigned)_port,
            _fd, (long)_state, (int)[self isSecure],
            (unsigned long)_writeQueue.length];
}

#pragma mark - Run loop watchers
//
// Readiness is watched only while something is waiting for it: the fd is
// level-triggered, so an unconditional read watch would spin the run loop
// while the engine has not asked for data yet.

- (void)_setWatchRead:(BOOL)read write:(BOOL)write
{
    NSRunLoop *loop = [NSRunLoop currentRunLoop];
    void *data = (void *)(intptr_t)_fd;
    if (read != _watchingRead) {
        for (NSString *mode in QSRunLoopModes()) {
            if (read) {
                [loop addEvent:data type:ET_RDESC watcher:self forMode:mode];
            } else {
                [loop removeEvent:data type:ET_RDESC forMode:mode all:YES];
            }
        }
        _watchingRead = read;
    }
    if (write != _watchingWrite) {
        for (NSString *mode in QSRunLoopModes()) {
            if (write) {
                [loop addEvent:data type:ET_WDESC watcher:self forMode:mode];
            } else {
                [loop removeEvent:data type:ET_WDESC forMode:mode all:YES];
            }
        }
        _watchingWrite = write;
    }
}

- (void)_updateWatchers
{
    if (_fd < 0 || _state == QSStateClosed) {
        [self _setWatchRead:NO write:NO];
        return;
    }
    BOOL write = (_state == QSStateConnecting) || (_writeQueue.length > 0)
        || (_state == QSStateHandshaking);
    BOOL read = _wantsRead || (_state == QSStateHandshaking);
    [self _setWatchRead:read write:write];
}

- (void)receivedEvent:(void *)data
                 type:(RunLoopEventType)type
                extra:(void *)extra
              forMode:(NSString *)mode
{
    [self _pumpOnce];
}

#pragma mark - Pump

- (void)_pumpOnce
{
    if (_fd < 0 || _state == QSStateClosed) return;

    switch (_state) {
        case QSStateConnecting:  [self _pumpConnect];   break;
        case QSStateHandshaking: [self _pumpHandshake]; break;
        case QSStateConnected:
        case QSStateSecure:
            [self _flushWrites];
            [self _drainInput];
            break;
        default:
            break;
    }
    [self _updateWatchers];
}

- (void)_pumpConnect
{
    struct pollfd p;
    p.fd      = _fd;
    p.events  = POLLOUT;
    p.revents = 0;
    if (poll(&p, 1, 0) <= 0) return;

    int       err = 0;
    socklen_t len = sizeof(err);
    if (getsockopt(_fd, SOL_SOCKET, SO_ERROR, &err, &len) < 0) err = errno;

    if (err != 0) {
        [self _failWithError:[self _errno:err message:
            [NSString stringWithFormat:@"Cannot connect to %@:%u", _host, (unsigned)_port]]];
        return;
    }

    [_connectTimer invalidate];
    _connectTimer = nil;
    _state = QSStateConnected;
    if ([_delegate respondsToSelector:@selector(socket:didConnectToHost:port:)]) {
        [_delegate socket:self didConnectToHost:_host port:_port];
    }
}

- (void)_pumpHandshake
{
    // -handshake returns YES when complete, NO when it needs another turn.
    if (![_tls handshake]) return;

    if (![_tls active]) {
        NSString *why = [_tls problem];
        [self _failWithError:[NSError errorWithDomain:QuasselSocketErrorDomain code:-2
            userInfo:@{NSLocalizedDescriptionKey:
                (why.length ? why : @"TLS handshake failed")}]];
        return;
    }

    _state = QSStateSecure;
    if ([_delegate respondsToSelector:@selector(socketDidSecure:)]) {
        [_delegate socketDidSecure:self];
    }
    [self _flushWrites];
    [self _drainInput];
}

- (BOOL)_wouldBlock
{
    return (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR);
}

- (void)_flushWrites
{
    while (_writeQueue.length > 0 && _fd >= 0) {
        NSInteger n;
        if (_state == QSStateSecure) {
            n = [_tls write:[_writeQueue bytes] length:[_writeQueue length]];
        } else {
            n = send(_fd, [_writeQueue bytes], [_writeQueue length], MSG_NOSIGNAL);
        }

        if (n > 0) {
            [_writeQueue replaceBytesInRange:NSMakeRange(0, (NSUInteger)n)
                                   withBytes:NULL length:0];
            continue;
        }
        if (n == 0 || [self _wouldBlock]) return;   // the write watcher retries

        [self _failWithError:[self _errno:errno message:@"Write failed"]];
        return;
    }
}

- (void)_drainInput
{
    // GnuTLS may already hold decrypted data the descriptor no longer
    // signals, so keep reading while the engine re-arms from its callback.
    while (_wantsRead && _fd >= 0) {
        uint8_t buf[16 * 1024];
        NSInteger n;
        if (_state == QSStateSecure) {
            n = [_tls read:buf length:sizeof(buf)];
        } else {
            n = recv(_fd, buf, sizeof(buf), 0);
        }

        if (n > 0) {
            NSData *chunk = [NSData dataWithBytes:buf length:(NSUInteger)n];
            // One-shot, matching GCDAsyncSocket: clear the request before
            // delivering, because the engine re-arms from inside its callback.
            _wantsRead = NO;
            long tag = _readTag;

            if ([_delegate respondsToSelector:@selector(socket:didReadPartialDataOfLength:tag:)]) {
                [_delegate socket:self didReadPartialDataOfLength:(NSUInteger)n tag:tag];
            }
            if ([_delegate respondsToSelector:@selector(socket:didReadData:withTag:)]) {
                [_delegate socket:self didReadData:chunk withTag:tag];
            }
            if (_state == QSStateSecure && [_tls pending] > 0) {
                continue;
            }
            return;
        }

        if (n == 0) {                       // clean EOF: the core closed
            [self _failWithError:nil];
            return;
        }
        if ([self _wouldBlock]) return;     // nothing yet

        [self _failWithError:[self _errno:errno message:@"Read failed"]];
        return;
    }
}

#pragma mark - Errors

- (NSError *)_errno:(int)e message:(NSString *)msg
{
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:e
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"%@: %s", msg, strerror(e)]}];
}

- (void)_failWithError:(NSError *)err
{
    if (_state == QSStateClosed) return;
    _state = QSStateClosed;
    [self _teardown];
    [self _notifyDisconnected:err];
}

- (void)_notifyDisconnected:(NSError *)err
{
    if ([_delegate respondsToSelector:@selector(socketDidDisconnect:withError:)]) {
        [_delegate socketDidDisconnect:self withError:err];
    }
}

@end
