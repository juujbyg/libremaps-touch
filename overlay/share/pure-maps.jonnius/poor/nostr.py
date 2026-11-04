# -*- coding: utf-8 -*-
# LibreMaps: a small Nostr client, Python standard library only.
#
# Nostr (https://nostr.com) is an open protocol: signed JSON events are
# posted to and read from public relays run by volunteers. LibreMaps uses
# it to share road reports between drivers without a server of its own.
#
# Contents: BIP-340 Schnorr signatures on secp256k1, a minimal WebSocket
# client (RFC 6455), geohash encoding, and publish/query helpers.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

import base64
import hashlib
import json
import os
import secrets
import socket
import ssl
import struct
import threading
import time
import urllib.parse

__all__ = ("make_key", "public_key", "sign_event", "verify_event",
           "publish", "query", "geohash")

# ---------------------------------------------------------------- secp256k1

P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F
N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
G = (0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798,
     0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8)


def _jac_double(X1, Y1, Z1):
    if Y1 == 0:
        return (0, 1, 0)
    S = 4 * X1 * Y1 * Y1 % P
    M = 3 * X1 * X1 % P
    X3 = (M * M - 2 * S) % P
    Y3 = (M * (S - X3) - 8 * Y1 * Y1 * Y1 * Y1) % P
    Z3 = 2 * Y1 * Z1 % P
    return (X3, Y3, Z3)


def _jac_add(p1, p2):
    X1, Y1, Z1 = p1
    X2, Y2, Z2 = p2
    if Z1 == 0:
        return p2
    if Z2 == 0:
        return p1
    Z1Z1 = Z1 * Z1 % P
    Z2Z2 = Z2 * Z2 % P
    U1 = X1 * Z2Z2 % P
    U2 = X2 * Z1Z1 % P
    S1 = Y1 * Z2 * Z2Z2 % P
    S2 = Y2 * Z1 * Z1Z1 % P
    if U1 == U2:
        if S1 != S2:
            return (0, 1, 0)
        return _jac_double(X1, Y1, Z1)
    H = U2 - U1
    R = S2 - S1
    H2 = H * H % P
    H3 = H * H2 % P
    U1H2 = U1 * H2 % P
    X3 = (R * R - H3 - 2 * U1H2) % P
    Y3 = (R * (U1H2 - X3) - S1 * H3) % P
    Z3 = H * Z1 * Z2 % P
    return (X3, Y3, Z3)


def _to_affine(p):
    X, Y, Z = p
    if Z == 0:
        return None
    zi = pow(Z, -1, P)
    zi2 = zi * zi % P
    return (X * zi2 % P, Y * zi2 * zi % P)


def _mul(point, k):
    """k * point, with point in affine coordinates. Returns affine or None."""
    result = (0, 1, 0)
    addend = (point[0], point[1], 1)
    while k:
        if k & 1:
            result = _jac_add(result, addend)
        addend = _jac_double(*addend)
        k >>= 1
    return _to_affine(result)


# Precomputed multiples of G (G, 2G, 4G, ...) make signing about twice as fast.
_G_TABLE = []


def _mul_g(k):
    if not _G_TABLE:
        q = (G[0], G[1], 1)
        for _ in range(256):
            _G_TABLE.append(q)
            q = _jac_double(*q)
    result = (0, 1, 0)
    i = 0
    while k:
        if k & 1:
            result = _jac_add(result, _G_TABLE[i])
        k >>= 1
        i += 1
    return _to_affine(result)


