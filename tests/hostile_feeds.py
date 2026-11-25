"""Hostile replies for the fuel price and official incident readers.

    python3 -I tests/hostile_feeds.py [PKG] [CACHE_DIR]

PKG is the folder holding poor/ (default: this repo's overlay). On the phone, run it inside the
app's AppArmor profile against the installed click:

    runuser -u phablet -- aa-exec -p libremaps.juujbyg_pure-maps_<version> -- \\
        python3 -I ~/.cache/libremaps.juujbyg/hostile_feeds.py \\
        /opt/click.ubuntu.com/libremaps.juujbyg/current/share/libremaps.juujbyg \\
        ~/.cache/libremaps.juujbyg/hostile-test

Every download is answered by a loopback server with a broken or malicious reply: oversized,
memory bombs, deep nesting, XML entity tricks, links to other servers, markup in text that
the screen shows, garbage values. Each case runs in a forked child so its peak memory can be
measured. Any request that reaches /leak/ is a failure: nothing should ever fetch it.
"""
import gzip, http.server, json, os, sys, tempfile, threading, time, types, warnings
warnings.filterwarnings("ignore", category=DeprecationWarning)  # fork() with the server thread

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(HERE), "overlay", "share", "pure-maps.jonnius")
CACHE = sys.argv[2] if len(sys.argv) > 2 else tempfile.mkdtemp()
os.makedirs(CACHE, exist_ok=True)
sys.path.insert(0, PKG)
poor = types.ModuleType("poor"); poor.__path__ = [os.path.join(PKG, "poor")]
poor.CACHE_HOME_DIR = CACHE
sys.modules["poor"] = poor
pyo = types.ModuleType("pyotherside"); pyo.send = lambda *a, **k: None
sys.modules["pyotherside"] = pyo
from poor import fuelprices as fp, alerts as al  # noqa: E402

MB = 1 << 20
leaks = []
NOW = time.time()


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime(t))


# ------------------------------------------------------------------ payloads (generators)

def repeat(head, unit, count, tail):
    def gen():
        yield head
        block = unit * 4096
        n = count
        while n >= 4096:
            yield block
            n -= 4096
        yield unit * n + tail
    return gen


def once(data):
    return lambda: iter([data])


def gzip_of(gen):
    def out():
        c = __import__("zlib").compressobj(6, 8, 31)
        for chunk in gen():
            d = c.compress(chunk)
            if d:
                yield d
        yield c.flush()
    return out


LAUGHS = (b'<?xml version="1.0"?><!DOCTYPE lolz [<!ENTITY lol "lol">'
          + b"".join(b'<!ENTITY lol%d "%s">' % (i, (b"&lol%d;" % (i - 1) if i > 1 else b"&lol;") * 10)
                     for i in range(1, 10))
          + b']>')
XXE = b'<?xml version="1.0"?><!DOCTYPE d [<!ENTITY ext SYSTEM "http://127.0.0.1:%d/leak/xxe">]>'
HTML = '<img src="http://127.0.0.1:%d/leak/img">'


def datex_record(rid, lat="45.75", lon="4.85", road="A7", town="Lyon", rtype="Accident"):
    return ('<situationRecord xsi:type="%s" id="%s"><validity><validityStatus>active</validityStatus>'
            '<validityTimeSpecification><overallStartTime>%s</overallStartTime></validityTimeSpecification>'
            '</validity><roadNumber>%s</roadNumber><municipality>%s</municipality>'
            '<pointByCoordinates><latitude>%s</latitude><longitude>%s</longitude></pointByCoordinates>'
            '</situationRecord>' % (rtype, rid, iso(NOW - 600), road, town, lat, lon))


def datex(records, prolog=""):
    return (prolog + '<d xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' + "".join(records) + "</d>").encode()


