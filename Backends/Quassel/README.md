# Quassel backend

Connects Messages to a Quassel core (legacy Quassel protocol, as spoken by
iQuassel).

## Origin and license

`Engine/` and `Transport/` come from iQuassel's GNUstep port,
<https://github.com/pkgdemon/iquassel/tree/gnustep-native> at commit
d066f517e4c46008420dc39c7d55fafd0913d811: the protocol engine by Woboq GmbH
and contributors (`quassel-for-ios/quassel-for-ios/`) and the GNUstep socket
of the port (`gnustep/Core/QuasselSocket.*`, `gnustep/Shims/GCDAsyncSocket.h`).
They are licensed under the GNU General Public License version 3
(`COPYING`; the upstream license statement is in `LICENSE.iquassel`), and so
is this bundle as a whole. Files written for Messages (`Backend/`,
`Transport/QuasselCompat.h`, the GNUmakefiles) are
`BSD-2-Clause OR GPL-3.0-or-later`.

Every upstream file changed for Messages says so in a comment at its top:
the GCD queue and CoreFoundation constants are gone, compiler warnings are
fixed, backlog replies are reported to the delegate, and the socket uses
run-loop descriptor watchers, asynchronous name resolution and a connect
timeout. See ARCHITECTURE.md, "Quassel backend".