def _lift_x(x):
    if x >= P:
        return None
    y_sq = (pow(x, 3, P) + 7) % P
    y = pow(y_sq, (P + 1) // 4, P)
    if y * y % P != y_sq:
        return None
    return (x, y if y % 2 == 0 else P - y)


def _tagged_hash(tag, data):
    t = hashlib.sha256(tag.encode()).digest()
    return hashlib.sha256(t + t + data).digest()


def _b32(x):
    return x.to_bytes(32, "big")


def make_key():
    """Return a new random private key as 64 hex characters."""
    while True:
        d = secrets.randbelow(N)
        if d:
            return "%064x" % d


def _mul_g_nonzero(k):
    pt = _mul_g(k % N)
    if pt is None:
        raise ValueError("invalid key")
    return pt


def public_key(sk_hex):
    """Return the x-only public key (64 hex) for a private key."""
    return "%064x" % _mul_g_nonzero(int(sk_hex, 16))[0]


def schnorr_sign(msg, sk_hex):
    d0 = int(sk_hex, 16)
    Pt = _mul_g_nonzero(d0)
    d = d0 if Pt[1] % 2 == 0 else N - d0
    aux = secrets.token_bytes(32)
    t = bytes(a ^ b for a, b in zip(_b32(d), _tagged_hash("BIP0340/aux", aux)))
    k0 = int.from_bytes(_tagged_hash("BIP0340/nonce", t + _b32(Pt[0]) + msg), "big") % N
    if k0 == 0:
        raise ValueError("bad nonce")
    R = _mul_g_nonzero(k0)
    k = k0 if R[1] % 2 == 0 else N - k0
    e = int.from_bytes(_tagged_hash("BIP0340/challenge", _b32(R[0]) + _b32(Pt[0]) + msg), "big") % N
    return _b32(R[0]) + _b32((k + e * d) % N)


def schnorr_verify(msg, pk_hex, sig):
    if len(sig) != 64:
        return False
    Pt = _lift_x(int(pk_hex, 16))
    r = int.from_bytes(sig[:32], "big")
    s = int.from_bytes(sig[32:], "big")
    if Pt is None or r >= P or s >= N:
        return False
    e = int.from_bytes(_tagged_hash("BIP0340/challenge", sig[:32] + _b32(Pt[0]) + msg), "big") % N
    sG = _mul_g(s)
    eP = _mul(Pt, N - e)
    if sG is None or eP is None:
        return False
    R = _to_affine(_jac_add((sG[0], sG[1], 1), (eP[0], eP[1], 1)))
    return R is not None and R[1] % 2 == 0 and R[0] == r


# ------------------------------------------------------------------ events

def _event_id(ev):
    data = [0, ev["pubkey"], ev["created_at"], ev["kind"], ev["tags"], ev["content"]]
    raw = json.dumps(data, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def pow_bits(id_hex):
    """Leading zero bits of an event id (NIP-13 difficulty)."""
    n = 0
    for ch in id_hex:
        v = int(ch, 16)
        if v == 0:
            n += 4
            continue
        return n + (4 - v.bit_length())
    return n


def _mine(ev, bits):
    """NIP-13: add a nonce tag and search for an id with `bits` leading zero
    bits. Hashes a fixed prefix once and only the nonce and suffix per try."""
    marker = "\x00NONCE\x00"
    tags = [t for t in ev["tags"] if not (t and t[0] == "nonce")]
    ev["tags"] = tags + [["nonce", marker, str(bits)]]
    raw = json.dumps([0, ev["pubkey"], ev["created_at"], ev["kind"], ev["tags"], ev["content"]],
                     separators=(",", ":"), ensure_ascii=False)
    marker_json = json.dumps(marker, ensure_ascii=False)[1:-1]
    prefix, suffix = raw.split(marker_json)
    base = hashlib.sha256(prefix.encode("utf-8"))
    suffix = suffix.encode("utf-8")
    full, rest = divmod(bits, 8)
    limit = 1 << (8 - rest)
    zeros = bytes(full)
    n = 0
    while True:
        h = base.copy()
        h.update(str(n).encode() + suffix)
        d = h.digest()
        if d[:full] == zeros and (rest == 0 or d[full] < limit):
            ev["tags"][-1][1] = str(n)
            return d.hex()
        n += 1


def sign_event(kind, tags, content="", sk_hex=None, created_at=None, pow=0):
    """Return a signed event. Without a key, a fresh one-use key is made,
    so events can't be linked to each other. With pow > 0, the event carries
    NIP-13 proof of work of that many bits, so forging many events costs time."""
    sk_hex = sk_hex or make_key()
    ev = {"pubkey": public_key(sk_hex),
          "created_at": int(created_at or time.time()),
          "kind": int(kind),
          "tags": [list(t) for t in tags],
          "content": content}
    ev["id"] = _mine(ev, pow) if pow > 0 else _event_id(ev)
    ev["sig"] = schnorr_sign(bytes.fromhex(ev["id"]), sk_hex).hex()
    return ev


def well_formed(ev):
    """Shape and types of an event from a relay, before trusting any field."""
    if not isinstance(ev, dict):
        return False
    for k, ln in (("id", 64), ("pubkey", 64), ("sig", 128)):
        v = ev.get(k)
        if not isinstance(v, str) or len(v) != ln:
            return False
        try:
            bytes.fromhex(v)
        except ValueError:
            return False
    for k in ("created_at", "kind"):
        v = ev.get(k)
        if not isinstance(v, int) or isinstance(v, bool) or not 0 <= v < 2**40:
            return False
    if not isinstance(ev.get("content"), str) or len(ev["content"]) > 4096:
        return False
    tags = ev.get("tags")
    if not isinstance(tags, list) or len(tags) > 64:
        return False
    for t in tags:
        if not isinstance(t, list) or not t or len(t) > 8:
            return False
        if not all(isinstance(x, str) and len(x) <= 256 for x in t):
            return False
    return True


def verify_event(ev):
    try:
        if not well_formed(ev):
            return False
        if _event_id(ev) != ev["id"]:
            return False
        return schnorr_verify(bytes.fromhex(ev["id"]), ev["pubkey"], bytes.fromhex(ev["sig"]))
    except Exception:
        return False


# ---------------------------------------------------------------- geohash

_B32 = "0123456789bcdefghjkmnpqrstuvwxyz"


def geohash(lat, lon, precision=6):
    lat_r, lon_r = [-90.0, 90.0], [-180.0, 180.0]
    bits, bit, ch, out, even = [16, 8, 4, 2, 1], 0, 0, [], True
    while len(out) < precision:
        rng, val = (lon_r, lon) if even else (lat_r, lat)
        mid = (rng[0] + rng[1]) / 2
        if val >= mid:
            ch |= bits[bit]
            rng[0] = mid
        else:
            rng[1] = mid
        even = not even
        if bit < 4:
            bit += 1
        else:
            out.append(_B32[ch])
            bit, ch = 0, 0
    return "".join(out)


# -------------------------------------------------------------- websocket

class WebSocket:
    """Just enough RFC 6455 for Nostr: text frames, ping/pong, close."""

    def __init__(self, url, timeout=8, user_agent="LibreMaps"):
        u = urllib.parse.urlsplit(url)
        host = u.hostname
        port = u.port or (443 if u.scheme == "wss" else 80)
        sock = socket.create_connection((host, port), timeout=timeout)
        if u.scheme == "wss":
            sock = ssl.create_default_context().wrap_socket(sock, server_hostname=host)
        self.sock = sock
        self.buf = b""
        key = base64.b64encode(os.urandom(16)).decode()
        path = (u.path or "/") + ("?" + u.query if u.query else "")
        req = ("GET %s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
               "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\nUser-Agent: %s\r\n\r\n"
               % (path, host, key, user_agent))
        sock.sendall(req.encode())
        head = self._read_until(b"\r\n\r\n")
        status = head.split(b"\r\n", 1)[0]
        if b" 101 " not in status + b" ":
            raise ConnectionError("handshake failed: %s" % status.decode("latin-1"))
        accept = base64.b64encode(hashlib.sha1(
            (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest())
        if accept not in head:
            raise ConnectionError("bad Sec-WebSocket-Accept")

    def _read(self, n, deadline=None):
        while len(self.buf) < n:
            if deadline is not None:
                left = deadline - time.time()
                if left <= 0:
                    raise socket.timeout("message took too long")
                self.sock.settimeout(left)
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def _read_until(self, marker):
        while marker not in self.buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("closed during handshake")
            self.buf += chunk
            if len(self.buf) > 65536:
                raise ConnectionError("handshake too long")
        i = self.buf.index(marker) + len(marker)
        out, self.buf = self.buf[:i], self.buf[i:]
        return out

    def _send_frame(self, opcode, payload):
        head = bytes([0x80 | opcode])
        n = len(payload)
        if n < 126:
            head += bytes([0x80 | n])
        elif n < 65536:
            head += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            head += bytes([0x80 | 127]) + struct.pack(">Q", n)
        mask = os.urandom(4)
        body = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(head + mask + body)

    def send(self, text):
        self._send_frame(0x1, text.encode("utf-8"))

    MAX_MESSAGE = 1024 * 1024

    def recv(self, deadline=None):
        """Return the next text message, or None when the server closes.
        A message (all its fragments together) may be at most MAX_MESSAGE
        bytes and must arrive before the deadline (a time.time() value)."""
        parts = []
        total = 0
        while True:
            b1, b2 = self._read(2, deadline)
            opcode = b1 & 0x0F
            n = b2 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._read(2, deadline))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._read(8, deadline))[0]
            if opcode < 0x8:
                total += n
                if total > self.MAX_MESSAGE:
                    raise ConnectionError("message too large")
            elif n > 125:
                raise ConnectionError("bad control frame")
            mask = self._read(4, deadline) if b2 & 0x80 else None
            data = self._read(n, deadline)
            if mask:
                data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))
            if opcode == 0x9:
                self._send_frame(0xA, data)
                continue
            if opcode == 0xA:
                continue
            if opcode == 0x8:
                return None
            parts.append(data)
            if b1 & 0x80:
                return b"".join(parts).decode("utf-8", "replace")

    def close(self):
        try:
            self._send_frame(0x8, b"")
        except Exception:
            pass
        try:
            self.sock.close()
        except Exception:
            pass


