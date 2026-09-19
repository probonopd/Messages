# Messages

Messages is a native GNUstep chat and messaging client. Its first backend
talks to [The Lounge](https://thelounge.chat/), a self-hosted IRC bouncer,
using the same client/server protocol as the The Lounge web client, so it
connects to an existing The Lounge installation and never connects to IRC
networks directly. Further backends connect to Nosterm (NOSTR relays) and to
Quassel cores; several accounts of any backends can be used at the same
time. Each backend is a loadable bundle; see `ARCHITECTURE.md`.

It is written in Objective-C and built entirely from native GNUstep/AppKit
components. There is **no embedded browser, WebKit, WebView, or JavaScript
runtime** anywhere in the application.

## Status

Working:

- Login with password; the session token returned by the server is stored
  (file permissions 0600) and reused for fast re-authentication.
- Server URL, username and "remember me" flag persist across launches.
- Sidebar with networks and channels (unread counts, highlight bolding),
  message pane (mIRC formatting, colors, actions), user list with mode
  prefixes.
- Channel switching marks channels read (`open`), requests user lists,
  restores history; scrolling to the top loads older messages (`more`).
- Sending: plain text as message, `/command` lines forwarded for the server
  to parse.
- Automatic reconnection with exponential backoff and jitter; on reconnect a
  delta `init` is merged into existing state (no duplicates).
- Main window size and position persist across launches.
- Native main menu: About panel, Hide/Show, Close Window (Cmd-W), standard
  Edit keys, Window menu with window list.

Known limitations:

- Network creation/editing (`network:new`/`network:edit`) not yet in the UI.
- Settings (`setting:*`), mentions and session lists are ignored.
- IRC color codes 0 (white) and other bright palette entries are hard to read
  on the light theme.

## Requirements

- GNUstep with AppKit (verified: gnustep-make 2.9.3, GNUstep Base 1.31.1 on
  Debian Linux). GNUstep GUI is required.
- clang (Objective-C compiler).
- libcurl 8.x with WebSocket support (`ws`/`wss` protocols, `curl_ws_send` /
  `curl_ws_recv`). Verified: libcurl 8.14.1.
- zlib (Quassel backend), OpenSSL libcrypto (Nosterm backend).
- A server to talk to: The Lounge 4.5.x, a NOSTR relay, or a Quassel core.

## Build

```sh
source /System/Library/Makefiles/GNUstep.sh
make
```

The top-level GNUmakefile builds, in order, `MessagesKit.framework`, the
backend bundles in `Backends/` and `Messages.app`, which copies the bundles
into its `PlugIns` folder. The build must complete with zero warnings.

## Install

```sh
sudo make install GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
```

This installs `MessagesKit.framework` and `Messages.app` (with its backends)
into the SYSTEM domain. The GNUmakefiles pin
`GNUSTEP_INSTALLATION_DOMAIN = SYSTEM`; nothing may be installed to the LOCAL
domain. After installing, verify there are no
leftovers under `/Local/Applications` or `/Local/Library`.

The application bundle is `Messages.app`; `ApplicationName`/`CFBundleName`
in `MessagesInfo.plist` also feed the generated `.desktop` entry.

## Run

```sh
openapp Messages
```

or directly:

```sh
/System/Applications/Messages.app/Messages
```

First run: the New Account panel opens. Pick the service (The Lounge,
Nosterm Relay or Quassel Core), fill in the fields the service asks for and
press Connect; the panel closes once the account is connected. More accounts
are added with Chat > New Account; Chat > Edit Account and Remove Account act
on the account of the selected network. Accounts are stored in
`~/Library/ApplicationSupport/Messages/accounts.plist` and reconnect on the
next launch; a The Lounge password is traded for a session token at the
first login and not kept.

## Tests

Tests live in `Tests/` and build against the framework and backends of this
tree, so build from the top first:

```sh
make
cd Tests
make
export LD_LIBRARY_PATH=$PWD/../MessagesKit/MessagesKit.framework/Versions/Current
./obj/t_accounts   # backend registry, account id slots, routing, persistence
./obj/t_quassel    # Quassel backend against Fixtures/quassel_mockcore.py
./obj/t_model      # model objects and wire parsing
./obj/t_engineio   # Engine.IO packets
./obj/t_socketio   # Socket.IO packets
./obj/t_protocol   # The Lounge event dispatch, model updates, reconciliation
./obj/t_session    # live end-to-end session against a real server
```

`t_quassel` starts a local mock Quassel core (needs python3) and needs no
other network. `t_session` and the `t_nosterm_*` live tests connect to real
servers (configured in the files or the environment). See COMPATIBILITY.md
for the servers tested.

## Developer tool

`Tools/thelounge-protocol-dump` connects to a The Lounge server and
prints each Engine.IO packet, Socket.IO packet, event name and decoded
payload, with authentication fields redacted automatically:

```text
[RX] EVENT: init
[RX] PAYLOAD: {...}
```

Development and regression testing only; not part of the shipped app.

## Architecture

Three parts (details in ARCHITECTURE.md):

1. **Messages.app** (`Messages/`) - AppKit UI: account panel, main window
   (network outline, message view, user list, input bar), menus. The UI
   never touches raw packets and never imports a backend header; it
   observes model notifications and asks accounts for their capabilities.
2. **MessagesKit.framework** (`MessagesKit/`) - the model (`MSGNetwork`,
   `MSGChannel`, `MSGMessage`, `MSGUser`, ...), the backend API
   (`MSGBackend`, `MSGAccount`, `MSGProtocol`), `MSGAccountManager`
   (accounts, persistence, id slots, routing) and the shared libcurl
   WebSocket transport.
3. **Backends** (`Backends/*/`, `.msgbackend` bundles loaded from
   `Messages.app/PlugIns`) - The Lounge (Socket.IO over WebSocket), Nosterm
   (NOSTR relays), Quassel (the iQuassel protocol engine, GPL-3.0).

Security: TLS verification always on for The Lounge and Nosterm, no
JavaScript anywhere, passwords and tokens never written to logs. The
account list holds the The Lounge session token and the Quassel password
(the legacy Quassel protocol has no tokens); it is written with mode 0600 in
a 0700 directory. Quassel cores are commonly self-signed, so the Quassel
backend does not verify the core's certificate chain, as iQuassel does.

## Documentation

- `PROTOCOL.md` - how the client talks to the server (concise wire reference).
- `SPEC.md` - the development specification.
- `ARCHITECTURE.md` - transport, threading and security decisions.
- `COMPATIBILITY.md` - what has actually been tested against which releases.
