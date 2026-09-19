# Quassel backend

Connects Messages to a Quassel core (legacy Quassel protocol, as spoken by
iQuassel).

## Origin and license

`Engine/` and `Transport/` come from iQuassel's GNUstep port,
<https://github.com/pkgdemon/iquassel/tree/gnustep-native> at commit
d066f517e4c46008420dc39c7d55fafd0913d811: the protocol engine by Woboq GmbH
and contributors and the GNUstep socket of the port
(`gnustep/Core/QuasselSocket.*`, `gnustep/Shims/GCDAsyncSocket.h`).
Messages uses them under the GNU General Public License version 3 only
(`COPYING`), so this bundle as a whole is GPL-3.0-only; files written for
Messages (`Backend/`, the GNUmakefiles, the Info.plist) are
`BSD-2-Clause OR GPL-3.0-or-later`. The details, including upstream's dual
license, are in `LICENSE`.

Every upstream file changed for Messages says so in a comment at its top:
the dispatch queue is gone, byte order uses Foundation's `NSSwap*`
functions, compiler warnings are fixed, backlog replies are reported to the
delegate, and the socket uses run-loop descriptor watchers, asynchronous
name resolution and a connect timeout. See ARCHITECTURE.md, "Quassel
backend".