# ------------------------------------------------------- relay operations

def _each_relay(relays, work, timeout):
    """Run work(url) on every relay at once; return {url: result or Exception}."""
    results = {}

    def run(url):
        try:
            results[url] = work(url)
        except Exception as e:
            results[url] = e
    threads = [threading.Thread(target=run, args=(u,), daemon=True) for u in relays]
    for t in threads:
        t.start()
    end = time.time() + timeout + 1
    for t in threads:
        t.join(max(0, end - time.time()))
    return results


def publish(event, relays, timeout=8):
    """Send an event to the relays. Returns {url: (accepted, message)}."""
    def work(url):
        ws = WebSocket(url, timeout=timeout)
        try:
            ws.send(json.dumps(["EVENT", event], ensure_ascii=False))
            deadline = time.time() + timeout
            while time.time() < deadline:
                msg = ws.recv(deadline)
                if msg is None:
                    return (False, "closed")
                data = json.loads(msg)
                if data and data[0] == "OK" and data[1] == event["id"]:
                    return (bool(data[2]), data[3] if len(data) > 3 else "")
                if data and data[0] == "NOTICE":
                    return (False, str(data[1]))
            return (False, "no answer")
        finally:
            ws.close()
    out = {}
    for url, r in _each_relay(relays, work, timeout).items():
        out[url] = r if isinstance(r, tuple) else (False, str(r))
    return out


