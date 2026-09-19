//
//  GCDAsyncSocket.h  (GNUstep compatibility shim)
//  Quassel for GNUstep
//
//  QuasselCoreConnection.h does `#import "GCDAsyncSocket.h"` and refers to the
//  type GCDAsyncSocket throughout (property declaration plus five delegate
//  callbacks). This header redirects all of that to QuasselSocket, so the
//  1,643-line engine needs no socket-related edits. The original socket
//  library depends on a TLS framework GNUstep does not have; see
//  QuasselSocket.h.
//
//  Modified for Messages (2026): comments reworded, TLS key renamed.
//

#import "QuasselSocket.h"

@compatibility_alias GCDAsyncSocket QuasselSocket;

// QuasselCoreConnection passes this key to startTLS: to disable
// certificate-chain validation (quassel cores are commonly self-signed).
extern NSString * const QuasselTLSValidatesCertificateChain;