def build(port):
    html = HTML % port
    big_name = "N" + "9" * (2 * MB)
    return {
        # France fuel: JSON
        "/fr-deep": (once(b"[" * 200000 + b"]" * 200000), "application/json", None),
        "/fr-bomb": (repeat(b"[", b"[],", 10 * MB, b"[]]"), "application/json", None),
        "/fr-small-bomb": (repeat(b"[", b"[],", 1700000, b"[]]"), "application/json", None),   # 5 MB, under the cap
        "/fr-big":(repeat(b'["', b"x", 40 * MB, b'"]'), "application/json", None),
        "/fr-junk": (once(json.dumps([
            {"geom": {"lat": 48.9, "lon": 2.3}, "gazole_prix": "1.799", "sp95_prix": "1e9",
             "e10_prix": "-1", "sp98_prix": html, "gazole_maj": "not a date"},
            {"geom": {"lat": "nan", "lon": "inf"}, "gazole_prix": 1.5},
            {"geom": [1, 2], "gazole_prix": {"x": 1}},
            {"geom": None},
            "not an object", 7, None,
            {"geom": {"lat": 1e308, "lon": -1e308}, "gazole_prix": True},
        ]).encode()), "application/json", None),
        # Slovenia: the next page points elsewhere
        "/si-next": (once(json.dumps({"results": [], "next": "http://127.0.0.1:%d/leak/next" % port}).encode()),
                     "application/json", None),
        # Italy: CSV with a 2 MB field, NUL bytes and broken lines
        "/it-stations": (once(b"Estrazione del x\nh\n1|a|" + b"B" * (2 * MB) + b"|x|x|x|x|x|41.9|12.5\n\0\0\0|||\n"),
                         "text/csv", None),
        "/it-prices": (once(b"Estrazione del x\nh\n1|Benzina|1.799|1|x\n"), "text/csv", None),
        # Mexico: XML entity tricks
        "/mx-laughs": (once(LAUGHS + b"<places><place place_id='1'><name>&lol9;</name></place></places>"),
                       "application/xml", None),
        "/mx-xxe": (once(XXE % port + b"<places><place place_id='1'><name>&ext;</name>"
                     b"<location><x>-99</x><y>19</y></location></place></places>"), "application/xml", None),
        # Incidents: DATEX II (France's reader, DGT's shares the parser)
        "/dx-badcoord": (once(datex([datex_record("good1"), datex_record("bad", lat="abc"),
                                     datex_record("good2", lat="45.76")])), "application/xml", None),
        "/dx-html": (once(datex([datex_record("h1", road=html.replace("<", "&lt;"), town=html.replace("<", "&lt;"))])),
                     "application/xml", None),
        "/dx-long": (once(datex([datex_record("l1", road=big_name, town="T" * MB)])), "application/xml", None),
        "/dx-nan": (once(datex([datex_record("n1", lat="nan", lon="nan"), datex_record("n2", lat="1e999", lon="4.8"),
                                datex_record("n3", lat="95", lon="4.8")])), "application/xml", None),
        "/dx-laughs": (once(LAUGHS + b'<d><situationRecord id="x"><roadNumber>&lol9;</roadNumber></situationRecord></d>'),
                       "application/xml", None),
        "/dx-xxe": (once(XXE % port + b'<d><situationRecord id="x"><roadNumber>&ext;</roadNumber></situationRecord></d>'),
                    "application/xml", None),
        "/dx-flood": (gzip_of(repeat(b'<d xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">',
                                     datex_record("f").encode(), 150000, b"</d>")), "application/xml", "gzip"),
        # valid XML (a root, then 1 GB of spaces) so the parser keeps reading until the cap
        "/dx-gzbomb": (lambda: iter([gzip.compress(b"<d>")] + [gzip.compress(b" " * (16 * MB), 9)] * 64),
                       "application/xml", "gzip"),
        # Germany: Autobahn JSON
        "/de-junk": (once(json.dumps({"warning": [
            {"coordinate": {"lat": "48.3", "long": "11.55"}, "title": "A9 | " + html, "subtitle": "x" * MB,
             "identifier": "i" * MB, "startTimestamp": "garbage", "description": [html] * 3},
            {"coordinate": {"lat": "nan", "long": "nan"}, "title": "nan"},
            {"coordinate": "nope"}, 5, None, "str",
        ]}).encode()), "application/json", None),
        "/de-deep": (once(b'{"warning":' + b"[" * 200000 + b"]" * 200000 + b"}"), "application/json", None),
        "/de-bomb": (repeat(b'{"warning":[', b"{},", 5 * MB, b"{}]}"), "application/json", None),
    }


