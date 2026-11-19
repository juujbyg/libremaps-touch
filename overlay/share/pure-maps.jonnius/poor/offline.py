# -*- coding: utf-8 -*-
"""LibreMaps offline maps: download areas anywhere in the world (OpenFreeMap
vector tiles, glyphs and sprites) into one shared file in the app's data
folder, then write an offline copy of the Drive styles that reads it
(mbtiles:// and file://). Areas may overlap; a low-detail world overview
(zoom 0-4) comes with the first one, so the map is never blank elsewhere.

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
GLYPH_RANGES = list(range(0, 0x3000, 256)) + list(range(0xFB00, 0x10000, 256))
# Chinese, Japanese and Korean glyphs: about 70 MB, so only for areas in East Asia
CJK_RANGES = list(range(0x3000, 0xFB00, 256))
CJK_AREA = [73.0, -11.0, 154.0, 54.0]   # w, s, e, n
SPRITE = "https://tiles.openfreemap.org/sprites/ofm_f384/ofm"
USER_AGENT = "LibreMaps-offline/0.1 (+https://github.com/juujbyg)"
WORKERS = 4
MAXZOOM = 14

OVERVIEW_ZOOM = 4          # world overview: zoom 0-4, 341 tiles (about 25 MB)
MAX_TILES = 400000         # one area at most (about 1.5 GB); zoom in for less
AVG_TILE_KB = 4.0          # for size estimates (Madrid: 91 MB / 25k tiles)
FILE = "world.mbtiles"
# the world overview (zoom 0-4) has a file of its own: the map stretches its
# tiles to deeper zooms where no area is saved, which it never does for
# tiles missing from a file that claims zoom 14
OVERVIEW_FILE = "overview.mbtiles"
WORLD = [-180.0, -85.05, 180.0, 85.05]

_cancel = threading.Event()
_lock = threading.Lock()   # one download or removal at a time


def folder():
    return os.path.join(poor.DATA_HOME_DIR, "offline")


def tiles_path():
    return os.path.join(folder(), FILE)


def _regions_path():
    return os.path.join(folder(), "regions.json")


def _migrate():
    """0.10.x kept one file per region (madrid.mbtiles): it becomes the shared file."""
    old = os.path.join(folder(), "madrid.mbtiles")
    if os.path.exists(old) and not os.path.exists(tiles_path()):
        done = os.path.exists(old + ".done")
        os.rename(old, tiles_path())
        if os.path.exists(old + ".done"):
            os.remove(old + ".done")
        _save([{"id": "madrid", "name": "Comunidad de Madrid",
                "bbox": [-4.58, 39.88, -3.05, 41.17], "done": done}])
        # the old file's bounds were Madrid only: open it up to the world
        db = _open_mbtiles()
        try:
            db.execute("INSERT OR REPLACE INTO metadata VALUES ('bounds', ?)",
                       ("%s,%s,%s,%s" % tuple(WORLD),))
            db.commit()
        finally:
            db.close()
        write_styles()


def _load():
    _migrate()
    _split_overview()
    try:
        with open(_regions_path(), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return []


def _save(regions):
    os.makedirs(folder(), exist_ok=True)
    tmp = _regions_path() + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(regions, f, ensure_ascii=False)
    os.replace(tmp, _regions_path())


def regions():
    return _load()


def done_regions():
    return [r for r in _load() if r.get("done")]


def overview_path():
    return os.path.join(folder(), OVERVIEW_FILE)


def has_overview():
    return os.path.exists(overview_path() + ".done")


def _split_overview():
    """Up to 0.10.42 the overview's zoom 0-4 tiles lived in world.mbtiles."""
    if not os.path.exists(tiles_path()) or os.path.exists(overview_path()):
        return
    db = sqlite3.connect(tiles_path())
    try:
        if db.execute("SELECT 1 FROM tiles WHERE zoom_level <= ? LIMIT 1",
                      (OVERVIEW_ZOOM,)).fetchone() is None:
            return
        meta = dict(db.execute("SELECT name, value FROM metadata"))
    finally:
        db.close()
    ov = _open_mbtiles(None, overview=True)
    try:
        ov.execute("ATTACH DATABASE ? AS w", (tiles_path(),))
        ov.execute("INSERT OR REPLACE INTO tiles SELECT * FROM w.tiles WHERE zoom_level <= ?",
                   (OVERVIEW_ZOOM,))
        ov.commit()
        ov.execute("DETACH DATABASE w")
    finally:
        ov.close()
    _write_meta(overview_path(), meta, 0, OVERVIEW_ZOOM)
    db = sqlite3.connect(tiles_path())
    try:
        db.execute("DELETE FROM tiles WHERE zoom_level <= ?", (OVERVIEW_ZOOM,))
        db.commit()
    finally:
        db.close()
    _write_meta(tiles_path(), meta, OVERVIEW_ZOOM + 1, MAXZOOM)
    old = tiles_path() + ".overview"
    if os.path.exists(old):
        os.rename(old, overview_path() + ".done")
    write_styles()


