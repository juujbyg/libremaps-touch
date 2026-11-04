# -*- coding: utf-8 -*-
"""LibreMaps offline maps: download one region of OpenFreeMap vector tiles,
glyphs and sprites into the app's data folder, then write an offline copy of
the Drive styles that reads them (mbtiles:// and file://).

Python standard library only. Tile download code follows
goals/offline-maps/offline_region.py.  Outside services used: tiles.openfreemap.org.
"""
import concurrent.futures
import gzip
import json
import math
import os
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

import poor

TILEJSON = "https://tiles.openfreemap.org/planet"
FONTS = "https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf"
FONTSTACKS = ["Noto Sans Regular", "Noto Sans Bold"]
GLYPH_RANGES = list(range(0, 0x3000, 256)) + list(range(0xFB00, 0x10000, 256))  # no CJK
SPRITE = "https://tiles.openfreemap.org/sprites/ofm_f384/ofm"
USER_AGENT = "LibreMaps-offline/0.1 (+https://github.com/juujbyg)"
WORKERS = 4
MAXZOOM = 14

# Named regions (a style reads one file, so regions must not overlap)
REGIONS = [
    {"id": "madrid", "label": "Comunidad de Madrid", "bbox": [-4.58, 39.88, -3.05, 41.17]},
]

_cancel = threading.Event()


def folder():
    return os.path.join(poor.DATA_HOME_DIR, "offline")


def region_file(rid):
    return os.path.join(folder(), rid + ".mbtiles")


def installed():
    """Ids of regions with a finished file (marked by a '.done' file)."""
    out = []
    for r in REGIONS:
        if os.path.exists(region_file(r["id"]) + ".done"):
            out.append(r["id"])
    return out


def status():
    inst = installed()
    res = []
    for r in REGIONS:
        p = region_file(r["id"])
        size = os.path.getsize(p) if os.path.exists(p) else 0
        res.append({"id": r["id"], "label": r["label"], "installed": r["id"] in inst,
                    "size": size, "tiles_est": count_tiles(r["bbox"], 0, MAXZOOM)})
    return res


def cancel():
    _cancel.set()


def fetch(url, tries=4):
    for attempt in range(tries):
        if _cancel.is_set():
            raise InterruptedError
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if attempt == tries - 1:
                raise
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt == tries - 1:
                raise
        time.sleep(2 ** attempt)


def tile_range(bbox, z):
    w, s, e, n = bbox
    count = 2 ** z

    def x_of(lon):
        return min(count - 1, max(0, int((lon + 180) / 360 * count)))

    def y_of(lat):
        lat = max(-85.05112878, min(85.05112878, lat))
        r = math.radians(lat)
        return min(count - 1, max(0, int((1 - math.asinh(math.tan(r)) / math.pi) / 2 * count)))

    return x_of(w), x_of(e), y_of(n), y_of(s)


def tiles(bbox, minzoom, maxzoom):
    for z in range(minzoom, maxzoom + 1):
        x0, x1, y0, y1 = tile_range(bbox, z)
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                yield z, x, y


def count_tiles(bbox, minzoom, maxzoom):
    total = 0
    for z in range(minzoom, maxzoom + 1):
        x0, x1, y0, y1 = tile_range(bbox, z)
        total += (x1 - x0 + 1) * (y1 - y0 + 1)
    return total


def _open_mbtiles(path, info, bbox, name):
    db = sqlite3.connect(path, check_same_thread=False)
    db.executescript("""
        CREATE TABLE IF NOT EXISTS metadata (name TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS tiles (zoom_level INTEGER, tile_column INTEGER,
            tile_row INTEGER, tile_data BLOB, PRIMARY KEY (zoom_level, tile_column, tile_row));
    """)
    w, s, e, n = bbox
    meta = {"name": name, "format": "pbf", "type": "baselayer", "minzoom": "0",
            "maxzoom": str(MAXZOOM), "bounds": "%s,%s,%s,%s" % (w, s, e, n),
            "center": "%s,%s,%s" % ((w + e) / 2, (s + n) / 2, 10),
            "attribution": info.get("attribution", ""),
            "description": "OpenFreeMap",
            "json": json.dumps({"vector_layers": info.get("vector_layers", [])})}
    db.executemany("INSERT OR REPLACE INTO metadata VALUES (?, ?)", meta.items())
    db.commit()
    return db


def _assets(out, progress):
    os.makedirs(os.path.join(out, "sprites"), exist_ok=True)
    for suffix in ("", "@2x"):
        for ext in ("json", "png"):
            target = os.path.join(out, "sprites", "ofm%s.%s" % (suffix, ext))
            if os.path.exists(target):
                continue
            data = fetch("%s%s.%s" % (SPRITE, suffix, ext))
            if data is None:
                raise RuntimeError("sprite missing")
            with open(target, "wb") as f:
                f.write(data)
    ranges = GLYPH_RANGES
    n = 0
    for stack in FONTSTACKS:
        d = os.path.join(out, "fonts", stack)
        os.makedirs(d, exist_ok=True)
        for start in ranges:
            target = os.path.join(d, "%d-%d.pbf" % (start, start + 255))
            n += 1
            if os.path.exists(target):
                continue
            data = fetch(FONTS.format(fontstack=urllib.parse.quote(stack),
                                      range="%d-%d" % (start, start + 255)))
            with open(target, "wb") as f:
                f.write(data or b"")
            progress("fonts", n, len(ranges) * len(FONTSTACKS))


