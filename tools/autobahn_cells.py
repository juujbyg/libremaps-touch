#!/usr/bin/env python3
"""Rebuild overlay/.../poor/autobahn_cells.json: which quarter-degree cells each German motorway
passes through, so the app asks the Autobahn API only about the motorways near a route.

Run from the maps folder:  python3 -I tools/autobahn_cells.py
One Overpass query (about 30 MB, a few minutes) and one request to the Autobahn API.
Data: OpenStreetMap, ODbL, (c) OpenStreetMap contributors.
"""
import collections, datetime, json, os, re, sys, urllib.parse, urllib.request

UA = "LibreMaps-build/0.1 (+https://github.com/juujbyg/libremaps-touch)"
OVERPASS = "https://overpass-api.de/api/interpreter"
QUERY = ('[out:json][timeout:300];area["ISO3166-1"="DE"][admin_level=2]->.de;'
         'way(area.de)[highway=motorway][ref~"^A ?[0-9]+"];out tags center qt;')
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "overlay", "share", "pure-maps.jonnius", "poor", "autobahn_cells.json")


def get(url, data=None, timeout=60):
    req = urllib.request.Request(url, data=data, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


def main():
    api = set(get("https://verkehr.autobahn.de/o/autobahn/")["roads"])
    ways = get(OVERPASS, urllib.parse.urlencode({"data": QUERY}).encode(), timeout=400)["elements"]
    cells = collections.defaultdict(set)
    for w in ways:
        c = w.get("center")
        if not c:
            continue
        for r in w.get("tags", {}).get("ref", "").split(";"):
            m = re.match(r"\s*A\s?(\d+)\s*([a-z]?)", r)
            name = m and "A%d%s" % (int(m.group(1)), m.group(2))
            if name in api:
                cells[name].add((int(c["lat"] * 4 // 1), int(c["lon"] * 4 // 1)))
    out = {"about": "German motorways (Autobahn API road names) and the quarter-degree cells "
                    "[floor(lat*4), floor(lon*4)] each one passes through. Derived from OpenStreetMap "
                    "(ODbL, (c) OpenStreetMap contributors) on %s by maps/tools/autobahn_cells.py."
                    % datetime.date.today().isoformat(),
           "roads": {k: sorted(map(list, v))
                     for k, v in sorted(cells.items(), key=lambda kv: (len(kv[0]), kv[0]))}}
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, separators=(",", ":"))
    print("%d of %d roads; missing: %s" % (len(cells), len(api), ", ".join(sorted(api - set(cells)))))


if __name__ == "__main__":
    sys.exit(main())