def _write_meta(path, meta, minzoom, maxzoom):
    db = sqlite3.connect(path)
    try:
        meta = dict(meta, minzoom=str(minzoom), maxzoom=str(maxzoom))
        db.executemany("INSERT OR REPLACE INTO metadata VALUES (?, ?)", meta.items())
        db.commit()
    finally:
        db.close()


def status():
    """For the Offline maps page: the areas, the file size and the overview."""
    regions = _load()
    size = sum(os.path.getsize(p) for p in (tiles_path(), overview_path()) if os.path.exists(p))
    return {"regions": [{"id": r["id"], "name": r["name"] or "…", "done": bool(r.get("done")),
                         "tiles": count_tiles(r["bbox"], OVERVIEW_ZOOM + 1, MAXZOOM)}
                        for r in regions],
            "size": size, "overview": has_overview()}


def estimate(bbox):
    """Tiles and approximate MB for an area (overview and fonts included if missing)."""
    bbox = _clamp(bbox)
    n = count_tiles(bbox, OVERVIEW_ZOOM + 1, MAXZOOM)
    mb = n * AVG_TILE_KB / 1024
    if not has_overview():
        mb += 25
    if _intersects(bbox, CJK_AREA) and not _has_cjk():
        mb += 70
    return {"tiles": n, "mb": int(round(mb)), "too_big": n > MAX_TILES}


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


def _clamp(bbox):
    w, s, e, n = [float(v) for v in bbox]
    w, e = max(-180.0, min(w, e)), min(180.0, max(w, e))
    s, n = max(-85.05, min(s, n)), min(85.05, max(s, n))
    return [w, s, e, n]


def _intersects(a, b):
    return a[0] < b[2] and a[2] > b[0] and a[1] < b[3] and a[3] > b[1]


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


def _open_mbtiles(info=None, overview=False):
    os.makedirs(folder(), exist_ok=True)
    db = sqlite3.connect(overview_path() if overview else tiles_path(), check_same_thread=False)
    db.executescript("""
        CREATE TABLE IF NOT EXISTS metadata (name TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS tiles (zoom_level INTEGER, tile_column INTEGER,
            tile_row INTEGER, tile_data BLOB, PRIMARY KEY (zoom_level, tile_column, tile_row));
    """)
    if info is not None:
        # the bounds are the whole world: areas can be anywhere, and the map must ask
        # this file for every tile (missing ones just draw nothing)
        meta = {"name": "LibreMaps offline", "format": "pbf", "type": "baselayer",
                "minzoom": "0" if overview else str(OVERVIEW_ZOOM + 1),
                "maxzoom": str(OVERVIEW_ZOOM if overview else MAXZOOM),
                "bounds": "%s,%s,%s,%s" % tuple(WORLD),
                "center": "0,0,2", "attribution": info.get("attribution", ""),
                "description": "OpenFreeMap",
                "json": json.dumps({"vector_layers": info.get("vector_layers", [])})}
        db.executemany("INSERT OR REPLACE INTO metadata VALUES (?, ?)", meta.items())
        db.commit()
    return db


def _has_cjk():
    d = os.path.join(folder(), "fonts", FONTSTACKS[-1])
    last = CJK_RANGES[-1]
    return os.path.exists(os.path.join(d, "%d-%d.pbf" % (last, last + 255)))


def _assets(out, progress, cjk):
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
    ranges = GLYPH_RANGES + (CJK_RANGES if cjk else [])
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


