#!/usr/bin/env python3
"""
mockcore.py -- a minimal Quassel core speaking the LEGACY (pre-2014) protocol.

This exists to validate the GNUstep port's network/protocol stack end to end
without needing a real quassel core. It implements just enough of the handshake
to drive QuasselCoreConnection from ClientInit through to quasselFullyConnected:

    ClientInit   -> ClientInitAck
    ClientLogin  -> ClientLoginAck -> SessionInit
    InitRequest(BufferSyncer)      -> InitData(BufferSyncer)
    InitRequest(BufferViewConfig)  -> InitData(BufferViewConfig)
    InitRequest(Network, <id>)     -> InitData(Network)

Wire format (Qt QDataStream / QVariant, big-endian throughout):
    frame   := uint32 length, then one QVariant
    variant := int32 typeId, uint8 isNull, payload
    types   := 1 Bool, 2 Int, 8 Map, 9 List, 10 String, 12 ByteArray, 127 UserType

usage: mockcore.py [port]   (default 4242)

From iQuassel's gnustep-native branch (github.com/pkgdemon/iquassel,
d066f517), GPL-3.0. Modified for Messages (2026): a ClientLogin with the
password "wrong" is rejected, requestBacklog is answered from a fixed
backlog of 100 messages in #gnustep, sendInput is echoed back as a
displayMsg, and a live message for #quassel arrives after the session is
initialized.
"""
import socket
import struct
import sys
import threading

# ---------------------------------------------------------------- encoding

def u32(n):   return struct.pack(">I", n)
def i32(n):   return struct.pack(">i", n)


def qstring(s):
    """QString payload: uint32 byte-length + UTF-16BE. 0xFFFFFFFF means null."""
    if s is None:
        return b"\xff\xff\xff\xff"
    b = s.encode("utf-16-be")
    return u32(len(b)) + b


def qbytearray(s):
    if s is None:
        return b"\xff\xff\xff\xff"
    b = s.encode("utf-8")
    return u32(len(b)) + b


def variant(type_id, payload):
    return i32(type_id) + b"\x00" + payload


def v_int(n):      return variant(2, i32(n))
def v_bool(b):     return variant(1, b"\x01" if b else b"\x00")
def v_string(s):   return variant(10, qstring(s))
def v_bytearray(s): return variant(12, qbytearray(s))


def v_list(items):
    return variant(9, u32(len(items)) + b"".join(items))


def v_stringlist(strings):
    """QStringList (type 11). The engine iterates these as NSStrings, so channel
    membership must use this rather than a QVariantList of QStrings."""
    return variant(11, u32(len(strings)) + b"".join(qstring(s) for s in strings))


def v_map(d):
    """QVariantMap: uint32 count, then (bare QString key, QVariant value)*"""
    out = u32(len(d))
    for k, val in d.items():
        out += qstring(k) + val
    return variant(8, out)


def v_usertype(name, payload):
    """UserType(127): uint32 len + ASCII name (NUL-terminated on the wire)."""
    nb = name.encode("ascii") + b"\x00"
    return variant(127, u32(len(nb)) + nb + payload)


def v_networkid(n):  return v_usertype("NetworkId", i32(n))
def v_bufferid(n):   return v_usertype("BufferId", i32(n))


def v_bufferinfo(buffer_id, network_id, btype, group_id, name):
    """BufferInfo: int32 id, int32 netid, int16 type, uint32 group, QByteArray name."""
    payload = i32(buffer_id) + i32(network_id) + struct.pack(">h", btype) \
              + u32(group_id) + qbytearray(name)
    return v_usertype("BufferInfo", payload)


def v_message(msg_id, buffer, flags, sender, contents, msg_type=1, ts=None):
    """Message: int32 id, uint32 time, uint32 type, uint8 flags, BufferInfo,
    QByteArray sender, QByteArray contents."""
    (bid, nid, btype, name) = buffer
    info = i32(bid) + i32(nid) + struct.pack(">h", btype) + u32(0) + qbytearray(name)
    payload = i32(msg_id) + u32(ts if ts is not None else 1700000000 + msg_id) \
              + u32(msg_type) + bytes([flags]) + info \
              + qbytearray(sender) + qbytearray(contents)
    return v_usertype("Message", payload)


