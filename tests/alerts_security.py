"""Checks for the traffic alerts backend against hostile relays.

Run from the maps folder:  python3 -I tests/alerts_security.py
No network: a local fake WebSocket server stands in for a relay.
"""
import base64, hashlib, os, socket, struct, sys, threading, time, types

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.join(os.path.dirname(HERE), "overlay", "share", "pure-maps.jonnius")
sys.path.insert(0, PKG)
sent = []
sys.modules["pyotherside"] = types.SimpleNamespace(send=lambda *a: sent.append(a),
                                                   atexit=lambda *a: None)
# import the two modules alone, without the whole poor package
poor = types.ModuleType("poor"); poor.__path__ = [os.path.join(PKG, "poor")]
poor.CACHE_HOME_DIR = "/nonexistent"
sys.modules["poor"] = poor
from poor import nostr, alerts  # noqa: E402

failures = 0


def check(name, cond):
    global failures
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        failures += 1


def reset():
    alerts._state.update(community={}, votes={}, dismissed=set(), last=[], last_box=None)


def report_event(kind="police", lat=40.4168, lon=-3.7038, pow=alerts.POW_BITS, created=None, extra=()):
    tags = [["t", alerts.TOPIC], ["alert", kind], ["lat", str(lat)], ["lon", str(lon)]] + list(extra)
    return nostr.sign_event(alerts.KIND, tags, "", pow=pow, created_at=created)


def vote_event(rid, up, created=None, sk=None):
    tags = [["t", alerts.TOPIC], ["vote", "up" if up else "down"], ["e", rid]]
    return nostr.sign_event(alerts.KIND, tags, "", sk_hex=sk, pow=alerts.POW_BITS, created_at=created)


# --- 1. malformed input never raises and never drops good events -------------
reset()
good = report_event()
bad = [None, 5, "x", [], {}, {"id": "zz"},
       dict(good, created_at="1"), dict(good, created_at=True), dict(good, created_at=1e400),
       dict(good, tags="nope"), dict(good, tags=[1, 2]), dict(good, tags=[["t", None]]),
       dict(good, kind=None), dict(good, pubkey=123)]
for lat in ("nan", "inf", "-inf", "1e400", "91", "abc", None):
    bad.append(report_event(lat=lat if lat is not None else "", pow=alerts.POW_BITS))
bad.append(report_event(extra=[["heading", "1e999"]]))   # bad heading only: kept, heading -1
try:
    alerts._merge_community(bad + [good])
    raised = False
except Exception as e:
    raised = e
check("malformed events don't raise (%s)" % raised, raised is False)
check("good event kept beside bad ones", good["id"] in alerts._state["community"])
lats_ok = all(-90 <= a["lat"] <= 90 for a in alerts._state["community"].values())
check("only finite, in-range coordinates kept", lats_ok)
hd = [a["heading"] for a in alerts._state["community"].values() if a["id"] != good["id"]]
check("non-finite heading becomes -1", hd == [-1])
check("well_formed rejects non-dict", not nostr.well_formed([1]))

# --- 2. proof of work, one vote per key, capped lifetime --------------------
reset()
weak = report_event(pow=0)
alerts._merge_community([weak])
check("report without proof of work dropped", weak["id"] not in alerts._state["community"])

now = int(time.time())
rep = report_event(created=now - 60)
alerts._merge_community([rep])
sk = nostr.make_key()
alerts._merge_community([vote_event(rep["id"], False, now - 50, sk),
                         vote_event(rep["id"], False, now - 40, sk)])
vis = {a["id"]: a for a in alerts._community_visible()}
check("two downs from one key count once", vis.get(rep["id"], {}).get("down") == 1)
alerts._merge_community([vote_event(rep["id"], False, now - 30)])
vis = {a["id"]: a for a in alerts._community_visible()}
check("two downs from two keys hide it", rep["id"] not in vis)

reset()
life = alerts.LIFETIME["police"]
old = report_event(created=now - 3 * life - 120)
alerts._merge_community([old] + [vote_event(old["id"], True, now - 5)])
vis = {a["id"]: a for a in alerts._community_visible()}
check("late confirmations can't keep a report past %d lifetimes" % alerts.MAX_LIFETIMES,
      old["id"] not in vis)
reset()
mid = report_event(created=now - life - 60)
alerts._merge_community([mid, vote_event(mid["id"], True, now - 30)])
vis = {a["id"]: a for a in alerts._community_visible()}
check("a fresh confirmation extends a report within the cap", mid["id"] in vis)

# --- 3. WebSocket: fragment flood and slow drip ------------------------------


def fake_relay(behaviour):
    srv = socket.socket(); srv.bind(("127.0.0.1", 0)); srv.listen(1)

    def run():
        c, _ = srv.accept()
        req = b""
        while b"\r\n\r\n" not in req:
            req += c.recv(4096)
        key = [l.split(b": ", 1)[1] for l in req.split(b"\r\n") if l.lower().startswith(b"sec-websocket-key")][0]
        acc = base64.b64encode(hashlib.sha1(key + b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest())
        c.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                  b"Sec-WebSocket-Accept: " + acc + b"\r\n\r\n")
        try:
            behaviour(c)
        except OSError:
            pass
        finally:
            c.close(); srv.close()
    threading.Thread(target=run, daemon=True).start()
    return "ws://127.0.0.1:%d/" % srv.getsockname()[1]