class Handler(http.server.BaseHTTPRequestHandler):
    payloads = {}

    def do_GET(self):
        path = self.path.split("?")[0]
        if path.startswith("/leak/"):
            leaks.append(path)
        for key, (gen, ctype, enc) in self.payloads.items():
            if path.startswith(key):
                self.send_response(200)
                self.send_header("Content-Type", ctype)
                if enc:
                    self.send_header("Content-Encoding", enc)
                self.end_headers()
                try:
                    for chunk in gen():
                        self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    pass
                return
        self.send_response(404)
        self.end_headers()

    def log_message(self, *a):
        pass


def mem(field):
    with open("/proc/self/status") as f:
        for line in f:
            if line.startswith(field + ":"):
                return int(line.split()[1]) // 1024
    return 0


def summary(res):
    if isinstance(res, str):
        return res
    if isinstance(res, dict) and "stations" in res:
        res = res["stations"]
    if isinstance(res, list):
        first = res[0] if res else None
        if isinstance(first, dict):
            first = {k: (v[:40] + "..." if isinstance(v, str) and len(v) > 40 else v)
                     for k, v in first.items() if k in ("lat", "lon", "road", "town", "dest")}
        return "%d item(s)%s" % (len(res), ", first %s" % json.dumps(first, default=str)[:150] if res else "")
    return repr(res)[:100]


def run_case(fn, check):
    """Run fn in a forked child; it reports (check passed, summary, seconds, extra peak MB).
    A download that raises counts as no data, as the app's callers treat it."""
    r, w = os.pipe()
    pid = os.fork()
    if pid == 0:
        os.close(r)
        base = mem("VmRSS")
        t = time.time()
        try:
            res = fn()
            shown = summary(res)
        except Exception as e:
            res, shown = None, "refused (%s: %s)" % (type(e).__name__, str(e)[:70])
        secs = round(time.time() - t, 1)
        try:
            good = bool(check(res))
        except Exception as e:
            good, shown = False, "check failed: %r; %s" % (e, shown)
        out = json.dumps({"good": good, "res": shown, "secs": secs, "peak": mem("VmHWM") - base})
        os.write(w, out.encode())
        os._exit(0)
    os.close(w)
    data = b""
    while True:
        chunk = os.read(r, 65536)
        if not chunk:
            break
        data += chunk
    os.waitpid(pid, 0)
    try:
        return json.loads(data.decode())
    except ValueError:
        return {"good": False, "res": "child died", "secs": 0, "peak": -1}