def frame(v):
    return u32(len(v)) + v


# ---------------------------------------------------------------- decoding
# Only enough to pull MsgType / request type out of what the client sends.

class Reader:
    def __init__(self, data):
        self.d = data
        self.i = 0

    def u32(self):
        v = struct.unpack(">I", self.d[self.i:self.i + 4])[0]
        self.i += 4
        return v

    def i32(self):
        v = struct.unpack(">i", self.d[self.i:self.i + 4])[0]
        self.i += 4
        return v

    def u8(self):
        v = self.d[self.i]
        self.i += 1
        return v

    def string(self):
        n = self.u32()
        if n == 0xFFFFFFFF:
            return ""
        s = self.d[self.i:self.i + n].decode("utf-16-be", "replace")
        self.i += n
        return s

    def bytearray_(self):
        n = self.u32()
        if n == 0xFFFFFFFF:
            return ""
        s = self.d[self.i:self.i + n].decode("utf-8", "replace")
        self.i += n
        return s

    def variant(self):
        t = self.i32()
        self.u8()                      # null flag
        return self.payload(t)

    def payload(self, t):
        if t == 1:   return bool(self.u8())
        if t == 2:   return self.i32()
        if t == 3:   return self.u32()
        if t == 8:                     # map
            n = self.u32()
            return {self.string(): self.variant() for _ in range(n)}
        if t == 9:                     # list
            return [self.variant() for _ in range(self.u32())]
        if t == 10:  return self.string()
        if t == 11:  return [self.string() for _ in range(self.u32())]
        if t == 12:  return self.bytearray_()
        if t == 127:                   # user type
            n = self.u32()
            name = self.d[self.i:self.i + n].rstrip(b"\x00").decode("ascii")
            self.i += n
            if name in ("NetworkId", "IdentityId", "BufferId", "MsgId"):
                return {name: self.i32()}
            if name == "BufferInfo":
                bid, nid = self.i32(), self.i32()
                btype = struct.unpack(">h", self.d[self.i:self.i + 2])[0]
                self.i += 2
                group = self.u32()
                return {name: (bid, nid, btype, group, self.bytearray_())}
            return {name: None}
        if t == 15:  return self.u32()  # QTime
        raise ValueError("unhandled qvariant type %d" % t)


# ---------------------------------------------------------------- fixtures

NETWORKS = {1: "TestNet", 2: "OtherNet"}

# (buffer_id, network_id, type, name)   type: 1=status 2=channel 4=query
BUFFERS = [
    (10, 1, 1, "TestNet"),
    (11, 1, 2, "#gnustep"),
    (12, 1, 2, "#quassel"),
    (13, 1, 4, "alice"),
    (20, 2, 1, "OtherNet"),
    (21, 2, 2, "#irc"),
]

SYNC, RPC_CALL, INIT_REQUEST, INIT_DATA, HEARTBEAT, HEARTBEAT_REPLY = 1, 2, 3, 4, 5, 6

FLAG_SELF = 0x01
BACKLOG_BUFFER = BUFFERS[1]          # #gnustep
BACKLOG = list(range(1, 101))        # message ids 1..100
LIVE_BUFFER = BUFFERS[2]             # #quassel
LIVE_ID = 500


def backlog_reply(bid, last, limit):
    """Newest first, like a real core: ids below `last` (or the newest when
    last is -1), at most `limit`."""
    ids = [m for m in BACKLOG if last < 0 or m < last]
    ids = ids[-limit:] if limit > 0 else ids
    msgs = [v_message(m, BACKLOG_BUFFER, 0, "bob!bob@example.org",
                      "backlog %d" % m) for m in reversed(ids)] \
        if bid == BACKLOG_BUFFER[0] else []
    return frame(v_list([
        v_int(SYNC), v_bytearray("BacklogManager"), v_bytearray(""),
        v_bytearray("receiveBacklog"), v_bufferid(bid),
        v_usertype("MsgId", i32(-1)), v_usertype("MsgId", i32(last)),
        v_int(limit), v_int(0), v_list(msgs)]))