def query(filters, relays, timeout=8, limit_per_relay=500, min_pow=0):
    """Ask the relays for events matching the filters (a list of dicts).
    Returns verified events, without duplicates. Events with less than
    min_pow bits of proof of work are dropped before the (slow) signature
    check."""
    sub = secrets.token_hex(6)

    def work(url):
        ws = WebSocket(url, timeout=timeout)
        got = []
        try:
            ws.send(json.dumps(["REQ", sub] + list(filters)))
            deadline = time.time() + timeout
            try:
                while time.time() < deadline and len(got) < limit_per_relay:
                    msg = ws.recv(deadline)
                    if msg is None:
                        break
                    data = json.loads(msg)
                    if not isinstance(data, list) or not data:
                        continue
                    if data[0] == "EVENT" and len(data) > 2:
                        got.append(data[2])
                    elif data[0] in ("EOSE", "CLOSED"):
                        break
            except (OSError, ValueError):
                # slow, oversized or garbled: keep what arrived before it
                pass
            try:
                ws.send(json.dumps(["CLOSE", sub]))
            except Exception:
                pass
            return got
        finally:
            ws.close()
    seen = {}
    for url, r in _each_relay(relays, work, timeout).items():
        if isinstance(r, Exception):
            continue
        for ev in r:
            if not well_formed(ev) or ev["id"] in seen:
                continue
            if min_pow and pow_bits(ev["id"]) < min_pow:
                continue
            if verify_event(ev):
                seen[ev["id"]] = ev
    return list(seen.values())
