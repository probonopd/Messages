//
//  GCDAsyncSocket.h  (GNUstep compatibility shim)
//  Quassel for GNUstep
//
//  QuasselCoreConnection.h does `#import "GCDAsyncSocket.h"` and refers to the
//  type GCDAsyncSocket throughout (property declaration plus five delegate
//  callbacks). Putting this directory ahead of the real CocoaAsyncSocket on the
//  header search path redirects all of that to QuasselSocket, so the 1,643-line
//  engine needs no socket-related edits at all.
//
//  The real GCDAsyncSocket cannot be used here: it imports
//  <Security/SecureTransport.h> unconditionally and GNUstep has no
//  Security.framework. See QuasselSocket.h for the replacement's rationale.
//

#import "QuasselSocket.h"

@compatibility_alias GCDAsyncSocket QuasselSocket;

// CFNetwork does not exist on GNUstep, but QuasselCoreConnection passes this key
// to startTLS: to disable certificate-chain validation (quassel cores are
// commonly self-signed). Exported here as an NSString so the app's
// `(id)kCFStreamSSLValidatesCertificateChain` cast keeps working unchanged.
extern NSString * const kCFStreamSSLValidatesCertificateChain;