def display_msg(msg):
    return frame(v_list([v_int(RPC_CALL), v_bytearray("2displayMsg(Message)"), msg]))


def session_init():
    return frame(v_map({
        "MsgType": v_string("SessionInit"),
        "SessionState": v_map({
            "NetworkIds":  v_list([v_networkid(n) for n in NETWORKS]),
            "BufferInfos": v_list([v_bufferinfo(b, n, t, 0, nm)
                                   for (b, n, t, nm) in BUFFERS]),
            "Identities":  v_list([]),
        }),
    }))


# Channel membership is derived from the users dict: the engine walks each
# user's "channels" list and adds them to those IrcChannels. Users are keyed by
# nick!user@host, as a real core sends them.
MEMBERS = {
    1: [
        ("alice",   ["#gnustep", "#quassel"], False),
        ("bob",     ["#gnustep"],             False),
        ("carol",   ["#gnustep", "#quassel"], True),
        ("dave",    ["#quassel"],             False),
        ("erin",    ["#gnustep"],             False),
        ("gnustep-tester", ["#gnustep", "#quassel"], False),
    ],
    2: [
        ("frank",   ["#irc"], False),
        ("grace",   ["#irc"], False),
    ],
}

CHANNELS_PER_NET = {1: ["#gnustep", "#quassel"], 2: ["#irc"]}


def network_init_data(net_id):
    users = v_map({
        "%s!%s@example.org" % (nick, nick): v_map({
            "nick":     v_string(nick),
            "realName": v_string(nick.capitalize()),
            "away":     v_bool(away),
            "channels": v_stringlist(chans),
        })
        for (nick, chans, away) in MEMBERS.get(net_id, [])
    })
    channels = v_map({
        ch: v_map({
            "name":  v_string(ch),
            "topic": v_string("mock channel %s" % ch),
        })
        for ch in CHANNELS_PER_NET.get(net_id, [])
    })
    return frame(v_list([
        v_int(INIT_DATA),
        v_string("Network"),
        v_string(str(net_id)),
        v_map({
            "networkName": v_string(NETWORKS.get(net_id, "Net%d" % net_id)),
            "myNick":      v_string("gnustep-tester"),
            "IrcUsersAndChannels": v_map({"users": users, "channels": channels}),
        }),
    ]))


def buffer_view_config_init(cfg_id):
    return frame(v_list([
        v_int(INIT_DATA),
        v_string("BufferViewConfig"),
        v_string(str(cfg_id)),
        v_map({
            "BufferList": v_list([v_bufferid(b) for (b, _, _, _) in BUFFERS]),
            "bufferViewName": v_string("All Chats"),
        }),
    ]))


def buffer_syncer_init():
    last_seen = []
    for (b, _, _, _) in BUFFERS:
        last_seen.append(v_bufferid(b))
        last_seen.append(v_usertype("MsgId", i32(0)))
    return frame(v_list([
        v_int(INIT_DATA),
        v_string("BufferSyncer"),
        v_string(""),
        v_map({"LastSeenMsg": v_list(last_seen)}),
    ]))


# ---------------------------------------------------------------- server