def main():
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port = srv.server_address[1]
    Handler.payloads = build(port)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    base = "http://127.0.0.1:%d" % port

    def fr(path):
        fp.FR_URL = base + path + "?"
        return fp._fr_fetch(48.9, 2.3)

    def dx(path):
        al.FR_URL = base + path
        return al._fetch_fr()

    def de(path):
        al.DE_URL = base + path + "/%s/%s"
        return al._fetch_de_road("A9")

    def stations(res):
        return res["stations"] if isinstance(res, dict) else (res or [])

    def texts(res):
        return [s for a in (res if isinstance(res, list) else []) for s in (a["road"], a["town"], a["dest"])]

    def ok_markup(res):
        return isinstance(res, list) and all("<" not in s for s in texts(res))

    def ok_short(res):
        return isinstance(res, list) and all(len(s) <= 200 for s in texts(res))

    def finite(res):
        import math
        return isinstance(res, list) and all(math.isfinite(a["lat"]) and math.isfinite(a["lon"])
                                             and -90 <= a["lat"] <= 90 and -180 <= a["lon"] <= 180 for a in res)

    def si():
        fp.SI_URL = base + "/si-next?%.2f,%.2f"
        return fp._si_fetch(46.05, 14.5)

    def it():
        fp.IT_STATIONS, fp.IT_PRICES = base + "/it-stations", base + "/it-prices"
        return fp._it_fetch()

    def mx(path):
        fp.MX_PLACES = fp.MX_PRICES = base + path
        return fp._mx_fetch()

    # name, function, check(result) -> bool, max seconds, max extra MB
    cases = [
        ("FR fuel: nesting 200,000 deep", lambda: fr("/fr-deep"), lambda r: not stations(r), 10, 64),
        ("FR fuel: 30 MB of tiny lists (memory bomb)", lambda: fr("/fr-bomb"), lambda r: not stations(r), 30, 120),
        ("FR fuel: 5 MB of tiny lists (under the size cap)", lambda: fr("/fr-small-bomb"),
         lambda r: not stations(r), 30, 64),
        ("FR fuel: 40 MB reply (over the cap)", lambda: fr("/fr-big"), lambda r: not stations(r), 30, 120),
        ("FR fuel: garbage values, markup as a price", lambda: fr("/fr-junk"),
         lambda r: stations(r) == [[48.9, 2.3, "", "", [["Diesel", "1.799"]], ""]], 10, 64),
        ("SI fuel: next page on another server", si, lambda r: stations(r) == [], 10, 64),
        ("IT fuel: 2 MB CSV field, NUL bytes", it, lambda r: True, 30, 120),
        ("MX fuel: billion laughs", lambda: mx("/mx-laughs"), lambda r: not stations(r), 15, 120),
        ("MX fuel: external entity", lambda: mx("/mx-xxe"), lambda r: True, 15, 64),
        ("Incidents: one bad coordinate keeps the rest", lambda: dx("/dx-badcoord"),
         lambda r: isinstance(r, list) and len(r) == 2, 10, 64),
        ("Incidents: markup in road and town", lambda: dx("/dx-html"), ok_markup, 10, 64),
        ("Incidents: 2 MB road name", lambda: dx("/dx-long"), ok_short, 10, 120),
        ("Incidents: NaN, infinite and impossible coordinates", lambda: dx("/dx-nan"), finite, 10, 64),
        ("Incidents: billion laughs", lambda: dx("/dx-laughs"), lambda r: not r, 15, 120),
        ("Incidents: external entity", lambda: dx("/dx-xxe"), lambda r: True, 15, 64),
        ("Incidents: 150,000 records (flood)", lambda: dx("/dx-flood"),
         lambda r: not isinstance(r, list) or len(r) <= 20000, 120, 250),
        ("Incidents: gzip bomb (1 GB unpacked)", lambda: dx("/dx-gzbomb"), lambda r: not r, 60, 150),
        ("Autobahn: garbage, markup, 1 MB strings", lambda: de("/de-junk"),
         lambda r: ok_markup(r) and ok_short(r) and len(r) == 1, 10, 64),
        ("Autobahn: nesting 200,000 deep", lambda: de("/de-deep"), lambda r: not r, 10, 64),
        ("Autobahn: 15 MB of tiny objects (memory bomb)", lambda: de("/de-bomb"), lambda r: not r, 30, 120),
    ]
    only = os.environ.get("ONLY")
    failures = 0
    for name, fn, check, max_s, max_mb in cases:
        if only and only not in name:
            continue
        got = run_case(fn, check)
        slow, fat = got["secs"] > max_s, got["peak"] > max_mb
        bad = not got["good"] or slow or fat or got["peak"] < 0
        failures += bad
        print("%s %-52s %5.1f s %5d MB  %s" % ("FAIL" if bad else "ok  ", name, got["secs"], got["peak"], got["res"][:110]))
    if leaks:
        failures += 1
        print("FAIL requests reached the leak listener:", sorted(set(leaks)))
    else:
        print("ok   no request reached the leak listener")
    srv.shutdown()
    print("%d failure(s)" % failures)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
