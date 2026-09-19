# Architecture

## Layers (The Lounge backend)

```text
GNUstep UI (AppKit, Messages.app)
      |
Combined model (MSGAccountManager.combinedState)
      |
Account (TLoungeAccount: connect/reconnect state machine, own MSGServerState)
      |
The Lounge Protocol Adapter (TLoungeProtocol_4_5)
      |
Socket.IO (TLSocketIOClient)
      |
Engine.IO (TLEngineIOClient)
      |
WebSocket (MSGWebSocketTransport, libcurl)
      |
The Lounge server
      |
IRC networks
```

The other backends and how they plug in are described under
"Multi-protocol architecture" below.

## Transport dependency decision (Phase 1)

Evaluated options for WebSocket + Socket.IO on GNUstep/Linux:

1. **GNUstep WebSocket libraries** - none shipped in the system GNUstep
   installation.
2. **C/C++ WebSocket libraries** - `libwebsockets` and `websocketpp` are not
   installed. **libcurl (8.14.1) is installed and ships a stable WebSocket
   API** (`curl_ws_send` / `curl_ws_recv`, `ws`/`wss` protocols). libcurl
   also provides TLS with certificate and hostname validation, redirect
   handling, HTTP proxies, and is already used across the system.
3. **Socket.IO C++ client** - not installed; adds a C++ dependency and an
   unfamiliar API. It is tied to specific socket.io versions and hard to keep
   version-pinned against The Lounge's socket.io 4.6.2.
4. **License** - libcurl is MIT-style (curl license); no GPL coupling.

Decision:

* **MSGWebSocketTransport** (in MessagesKit, shared with Nosterm) wraps libcurl's WebSocket API (async reads via the
  curl multi interface on a dedicated network thread). All WebSocket framing,
  TLS, and connection state live behind this class.
* **TLEngineIOClient** and **TLSocketIOClient** are implemented in-project
  because the wire formats are small, stable, version-pinned
  (Engine.IO v4, Socket.IO v5) and must not depend on a third-party API.
* JSON is handled with GNUstep's `NSJSONSerialization`.

This satisfies SPEC section 8: existing implementations were evaluated, the
reliable one (libcurl) is wrapped behind project interfaces, and the rest of
the application depends only on the project's transport interfaces.

## Threading

* Main thread: GNUstep UI, model state, model notifications, and the whole Quassel backend (its socket is watched by the main run loop; only name resolution uses a helper thread).
* Network thread: libcurl multi loop feeding `MSGWebSocketTransport`; `MSGAccount` hops every transport callback to the main thread.
* Model mutations happen on the main thread. The transport/protocol layer
  delivers raw Socket.IO events to the protocol adapter; the adapter schedules
  model updates on the main thread (or the UI is only updated from the main
  thread through the notification path).
* All socket writes are serialized on the network thread.

## Versioning of the protocol adapter

`TLoungeProtocol` (an `MSGProtocol`) is the base class; `TLoungeProtocol_4_5` implements the
4.5.x protocol described in PROTOCOL.md. The UI and model layers
contain no The Lounge version-specific logic.

## Security

* TLS certificate and hostname validation always on (libcurl defaults).
* No JavaScript execution anywhere.
* Passwords and tokens kept in a secure credential store, never in property
  lists or logs.
* Server-provided content treated as untrusted.
## Multi-protocol architecture

Messages is split into a shared framework, one loadable bundle per protocol
and a protocol-agnostic app. This follows the usual GNUstep plug-in pattern
(Preferences `.prefPane`, GWorkspace inspectors, GNUMail bundles):
`bundle.make`, `NSPrincipalClass`, discovery through `NSBundle`, a formal
protocol as the contract.

```text
Messages.app (AppKit UI)          Messages.app/PlugIns/*.msgbackend
      |                             TheLounge.msgbackend  (BSD-2-Clause)
      |                             Nosterm.msgbackend    (BSD-2-Clause)
      v                             Quassel.msgbackend    (GPL-3.0)
MessagesKit.framework  <---------------/
(model, backend API, account manager, WebSocket transport, preferences)
```

Source layout: `MessagesKit/`, `Backends/<Name>/`, `Messages/`, `Tests/`,
`Tools/`, `BubbleDemo/`; the top-level GNUmakefile is an `aggregate.make`
that builds them in that order.

### MessagesKit.framework

`framework.make`, BSD-2-Clause, installed to the SYSTEM domain, linked by
the app, every backend, the tests and the tools. Foundation only, so tests
stay headless.

- Model: `MSGServerState` (one per account), `MSGNetwork`, `MSGChannel`,
  `MSGMessage`, `MSGUser`, `MSGClientState`.
- `MSGProtocol`: maps one wire protocol onto an account's model; declares
  its `MSGCapabilities` (server search, history paging, clear history,
  mute, IRC commands, group directory, server-managed networks, reports
  connection loss). The UI enables commands from these flags; there is no
  code in the app that asks which backend it is talking to.
- `MSGTransportClient`: an event-oriented connection (Socket.IO, NOSTR
  relay). `MSGAccount` drives any such client with one connect / reconnect
  (exponential backoff, jitter, 3 s probe) / pending-message state machine.
- `MSGAccount`: one configured connection; owns transport, protocol and
  model state; backends subclass it. Settings are a dictionary; keys in
  `+transientSettingKeys` (a The Lounge password traded for a token) are
  never written to disk.