def handle(conn, addr):
    print("[mockcore] client connected from %s:%d" % addr, flush=True)
    buf = b""
    sent_view_config = False
    next_id = 1000

    try:
        while True:
            chunk = conn.recv(65536)
            if not chunk:
                break
            buf += chunk

            while len(buf) >= 4:
                (length,) = struct.unpack(">I", buf[:4])
                if len(buf) < 4 + length:
                    break
                body, buf = buf[4:4 + length], buf[4 + length:]

                try:
                    msg = Reader(body).variant()
                except Exception as e:
                    print("[mockcore] decode error: %s" % e, flush=True)
                    continue

                # ---- handshake maps ----
                if isinstance(msg, dict) and "MsgType" in msg:
                    mt = msg["MsgType"]
                    print("[mockcore] <- %s" % mt, flush=True)

                    if mt == "ClientInit":
                        print("[mockcore]    ProtocolVersion=%s UseSsl=%s UseCompression=%s"
                              % (msg.get("ProtocolVersion"), msg.get("UseSsl"),
                                 msg.get("UseCompression")), flush=True)
                        conn.sendall(frame(v_map({
                            "MsgType":             v_string("ClientInitAck"),
                            "CoreInfo":            v_string("mockcore 0.1 (GNUstep port harness)"),
                            "ProtocolVersion":     v_int(10),
                            # No TLS: keeps this harness focused on the protocol.
                            "SupportSsl":          v_bool(False),
                            "SupportsCompression": v_bool(False),
                            "LoginEnabled":        v_bool(True),
                            "Configured":          v_bool(True),
                        })))
                        print("[mockcore] -> ClientInitAck", flush=True)

                    elif mt == "ClientLogin" and msg.get("Password") == "wrong":
                        conn.sendall(frame(v_map({
                            "MsgType": v_string("ClientLoginReject"),
                            "Error":   v_string("Invalid username or password"),
                        })))
                        print("[mockcore] -> ClientLoginReject", flush=True)

                    elif mt == "ClientLogin":
                        print("[mockcore]    User=%s" % msg.get("User"), flush=True)
                        conn.sendall(frame(v_map({"MsgType": v_string("ClientLoginAck")})))
                        print("[mockcore] -> ClientLoginAck", flush=True)
                        conn.sendall(session_init())
                        print("[mockcore] -> SessionInit (%d networks, %d buffers)"
                              % (len(NETWORKS), len(BUFFERS)), flush=True)
                    continue

                # ---- signal proxy lists ----
                if isinstance(msg, list) and msg:
                    req = msg[0]
                    if req == INIT_REQUEST:
                        cls, objname = msg[1], msg[2]
                        if cls == "BufferSyncer":
                            conn.sendall(buffer_syncer_init())
                            print("[mockcore] -> InitData BufferSyncer", flush=True)
                        elif cls == "BufferViewConfig":
                            # The client brute-forces ids 10..0; answer exactly one.
                            if not sent_view_config and objname == "0":
                                sent_view_config = True
                                conn.sendall(buffer_view_config_init(objname))
                                print("[mockcore] -> InitData BufferViewConfig(%s)" % objname,
                                      flush=True)
                                # One live message once the session is up.
                                threading.Timer(1.0, lambda: conn.sendall(display_msg(
                                    v_message(LIVE_ID, LIVE_BUFFER, 0,
                                              "alice!alice@example.org",
                                              "hello from alice")))).start()
                        elif cls == "Network":
                            nid = int(objname)
                            conn.sendall(network_init_data(nid))
                            print("[mockcore] -> InitData Network(%d)" % nid, flush=True)
                    elif req == SYNC and msg[3] == "requestBacklog":
                        bid = msg[4]["BufferId"]
                        last, limit = msg[6]["MsgId"], msg[7]
                        conn.sendall(backlog_reply(bid, last, limit))
                        print("[mockcore] -> receiveBacklog(%d, last=%d, limit=%d)"
                              % (bid, last, limit), flush=True)
                    elif req == RPC_CALL and msg[1].startswith("2sendInput"):
                        (bid, nid, btype, _, name) = msg[2]["BufferInfo"]
                        text = msg[3]
                        if text.upper().startswith("/SAY "):
                            text = text[5:]
                        next_id += 1
                        conn.sendall(display_msg(v_message(
                            next_id, (bid, nid, btype, name), FLAG_SELF,
                            "gnustep-tester!t@example.org", text)))
                        print("[mockcore] -> displayMsg(%s)" % text, flush=True)
                    elif req == HEARTBEAT:
                        conn.sendall(frame(v_list([v_int(HEARTBEAT_REPLY), msg[1]])))
    except Exception as e:
        print("[mockcore] error: %s" % e, flush=True)
    finally:
        conn.close()
        print("[mockcore] client disconnected", flush=True)


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 4242
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", port))
    s.listen(5)
    print("[mockcore] legacy-protocol quassel core on 127.0.0.1:%d" % port, flush=True)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle, args=(conn, addr), daemon=True).start()


if __name__ == "__main__":
    main()
