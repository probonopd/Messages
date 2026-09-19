# AGENTS.md

Messages.app (formerly TheLounge.app): a native GNUstep/AppKit (Objective-C) multi-protocol chat client. `MessagesKit/` is the framework (model, backend API, account manager), `Backends/{TheLounge,Nosterm,Quassel}` are `.msgbackend` bundles loaded from `Messages.app/PlugIns`, `Messages/` is the app; see `ARCHITECTURE.md` "Multi-protocol architecture". Class prefixes: `MSG` (framework, app), `TL` (The Lounge backend), `NT` (Nosterm), upstream names in the Quassel engine. The Lounge backend speaks the The Lounge client protocol (Socket.IO v5 / Engine.IO v4 over WebSocket via libcurl). No embedded browser/JS runtime.

## Build

GNUstep is installed at `/System`, not `/usr/GNUstep`. Source the env first:

```sh
source /System/Library/Makefiles/GNUstep.sh
```

- Everything: `make` at the top (aggregate: MessagesKit, Backends, Messages; the app copies the built bundles into `Messages.app/PlugIns`). `sudo make install` installs the framework and the app to SYSTEM.
- Tests: `make` at the top first, then `cd Tests && make` and run `./obj/t_*` with `LD_LIBRARY_PATH=$PWD/../MessagesKit/MessagesKit.framework/Versions/Current` (`gmake check` is NOT wired). Offline: `t_accounts`, `t_accountui` (Account menu section, settings form), `t_outline` (sidebar selection), `t_quassel` (spawns `Fixtures/quassel_mockcore.py`, needs python3), `t_model`, `t_engineio`, `t_socketio`, `t_protocol`, `t_badge`, `t_bubbles`, `t_contextmenu`, `t_nostr_crypto`, `t_nosterm_nickname`. `t_quassel` links the Quassel engine objects from `Backends/Quassel/Engine/obj`, so the backends must be built.
- Tool: `cd Tools && make` -> `./obj/thelounge-protocol-dump`
- In-tree consumers link MessagesKit by path (`MSGKIT_LIBS` in `MessagesKit/MessagesKit.make`), because gnustep-make puts `-L/System/Library/Libraries` first and a plain `-lMessagesKit` silently links the installed copy. Likewise, when running an uninstalled build, set `LD_LIBRARY_PATH` AFTER sourcing `GNUstep.sh`, which prepends the system library path.
- `make clean` before rebuilding when changing sources; zero warnings is a hard requirement (fix every warning, never suppress beyond the one flag below)

Links `-lcurl` (libcurl 8.14.1 with `ws`/`wss`). Compiler is clang.

## Non-ARC rules (differ from default ObjC, easy to get wrong)

- Manual retain/release, `[super dealloc]`. No ARC anywhere, with one exception: the upstream Quassel engine (`Backends/Quassel/Engine`, `Backends/Quassel/Transport`) keeps its ARC and is built as a `subproject.make` with `-fobjc-arc`. The Quassel glue in `Backends/Quassel/Backend` is MRC. The engine holds its delegate strongly and does not retain itself during its own callbacks: clear the delegate and autorelease (not release) the engine when closing.
- `__weak` is a compile error. Blocks that capture `self` must use `__block` (MRC `__block` does not retain, so no cycle). Delegate properties are `assign`.
- No GCD/dispatch at all; use NSLock/`performSelectorOnMainThread`.
- Model properties `newNick`, `newIdent`, `newHost`, `rawText` intentionally mirror wire field names and trip clang's ownership naming heuristic (the flag name is clang's) - the `-Wno-objc-property-matches-cocoa-ownership-rule` flag in the GNUmakefiles must stay.
- `MSGMessage` has a BOOL property named `self`; read it with `-isSelf`, never `message.self` (clang crashes in its backend on that).
- The GNUmakefiles pin `GNUSTEP_INSTALLATION_DOMAIN = SYSTEM`; the backend bundles set `STANDARD_INSTALL = no` and are installed inside the app. Never install to LOCAL; verify `/Local/Applications` etc. has no leftovers after `make install`.

## Wire layering (subtle, get this right)

Chain (The Lounge): `MSGWebSocketTransport` (libcurl CURLWS, connect-only + select loop) -> `TLEngineIOClient` (EIO=4) -> `TLSocketIOClient` (Socket.IO v5, an `MSGTransportClient`) -> `MSGAccount` (hops to the main thread) -> `MSGEventDispatcher` -> `TLoungeProtocol_4_5` -> the account's own `MSGServerState`. The UI reads `MSGAccountManager.combinedState` and observes `MSG*DidChangeNotification` only.

- Each account writes only its own model state; channel ids live in the account's id slot (`MSGAccountIdSlotSize` = 2^56, slot = id >> 56). The Lounge uses server ids verbatim (`+usesServerChannelIds`), so it takes slot 0 and only one The Lounge account can exist at a time.

- On the wire messages look like `4<payload>` (Engine.IO `4` = message). The Engine.IO client strips that prefix, so `TLSocketIOParser` receives the bare payload e.g. `2["event",...]`. When parsing Socket.IO packets, do NOT feed the parser `42...` strings; tests use `2[...]`.
- Endpoint: `<install-path>socket.io/?EIO=4&transport=websocket`; scheme http->ws, https->wss; path must end with `/`.
- Auth: server `auth:start(hash)` -> client `auth:perform` `{user,password}` or `{user,token,...}` -> `auth:success` -> `configuration` -> `push:issubscribed` -> `init{active,networks}`.
- Server `id` is authoritative for messages. Reconnect `init` only returns messages with `id > lastMessage` (max 100), so on reconnect the handler MUST merge into existing state, not replace it (`handleInitEvent` reconciliation).
- Protocol is pinned to The Lounge 4.5.0 (commit `dd2108fa8096949473f8e94dd937461a71d0442d`).

## Verification

- Unit tests are parser/model-level (165 assertions, all green). Live integration confirmed against `https://lounge.assassinate-you.net/` (The Lounge 4.5.2): connect, Engine.IO open, Socket.IO connect, `auth:start`/`auth:perform`/`auth:success`, `configuration`, `init` (55 KB payload), `commands`. Test via `thelounge-protocol-dump <url> <user> --password <pw>` (output auto-redacted).
- Large WebSocket frames are split across many `curl_ws_recv` calls WITHOUT `CURLWS_CONT`; reassemble using `curl_ws_frame.offset`/`bytesleft` (frame complete when `bytesleft==0`). See `receiveLoop` in MessagesKit/MSGWebSocketTransport.m.
- `SPEC.md` is the authoritative spec (see "# 48. Compatibility documentation" before claiming any compatibility). `PROTOCOL.md` is the pinned wire reference; `ARCHITECTURE.md` has the transport/threading/security decisions; `COMPATIBILITY.md` tracks what is actually implemented.

## Style

- New files: header `Copyright (c) 2026 Simon Peter` with `SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later` (the project contains GPL code since the Quassel backend; older files stay BSD-2-Clause). Files in `Backends/Quassel/Engine` and `Transport` and `Tests/Fixtures/quassel_mockcore.py` are third-party GPL-3.0-only: keep their headers, mark every change with a "Modified for Messages" comment at the top. Licensing overview: README "License", `LICENSE`, `Backends/Quassel/LICENSE`.
- No em-dashes (plain `-`), no "WiFi"/"Wi-Fi" (use "WLAN").
- Comments only explain WHY, never WHAT.