def _area_name(bbox):
    """A name for an area: the town, county or region at its centre (one
    Nominatim request at a zoom that fits the area's size), or coordinates."""
    x, y = (bbox[0] + bbox[2]) / 2, (bbox[1] + bbox[3]) / 2
    span = max(bbox[2] - bbox[0], bbox[3] - bbox[1])
    # Nominatim zoom: 5 country, 8 state, 10 city, 12 town or borough
    zoom = 5 if span > 6 else 8 if span > 1.2 else 10 if span > 0.15 else 12
    try:
        from poor.placeinfo import _nominatim_lock, _nominatim_last, USER_AGENT as UA
        with _nominatim_lock:
            wait = 1.0 - (time.time() - _nominatim_last[0])
            if wait > 0:
                time.sleep(wait)
            _nominatim_last[0] = time.time()
        url = ("https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=%d&lat=%.5f&lon=%.5f"
               "&accept-language=%s" % (zoom, y, x, urllib.parse.quote(_lang())))
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=15) as r:
            res = json.loads(r.read().decode("utf-8"))
        name = res.get("name") or (res.get("display_name") or "").split(",")[0]
        if name:
            return name.strip()
    except Exception:
        pass
    return "%.2f, %.2f" % (y, x)


def _lang():
    lang = (os.environ.get("LANGUAGE") or os.environ.get("LANG") or "en").split(":")[0]
    return lang.split(".")[0].replace("_", "-") or "en"


def _fill(db, todo, template, progress, done, total):
    def get(t):
        z, x, y = t
        return t, fetch(template.format(z=z, x=x, y=y))

    progress("tiles", done, total)
    with concurrent.futures.ThreadPoolExecutor(WORKERS) as pool:
        for (z, x, y), data in pool.map(get, todo):
            if data is not None:
                db.execute("INSERT OR REPLACE INTO tiles VALUES (?, ?, ?, ?)",
                           (z, x, (1 << z) - 1 - y, gzip.compress(data)))
            done += 1
            if done % 200 == 0:
                db.commit()
                progress("tiles", done, total)
    db.commit()
    return done


def _have(db, bbox, minzoom, maxzoom):
    have = set()
    for z in range(minzoom, maxzoom + 1):
        x0, x1, y0, y1 = tile_range(bbox, z)
        top = (1 << z) - 1
        for x, row in db.execute(
                "SELECT tile_column, tile_row FROM tiles WHERE zoom_level=? AND tile_column BETWEEN ? AND ?"
                " AND tile_row BETWEEN ? AND ?", (z, x0, x1, top - y1, top - y0)):
            have.add((z, x, top - row))
    return have


def add_region(bbox, name=""):
    """Register a new area (not downloaded yet); returns its id."""
    bbox = _clamp(bbox)
    if count_tiles(bbox, OVERVIEW_ZOOM + 1, MAXZOOM) > MAX_TILES:
        raise ValueError("area too big")
    regions = _load()
    rid = "r%d" % int(time.time() * 1000)
    regions.append({"id": rid, "name": name or "", "bbox": bbox, "done": False})
    _save(regions)
    return rid


def download(rid, progress=lambda phase, done, total: None):
    """Download area rid, and the world overview if missing (blocking; run in a
    thread). Resumable: tiles already in the file are skipped."""
    with _lock:
        _cancel.clear()
        regions = _load()
        if rid == "overview":
            bbox = None          # just the world overview
        else:
            region = [r for r in regions if r["id"] == rid][0]
            bbox = region["bbox"]
            if not region.get("name"):
                region["name"] = _area_name(bbox)
                _save(regions)
        out = folder()
        os.makedirs(out, exist_ok=True)
        _assets(out, progress, bool(bbox) and _intersects(bbox, CJK_AREA))
        info = json.loads(fetch(TILEJSON))
        template = info["tiles"][0]
        ov = _open_mbtiles(info, overview=True)
        db = _open_mbtiles(info)
        try:
            ov_todo, todo = [], []
            have_n = 0
            if not has_overview():
                have = _have(ov, WORLD, 0, OVERVIEW_ZOOM)
                ov_todo = [t for t in tiles(WORLD, 0, OVERVIEW_ZOOM) if t not in have]
                have_n += len(have)
            if bbox:
                have = _have(db, bbox, OVERVIEW_ZOOM + 1, MAXZOOM)
                todo = [t for t in tiles(bbox, OVERVIEW_ZOOM + 1, MAXZOOM) if t not in have]
                have_n += len(have)
            total = len(ov_todo) + len(todo) + have_n
            done = _fill(ov, ov_todo, template, progress, have_n, total)
            open(overview_path() + ".done", "w").close()
            _fill(db, todo, template, progress, done, total)
        finally:
            db.close()
            ov.close()
        regions = _load()
        for r in regions:
            if r["id"] == rid:
                r["done"] = True
        _save(regions)
        write_styles()
        _after_change(progress)
        progress("done", 1, 1)