- `MSGBackend` (the bundle's principal class, class-side only): identifier,
  display name, account class, `+accountSettingFields` (declarative field
  list the app renders as the account form, so backends need no AppKit),
  optional validation and quick-connect presets.
- `MSGBackendRegistry`: reads each bundle's Info.plist without loading
  code, refuses other API versions, loads the code on first use.
- `MSGAccountManager`: accounts, persistence (`accounts.plist`, 0600),
  channel-id slots, routing of channel operations, and `combinedState`, a
  read-only `MSGServerState` view over all accounts for the UI.

### Channel ids

Ids stay `NSInteger` (a string-id model would have rewritten ~400 call
sites). Each account owns a slot of `MSGAccountIdSlotSize` = 2^56 ids, so the
owning account of any id is `id >> 56`. Nosterm hashes into its slot,
Quassel adds the slot base to buffer ids. The Lounge uses the bouncer's
ids verbatim on the wire and in every event, so it declares
`+usesServerChannelIds` and gets slot 0: only one The Lounge account can
exist at a time (a bouncer already aggregates many IRC networks).

Each account writes only its own `MSGServerState`. Before the split, the
bouncer and the relays shared one model, and the bouncer's reconnect path
removed networks it did not know (the relays') and computed `lastMessage`
over all networks.

### Backend bundles

`bundle.make` with `BUNDLE_EXTENSION = .msgbackend` and
`STANDARD_INSTALL = no`; the app's makefile copies the built bundles into
`Messages.app/PlugIns`, which is what `-[NSBundle builtInPlugInsPath]`
returns on GNUstep (not `Resources/PlugIns`). Info.plist of each bundle
(`<Name>Info.plist`, merged by gnustep-make):

| Key | Purpose |
|---|---|
| `NSPrincipalClass` | class conforming to `MSGBackend` |
| `MSGBackendIdentifier` | stable id stored with saved accounts, e.g. `io.github.gershwin-desktop.Messages.TheLounge` |
| `MSGBackendDisplayName` | shown in the account panel without loading code |
| `MSGBackendAPIVersion` | must equal `MSG_BACKEND_API_VERSION`; otherwise the bundle is refused, not loaded on a guess |

- `TheLounge.msgbackend` (`TL` prefix): Engine.IO, Socket.IO, the 4.5
  adapter, `TLoungeAccount`, `TLoungeBackend`.
- `Nosterm.msgbackend` (`NT` prefix): NOSTR crypto, relay client, protocol;
  `-lcrypto` is linked only here. The group chooser for its
  `MSGCapabilityGroupDirectory` is generic app UI.
- `Quassel.msgbackend`: see below.

A saved account whose backend is missing is reported at launch and kept
in `accounts.plist` unchanged, so it returns with the backend.

### Messages.app

UI and orchestration only: the account panel (form rendered from
`+accountSettingFields`), the main window over `combinedState`, account
errors (an account that never worked is removed again when it fails from
the panel; a restored account reconnects silently; authentication and
protocol errors reopen the account's settings). No backend header is
imported.

### Quassel backend

- Origin: <https://github.com/pkgdemon/iquassel/tree/gnustep-native> at
  d066f517 (the iQuassel protocol engine by Woboq GmbH and contributors,
  with a GNUstep socket by the port's author). `Engine/` and `Transport/`
  are upstream files with their headers unchanged; every modified file says
  so at the top.
- License: GPL-3.0 (`COPYING`, `LICENSE.iquassel`). New files in the bundle
  are `BSD-2-Clause OR GPL-3.0-or-later`. MessagesKit and the app stay
  BSD-2-Clause; loaded in-process, the distributed combination is covered
  by GPL-3.0, which BSD-2-Clause permits. Keeping Quassel in its own bundle
  confines that and allows packaging it separately.
- Memory model: upstream keeps ARC. `Engine/GNUmakefile` builds engine and
  socket as a `subproject.make` with `-fobjc-arc`; the glue in `Backend/`
  is MRC like the rest of Messages. The engine holds its delegate strongly
  (the glue clears it when closing) and does not keep itself alive during
  its own callbacks (the glue autoreleases it instead of releasing).
- No GCD: the engine's serial queue is removed (the socket runs on the main
  run loop). No CoreFoundation: `Transport/QuasselCompat.h` maps the
  engine's `CFSwapInt*` byte-order calls to Foundation's `NSSwap*` and is
  force-included into the upstream sources only.
- Socket: the upstream 10 ms polling timer is replaced by run-loop
  descriptor watchers (`-[NSRunLoop addEvent:type:watcher:forMode:]`, also
  in modal and tracking modes), `getaddrinfo()` runs on a helper thread (a
  slow DNS server no longer freezes the UI), the connect has a timeout, and
  data GnuTLS already decrypted is drained without waiting for the
  descriptor. TLS stays on GNUstep's `GSTLSSession` (STARTTLS mid-stream).
- Engine addition: every backlog reply is reported
  (`-quasselBacklogReceivedForBuffer:count:limit:`), including empty and
  all-duplicate ones the engine drops, so the start of a buffer is known
  instead of guessed.
- Protocol: the legacy Quassel protocol (what iQuassel speaks). The
  password is stored with the account because that protocol has no session
  tokens; the core's certificate chain is not verified, as in iQuassel.
- Tests: `Tests/t_quassel` against `Tests/Fixtures/quassel_mockcore.py`
  (upstream's mock core, extended with login rejection, backlog, echo of
  sent input and a live message).