def download(rid, progress=lambda phase, done, total: None):
    """Download region rid (blocking; run in a thread). Resumable."""
    _cancel.clear()
    region = [r for r in REGIONS if r["id"] == rid][0]
    bbox = region["bbox"]
    out = folder()
    os.makedirs(out, exist_ok=True)
    marker = region_file(rid) + ".done"
    if os.path.exists(marker):
        os.remove(marker)
    _assets(out, progress)
    info = json.loads(fetch(TILEJSON))
    template = info["tiles"][0]
    db = _open_mbtiles(region_file(rid), info, bbox, rid)
    have = {(z, x, (1 << z) - 1 - row) for z, x, row in
            db.execute("SELECT zoom_level, tile_column, tile_row FROM tiles")}
    todo = [t for t in tiles(bbox, 0, MAXZOOM) if t not in have]
    total = len(todo) + len(have)
    done = len(have)
    lock = threading.Lock()

    def get(t):
        z, x, y = t
        return t, fetch(template.format(z=z, x=x, y=y))

    try:
        with concurrent.futures.ThreadPoolExecutor(WORKERS) as pool:
            for (z, x, y), data in pool.map(get, todo):
                with lock:
                    if data is not None:
                        db.execute("INSERT OR REPLACE INTO tiles VALUES (?, ?, ?, ?)",
                                   (z, x, (1 << z) - 1 - y, gzip.compress(data)))
                    done += 1
                    if done % 200 == 0:
                        db.commit()
                        progress("tiles", done, total)
        db.commit()
    finally:
        db.close()
    write_styles(rid)
    open(marker, "w").close()
    progress("done", total, total)


def remove(rid):
    for p in (region_file(rid), region_file(rid) + ".done"):
        if os.path.exists(p):
            os.remove(p)
    inst = installed()
    if inst:
        write_styles(inst[0])
    else:
        for mode in ("night", "day"):
            p = os.path.join(poor.DATA_HOME_DIR, "maps", "drive_offline_%s.json" % mode)
            if os.path.exists(p):
                os.remove(p)


def _strings(v):
    if isinstance(v, str):
        yield v
    elif isinstance(v, dict):
        for x in v.values():
            yield from _strings(x)
    elif isinstance(v, list):
        for x in v:
            yield from _strings(x)


def offline_style(style, name):
    style = json.loads(json.dumps(style))
    base = folder().rstrip("/")
    dropped = {k for k, v in style["sources"].items() if v.get("type") != "vector"}
    for k in dropped:
        del style["sources"][k]
    style["layers"] = [l for l in style["layers"] if l.get("source") not in dropped]
    style["sources"]["openmaptiles"] = {"type": "vector",
                                        "url": "mbtiles://%s/%s.mbtiles" % (base, name)}
    style["glyphs"] = "file://%s/fonts/{fontstack}/{range}.pbf" % base
    style["sprite"] = "file://%s/sprites/ofm" % base
    left = [u for u in _strings(style) if u.startswith(("http://", "https://"))]
    if left:
        raise ValueError("network URLs left: %s" % left[:3])
    return style


def write_styles(rid):
    """Write 'Drive Offline' night and day basemaps that read region rid."""
    maps = os.path.join(poor.DATA_HOME_DIR, "maps")
    os.makedirs(maps, exist_ok=True)
    for mode in ("night", "day"):
        with open(os.path.join(poor.DATA_DIR, "maps", "drive_%s.json" % mode)) as f:
            data = json.load(f)
        data["style_json"] = offline_style(data["style_json"], rid)
        data["provider"] = "Drive Offline"
        data["name"] = "Drive Offline " + mode.capitalize()
        data["profiles"] = ["mixed", "online", "offline"]
        data["attribution"] = {"© OpenFreeMap": "https://openfreemap.org/",
                               "© OpenStreetMap contributors": "https://www.openstreetmap.org/copyright"}
        with open(os.path.join(maps, "drive_offline_%s.json" % mode), "w") as f:
            json.dump(data, f, separators=(",", ":"))


def download_async(rid):
    """Start a download in a thread; progress and the end arrive as
    'offline.progress' (phase, done, total) and 'offline.finished' (rid, error)."""
    import pyotherside

    def run():
        err = ""
        try:
            download(rid, lambda p, d, t: pyotherside.send("offline.progress", p, d, t))
        except InterruptedError:
            err = "cancelled"
        except Exception as e:
            err = str(e) or e.__class__.__name__
        pyotherside.send("offline.finished", rid, err)

    threading.Thread(target=run, daemon=True).start()