def remove(rid):
    """Remove area rid: its tiles go unless another area still needs them."""
    with _lock:
        regions = _load()
        region = [r for r in regions if r["id"] == rid]
        if not region:
            return
        bbox = region[0]["bbox"]
        others = [r["bbox"] for r in regions if r["id"] != rid]
        rest = [r for r in regions if r["id"] != rid]
        if not [r for r in rest if r.get("done")]:
            # nothing left but the overview: drop the whole offline map
            for name in (FILE, OVERVIEW_FILE, OVERVIEW_FILE + ".done", "regions.json",
                         "search.sqlite", "roads.sqlite"):
                p = os.path.join(folder(), name)
                if os.path.exists(p):
                    os.remove(p)
            for mode in ("night", "day"):
                p = os.path.join(poor.DATA_HOME_DIR, "maps", "drive_offline_%s.json" % mode)
                if os.path.exists(p):
                    os.remove(p)
            _save(rest)
            return
        if os.path.exists(tiles_path()):
            db = _open_mbtiles()
            try:
                for z in range(OVERVIEW_ZOOM + 1, MAXZOOM + 1):
                    x0, x1, y0, y1 = tile_range(bbox, z)
                    top = (1 << z) - 1
                    keep = [tile_range(o, z) for o in others if _intersects(bbox, o)]
                    if not keep:
                        db.execute("DELETE FROM tiles WHERE zoom_level=? AND tile_column BETWEEN ? AND ?"
                                   " AND tile_row BETWEEN ? AND ?", (z, x0, x1, top - y1, top - y0))
                        continue
                    gone = []
                    for x in range(x0, x1 + 1):
                        for y in range(y0, y1 + 1):
                            if not any(k[0] <= x <= k[1] and k[2] <= y <= k[3] for k in keep):
                                gone.append((z, x, top - y))
                    db.executemany("DELETE FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?", gone)
                db.commit()
                db.execute("VACUUM")
            finally:
                db.close()
        _save(rest)
        _after_change(lambda p, d, t: None)


def _after_change(progress):
    """Rebuild the offline search and routing data from the tiles."""
    try:
        import poor.offline_index
    except ImportError:
        return
    poor.offline_index.rebuild(progress)


def _strings(v):
    if isinstance(v, str):
        yield v
    elif isinstance(v, dict):
        for x in v.values():
            yield from _strings(x)
    elif isinstance(v, list):
        for x in v:
            yield from _strings(x)


def offline_style(style):
    style = json.loads(json.dumps(style))
    base = folder().rstrip("/")
    dropped = {k for k, v in style["sources"].items() if v.get("type") != "vector"}
    for k in dropped:
        del style["sources"][k]
    style["layers"] = [l for l in style["layers"] if l.get("source") not in dropped]
    style["sources"]["openmaptiles"] = {"type": "vector",
                                        "url": "mbtiles://%s/%s" % (base, FILE)}
    style["sources"]["overview"] = {"type": "vector",
                                    "url": "mbtiles://%s/%s" % (base, OVERVIEW_FILE)}
    # the overview draws first, under everything from the saved areas, up to
    # zoom 10 (roads up to 7, where its simplified lines would show beside the
    # detailed ones)
    under = []
    for l in style["layers"]:
        if l.get("source") != "openmaptiles":
            continue
        c = json.loads(json.dumps(l))
        c["id"] = "ov-" + l["id"]
        c["source"] = "overview"
        cap = 7 if l.get("source-layer", "").startswith("transportation") else 10
        if l.get("minzoom", 0) >= cap:
            continue
        c["maxzoom"] = min(l.get("maxzoom", 24), cap)
        under.append(c)
    first = next((i for i, l in enumerate(style["layers"]) if l.get("source")), len(style["layers"]))
    style["layers"] = style["layers"][:first] + under + style["layers"][first:]
    style["glyphs"] = "file://%s/fonts/{fontstack}/{range}.pbf" % base
    style["sprite"] = "file://%s/sprites/ofm" % base
    left = [u for u in _strings(style) if u.startswith(("http://", "https://"))]
    if left:
        raise ValueError("network URLs left: %s" % left[:3])
    return style


