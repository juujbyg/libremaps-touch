"""Size caps on network replies (poor/netlimit.py): a loopback server sends replies over the cap
and a gzip bomb; each must be refused, and normal replies must still read in full. No internet.
Usage: python3 -I tests/netlimit_check.py"""
import gzip, http.server, io, os, sys, threading, types, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.join(os.path.dirname(HERE), "overlay", "share", "pure-maps.jonnius")
sys.path.insert(0, PKG)
sys.modules["pyotherside"] = types.SimpleNamespace(send=lambda *a: None, atexit=lambda *a: None)
poor = types.ModuleType("poor"); poor.__path__ = [os.path.join(PKG, "poor")]
poor.CACHE_HOME_DIR = "/nonexistent"
sys.modules["poor"] = poor
from poor import netlimit, alerts, offline  # noqa: E402

SIZE = {"/small": 1000, "/exact": 4096, "/big": 4097, "/chunked-big": 50000}


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        n = SIZE[self.path]
        self.send_response(200)
        if self.path.startswith("/chunked"):
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            for _ in range(n // 1000):
                self.wfile.write(b"3e8\r\n" + b"x" * 1000 + b"\r\n")
            self.wfile.write(b"0\r\n\r\n")
        else:
            self.send_header("Content-Length", str(n))
            self.end_headers()
            self.wfile.write(b"x" * n)

    def log_message(self, *a):
        pass


class Server(http.server.ThreadingHTTPServer):
    def handle_error(self, request, address):
        pass                      # the client hanging up on an oversized reply is the point


server = Server(("127.0.0.1", 0), Handler)
threading.Thread(target=server.serve_forever, daemon=True).start()
BASE = "http://127.0.0.1:%d" % server.server_port
results = []


def check(name, fn, refused):
    try:
        out = fn()
        ok = not refused
        detail = "%d bytes" % len(out) if isinstance(out, (bytes, list)) else str(out)
    except netlimit.TooLarge as e:
        ok, detail = refused, "refused: %s" % e
    results.append(ok)
    print("%s %s (%s)" % ("ok  " if ok else "BAD ", name, detail))


def get(path, limit=4096):
    with urllib.request.urlopen(BASE + path, timeout=5) as r:
        return netlimit.read_capped(r, limit)


check("small reply reads in full", lambda: get("/small"), False)
check("reply of exactly the cap reads", lambda: get("/exact"), False)
check("one byte over the cap is refused", lambda: get("/big"), True)
check("chunked reply over the cap is refused", lambda: get("/chunked-big", 40000), True)

# A gzip bomb for the DGT parser: 300 MB of zeros, about 0.3 MB compressed.
bomb = io.BytesIO()
with gzip.GzipFile(fileobj=bomb, mode="wb", compresslevel=9) as z:
    chunk = b"<a>" + b" " * (1 << 20)
    for _ in range(300):
        z.write(chunk)
data = bomb.getvalue()
check("DGT gzip bomb (%.1f MB compressed) is refused" % (len(data) / 1e6),
      lambda: alerts._parse_dgt(netlimit.CappedReader(gzip.GzipFile(fileobj=io.BytesIO(data)), netlimit.FEED_XML)),
      True)
real = gzip.compress(b'<?xml version="1.0"?><d xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"></d>')
check("a normal small feed still parses",
      lambda: alerts._parse_dgt(netlimit.CappedReader(gzip.GzipFile(fileobj=io.BytesIO(real)), netlimit.FEED_XML)),
      False)

# The app's own offline fetch, with its cap lowered for the test.
netlimit.TILE = 4096
check("offline fetch: a tile over the cap is refused", lambda: offline.fetch(BASE + "/big", tries=1), True)
check("offline fetch: a normal tile reads", lambda: offline.fetch(BASE + "/small", tries=1), False)

server.shutdown()
print("%d/%d passed" % (sum(results), len(results)))
sys.exit(0 if all(results) else 1)