def flood(c):
    chunk = b"a" * 65535
    c.sendall(bytes([0x01, 126]) + struct.pack(">H", len(chunk)) + chunk)   # text, not final
    for _ in range(200):                                                    # 13 MB of continuations
        c.sendall(bytes([0x00, 126]) + struct.pack(">H", len(chunk)) + chunk)


def drip(c):
    c.sendall(bytes([0x81, 126]) + struct.pack(">H", 1000))
    for _ in range(100):
        c.sendall(b"a"); time.sleep(0.2)


ws = nostr.WebSocket(fake_relay(flood), timeout=5)
try:
    ws.recv(time.time() + 5); err = None
except Exception as e:
    err = e
check("fragment flood stopped at %d bytes (%s)" % (ws.MAX_MESSAGE, err),
      isinstance(err, ConnectionError) and "too large" in str(err))
ws.close()

ws = nostr.WebSocket(fake_relay(drip), timeout=5)
t = time.time()
try:
    ws.recv(time.time() + 1.5); err = None
except Exception as e:
    err = e
took = time.time() - t
check("slow drip ends at the deadline (%.1f s, %s)" % (took, type(err).__name__),
      isinstance(err, OSError) and took < 3)
ws.close()

t = time.time()
got = nostr.query([{"kinds": [alerts.KIND]}], [fake_relay(drip)], timeout=1.5)
check("query against a dripping relay returns in time (%.1f s)" % (time.time() - t),
      got == [] and time.time() - t < 4)

# --- 4. strict hex, mixed batches, byte budget, eviction ---------------------


def send_text(c, s):
    b = s.encode()
    if len(b) < 126:
        c.sendall(bytes([0x81, len(b)]) + b)
    elif len(b) < 65536:
        c.sendall(bytes([0x81, 126]) + struct.pack(">H", len(b)) + b)
    else:
        c.sendall(bytes([0x81, 127]) + struct.pack(">Q", len(b)) + b)


import json  # noqa: E402
good2 = report_event(kind="jam")
spaced = dict(good2, id=good2["id"][:10] + " " + good2["id"][11:])
check("id with a space is not well formed", not nostr.well_formed(spaced))
check("pow_bits of non-hex is 0", nostr.pow_bits("00 0" + "f" * 60) == 0 and nostr.pow_bits(None) == 0)


def mixed(c):
    c.recv(65536)   # the REQ
    for ev in (spaced, {"id": 5}, "junk", good2):
        send_text(c, json.dumps(["EVENT", "s", ev]))
    send_text(c, json.dumps(["EOSE", "s"]))
    time.sleep(0.5)


got = nostr.query([{"kinds": [alerts.KIND]}], [fake_relay(mixed)], timeout=4, min_pow=alerts.POW_BITS)
check("bad events in a batch don't lose the good one", [e["id"] for e in got] == [good2["id"]])

big_sent = []


def hoard(c):
    c.recv(65536)
    pad = "x" * (900 * 1024)
    for i in range(40):   # 36 MB if nothing stopped it
        send_text(c, json.dumps(["NOTICE", pad]))
        big_sent.append(i)


t = time.time()
got = nostr.query([{"kinds": [alerts.KIND]}], [fake_relay(hoard)], timeout=6)
time.sleep(0.3)
check("relay byte budget stops reading (%d messages read before the stop)" % len(big_sent),
      got == [] and len(big_sent) < 40 and time.time() - t < 8)

reset()
alerts._state["points"] = [[-3.70, 40.41]]
for i in range(alerts.MAX_REPORTS):   # fill with old reports far away, no mining needed
    alerts._state["community"]["%064x" % i] = {"id": "%064x" % i, "type": "jam", "lat": 50.0,
                                               "lon": 10.0, "created": now - 3000, "heading": -1}
fresh = report_event(kind="closed")
alerts._merge_community([fresh])
check("a full report table makes room instead of refusing (%d left)" % len(alerts._state["community"]),
      fresh["id"] in alerts._state["community"] and len(alerts._state["community"]) <= alerts.MAX_REPORTS)

reset()
rid = "ab" * 32
alerts._state["votes"][rid] = {"%064x" % i: (False, now - 3000) for i in range(alerts.MAX_VOTES_PER_REPORT)}
v = vote_event(rid, True, now - 10)
alerts._merge_community([v])
vs = alerts._state["votes"][rid]
check("a full vote list drops its oldest vote for a newer one",
      v["pubkey"] in vs and len(vs) == alerts.MAX_VOTES_PER_REPORT)

# --- signatures still right ---------------------------------------------------
ev = nostr.sign_event(1, [["t", "x"]], "hi", pow=8)
check("signed event with proof of work verifies", nostr.verify_event(ev) and nostr.pow_bits(ev["id"]) >= 8)
ev2 = dict(ev, content="changed")
check("tampered event fails", not nostr.verify_event(ev2))

print("\n%d failure(s)" % failures)
sys.exit(1 if failures else 0)