def write_styles():
    """Write 'Drive Offline' night and day basemaps that read the shared file."""
    maps = os.path.join(poor.DATA_HOME_DIR, "maps")
    os.makedirs(maps, exist_ok=True)
    for mode in ("night", "day"):
        with open(os.path.join(poor.DATA_DIR, "maps", "drive_%s.json" % mode)) as f:
            data = json.load(f)
        data["style_json"] = offline_style(data["style_json"])
        data["provider"] = "Drive Offline"
        data["name"] = "Drive Offline " + mode.capitalize()
        data["profiles"] = ["mixed", "online", "offline"]
        data["attribution"] = {"© OpenFreeMap": "https://openfreemap.org/",
                               "© OpenStreetMap contributors": "https://www.openstreetmap.org/copyright"}
        with open(os.path.join(maps, "drive_offline_%s.json" % mode), "w") as f:
            json.dump(data, f, separators=(",", ":"))


def _run_async(rid, job):
    import pyotherside

    def run():
        err = ""
        try:
            job()
        except InterruptedError:
            err = "cancelled"
        except Exception as e:
            err = str(e) or e.__class__.__name__
        pyotherside.send("offline.finished", rid, err)

    threading.Thread(target=run, daemon=True).start()


def download_async(rid):
    """Start a download in a thread; progress and the end arrive as
    'offline.progress' (phase, done, total) and 'offline.finished' (rid, error)."""
    import pyotherside
    _run_async(rid, lambda: download(rid, lambda p, d, t: pyotherside.send("offline.progress", p, d, t)))


def add_and_download_async(bbox):
    """A new area from the map on screen, downloaded at once; returns its id."""
    try:
        rid = add_region(bbox)
    except Exception as e:
        import pyotherside
        pyotherside.send("offline.finished", "new", str(e) or e.__class__.__name__)
        return ""
    download_async(rid)
    return rid


def index_pending():
    try:
        import poor.offline_index
        return poor.offline_index.pending()
    except Exception:
        return False


def reindex_async():
    """Build the offline search and routes for areas saved before they
    existed (or after an update changed the index)."""
    import pyotherside

    def job():
        with _lock:
            _cancel.clear()
            _after_change(lambda p, d, t: pyotherside.send("offline.progress", p, d, t))
    _run_async("index", job)


def remove_async(rid):
    _run_async(rid, lambda: remove(rid))


# ---------------------------------------------------------------- using it

OFFLINE_PROVIDER = "Drive Offline"
ONLINE_PROVIDER = "Drive"


def in_use():
    """Is the map drawn from the offline file?"""
    try:
        return poor.app.basemap.basemap == OFFLINE_PROVIDER
    except Exception:
        return False


def use(on):
    """Switch the map between the offline file and the online Drive map.
    The map list is read once at start, so reload it when the offline map
    was written after that."""
    mm = poor.app.basemap
    if on:
        if not done_regions() and not has_overview():
            return False
        _load()             # finishes any pending update of the files first
        # always reload: the offline style may have been rewritten since start
        if hasattr(mm, "profile"):
            del mm.profile
        mm.__init__()
        if in_use():
            poor.app.set_basemap(ONLINE_PROVIDER)
        poor.app.set_basemap(OFFLINE_PROVIDER)
    else:
        poor.app.set_basemap(ONLINE_PROVIDER)
    # Pure Maps writes its settings only on a clean quit
    try:
        poor.conf.write()
    except Exception:
        pass
    return in_use()
