# -*- coding: utf-8 -*-
"""LibreMaps offline search and routes, built on the phone from the saved
OpenFreeMap tiles (OpenMapTiles schema, zoom 14). Standard library only.

search.sqlite  places, points of interest, streets and house numbers, with a
               full-text index (FTS5); read by poor.offline_search.
roads.sqlite   the road network as a graph; read by poor.offline_route.

Both follow the saved areas tile by tile: a new area indexes only its new
tiles, and removing an area drops the tiles no other area needs.

Coordinates in roads.sqlite are "world units": zoom-14 tile pixels at extent
4096, so 2**26 across the world (about 0.6 m at the equator).
"""

import array
import gzip
import math
import os
import sqlite3
import zlib

from poor import mvt

Z = 14
E = 4096
WU = (1 << Z) * E                       # world units across
VERSION = 5                             # bump to rebuild everything

# road classes worth routing on, as small codes
CLASSES = {"motorway": 1, "trunk": 2, "primary": 3, "secondary": 4, "tertiary": 5,
           "minor": 6, "service": 7, "track": 8, "path": 9, "busway": 10}
CLASS_NAMES = {v: k for k, v in CLASSES.items()}
F_FWD, F_BACK, F_RAMP, F_TOLL, F_NOACCESS = 1, 2, 4, 8, 16
F_STEPS, F_CYCLEWAY, F_FOOTWAY, F_NOBIKE, F_NOFOOT, F_BRUNNEL = 32, 64, 128, 256, 512, 1024

PLACE_RANK = {"city": 1, "town": 2, "village": 3, "suburb": 4, "hamlet": 5, "quarter": 5,
              "neighbourhood": 6, "isolated_dwelling": 7, "locality": 7, "island": 4,
              "country": 0, "state": 1, "province": 1}

SNAP = 1.6          # tile units: an end this close to another road joins it
BOUNDARY_TOL = 4    # world units: the same road leaving one tile and entering the next


# ------------------------------------------------------------------ geometry

def lonlat(gx, gy):
    lon = gx / WU * 360.0 - 180.0
    lat = math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * gy / WU))))
    return lon, lat


def world(lon, lat):
    lat = max(-85.0511, min(85.0511, lat))
    gx = (lon + 180.0) / 360.0 * WU
    gy = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * WU
    return gx, gy


def meters_per_unit(gy):
    lat = math.radians(lonlat(0, gy)[1])
    return 40075016.686 * math.cos(lat) / WU


def _clip_segment(x0, y0, x1, y1):
    dx, dy = x1 - x0, y1 - y0
    t0, t1 = 0.0, 1.0
    for p, q in ((-dx, x0), (dx, E - x0), (-dy, y0), (dy, E - y0)):
        if p == 0:
            if q < 0:
                return None
        else:
            r = q / p
            if p < 0:
                if r > t1:
                    return None
                if r > t0:
                    t0 = r
            else:
                if r < t0:
                    return None
                if r < t1:
                    t1 = r
    a = (x0 + t0 * dx, y0 + t0 * dy) if t0 > 0 else (x0, y0)
    b = (x0 + t1 * dx, y0 + t1 * dy) if t1 < 1 else (x1, y1)
    return a, b, t0 > 0, t1 < 1


def _snap_edge(v):
    v = int(round(v))
    return 0 if v < 0 else E if v > E else v


def clip(line):
    """Cut a line to the tile square [0, E]; a road leaving the tile ends on
    its edge, where the next tile's copy of it starts."""
    out, cur = [], None
    for i in range(len(line) - 1):
        seg = _clip_segment(line[i][0], line[i][1], line[i + 1][0], line[i + 1][1])
        if seg is None:
            cur = None
            continue
        a, b, entered, left = seg
        a = (_snap_edge(a[0]), _snap_edge(a[1]))
        b = (_snap_edge(b[0]), _snap_edge(b[1]))
        if a == b:
            continue
        if cur is None or entered or cur[-1] != a:
            cur = [a]
            out.append(cur)
        cur.append(b)
        if left:
            cur = None
    return [l for l in out if len(l) >= 2]


def on_boundary(p):
    return p[0] == 0 or p[0] == E or p[1] == 0 or p[1] == E


class Grid:
    """Segments of a tile in square cells, for nearby lookups."""

    def __init__(self, cell=128):
        self.cell = cell
        self.cells = {}

    def add(self, item, a, b, pad=2):
        c = self.cell
        x0, x1 = int((min(a[0], b[0]) - pad) // c), int((max(a[0], b[0]) + pad) // c)
        y0, y1 = int((min(a[1], b[1]) - pad) // c), int((max(a[1], b[1]) + pad) // c)
        for cx in range(x0, x1 + 1):
            for cy in range(y0, y1 + 1):
                self.cells.setdefault((cx, cy), []).append(item)

    def near(self, p):
        return self.cells.get((int(p[0] // self.cell), int(p[1] // self.cell)), ())


def _project(p, a, b):
    """(squared distance, t) from point p to segment ab."""
    ax, ay = a
    dx, dy = b[0] - ax, b[1] - ay
    L = dx * dx + dy * dy
    if L == 0:
        return (p[0] - ax) ** 2 + (p[1] - ay) ** 2, 0.0
    t = ((p[0] - ax) * dx + (p[1] - ay) * dy) / L
    t = 0.0 if t < 0 else 1.0 if t > 1 else t
    qx, qy = ax + t * dx, ay + t * dy
    return (p[0] - qx) ** 2 + (p[1] - qy) ** 2, t


def _cross(a, b, c, d):
    """Where segments ab and cd cross properly, as (t on ab, u on cd), or None."""
    rx, ry = b[0] - a[0], b[1] - a[1]
    sx, sy = d[0] - c[0], d[1] - c[1]
    den = rx * sy - ry * sx
    if den == 0:
        return None
    qx, qy = c[0] - a[0], c[1] - a[1]
    t = (qx * sy - qy * sx) / den
    u = (qx * ry - qy * rx) / den
    if 0.001 < t < 0.999 and 0.001 < u < 0.999:
        return t, u
    return None


# ------------------------------------------------------------------ roads

def road_flags(p):
    f = 0
    ow = p.get("oneway")
    if ow == 1:
        f |= F_FWD
    elif ow == -1:
        f |= F_BACK
    if p.get("ramp") == 1:
        f |= F_RAMP
    if p.get("toll") == 1:
        f |= F_TOLL
    if p.get("access") == "no":
        f |= F_NOACCESS
    sub = p.get("subclass")
    if sub == "steps":
        f |= F_STEPS
    elif sub == "cycleway":
        f |= F_CYCLEWAY
    elif sub in ("footway", "pedestrian", "platform", "corridor"):
        f |= F_FOOTWAY
    if p.get("bicycle") == "no":
        f |= F_NOBIKE
    if p.get("foot") == "no":
        f |= F_NOFOOT
    if p.get("brunnel"):
        f |= F_BRUNNEL
    return f


def tile_roads(feats):
    """Routable lines of one tile, cut to the tile and joined where they meet.
    Returns pieces as (points, class code, flags, layer), split at junctions."""
    lines = []          # [points, cls, flags, layer]
    for gtype, p, geom in feats:
        if gtype != mvt.LINE:
            continue
        cls = CLASSES.get(p.get("class"))
        if not cls:
            continue
        flags = road_flags(p)
        layer = p.get("layer") or 0
        for part in geom:
            for l in clip(part):
                lines.append([l, cls, flags, layer])
    if not lines:
        return []

    grid = Grid()
    for li, (pts, cls, flags, layer) in enumerate(lines):
        for si in range(len(pts) - 1):
            grid.add((li, si), pts[si], pts[si + 1])

    count = {}
    for pts, *_ in lines:
        for q in pts:
            count[q] = count.get(q, 0) + 1

    inserts = {}        # line index -> [(segment index, t, point)]

    # a road ending on another one (a T junction whose shared point the tile
    # dropped) joins it there; one ending close to a corner snaps to it
    snap2 = SNAP * SNAP
    for li, line in enumerate(lines):
        pts = line[0]
        for end in (0, -1):
            p = pts[end]
            if count[p] > 1 or on_boundary(p):
                continue
            best = None
            for lj, sj in grid.near(p):
                if lj == li:
                    continue
                q = lines[lj][0]
                d2, t = _project(p, q[sj], q[sj + 1])
                if d2 <= snap2 and (best is None or d2 < best[0]):
                    best = (d2, lj, sj, t)
            if best is None:
                continue
            _, lj, sj, t = best
            q = lines[lj][0]
            if t <= 0.0 or t >= 1.0:
                v = q[sj] if t <= 0.0 else q[sj + 1]
                pts[end] = v
                count[v] = count.get(v, 0) + 1
            else:
                inserts.setdefault(lj, []).append((sj, t, p))
                count[p] += 1

    # two level roads crossing with no shared point (both straight through)
    cell = grid.cell
    level = [not (L[2] & F_BRUNNEL) and L[1] != 1 for L in lines]
    for (cx, cy), items in grid.cells.items():
        segs = []
        for li, si in items:
            if level[li]:
                pts = lines[li][0]
                a, b = pts[si], pts[si + 1]
                segs.append((li, si, a, b, min(a[0], b[0]), max(a[0], b[0]),
                             min(a[1], b[1]), max(a[1], b[1]), lines[li][3]))
        n = len(segs)
        for i in range(n):
            li, si, a, b, ax0, ax1, ay0, ay1, lay = segs[i]
            for j in range(i + 1, n):
                lj, sj, c, d, bx0, bx1, by0, by1, lay2 = segs[j]
                if lj == li or bx0 > ax1 or bx1 < ax0 or by0 > ay1 or by1 < ay0 or lay2 != lay:
                    continue
                hit = _cross(a, b, c, d)
                if hit is None:
                    continue
                t, u = hit
                fx, fy = a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])
                if int(fx // cell) != cx or int(fy // cell) != cy:
                    continue        # the cell holding the crossing records it
                pt = (int(round(fx)), int(round(fy)))
                inserts.setdefault(li, []).append((si, t, pt))
                inserts.setdefault(lj, []).append((sj, u, pt))
                count[pt] = count.get(pt, 0) + 2

    for li, ins in inserts.items():
        pts = lines[li][0]
        ins.sort()
        out = []
        k = 0
        for si in range(len(pts)):
            out.append(pts[si])
            while k < len(ins) and ins[k][0] == si:
                if ins[k][2] != out[-1]:
                    out.append(ins[k][2])
                k += 1
        lines[li][0] = [q for i, q in enumerate(out) if i == 0 or q != out[i - 1]]

    count = {}
    for pts, *_ in lines:
        for q in pts:
            count[q] = count.get(q, 0) + 1
    pieces = []
    for pts, cls, flags, layer in lines:
        cur = [pts[0]]
        last = len(pts) - 1
        for i in range(1, last + 1):
            q = pts[i]
            cur.append(q)
            if i == last or count[q] > 1 or on_boundary(q):
                pieces.append((cur, cls, flags, layer))
                cur = [q]
    return pieces


def name_grid(feats):
    """transportation_name lines of a tile, to name the roads."""
    grid = Grid(64)
    for gtype, p, geom in feats:
        if gtype != mvt.LINE:
            continue
        name = p.get("name") or ""
        ref = p.get("ref") or ""
        if not name and not ref:
            continue
        label = (name, ref, CLASSES.get(p.get("class"), 0))
        for part in geom:
            for i in range(len(part) - 1):
                grid.add((label, part[i], part[i + 1]), part[i], part[i + 1], pad=6)
    return grid


def find_name(grid, pts, cls):
    if not grid.cells:
        return ("", "")
    mid = len(pts) // 2
    if len(pts) % 2 == 0:
        a, b = pts[mid - 1], pts[mid]
        p = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    else:
        p = pts[mid]
    best = None
    for label, a, b in grid.near(p):
        d2, _ = _project(p, a, b)
        if label[2] != cls:
            d2 += 4
        if d2 <= 25 and (best is None or d2 < best[0]):
            best = (d2, label)
    return (best[1][0], best[1][1]) if best else ("", "")


# ------------------------------------------------------------------ databases

def _open_roads(path):
    db = sqlite3.connect(path)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=NORMAL")
    db.executescript("""
        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS tiles (key INTEGER PRIMARY KEY, first INTEGER, last INTEGER);
        CREATE TABLE IF NOT EXISTS nodes (id INTEGER PRIMARY KEY, x INTEGER, y INTEGER);
        CREATE INDEX IF NOT EXISTS nodes_xy ON nodes (x, y);
        CREATE TABLE IF NOT EXISTS names (id INTEGER PRIMARY KEY, name TEXT, ref TEXT);
        CREATE UNIQUE INDEX IF NOT EXISTS names_u ON names (name, ref);
        CREATE TABLE IF NOT EXISTS edges (id INTEGER PRIMARY KEY, a INTEGER, b INTEGER,
            cls INTEGER, flags INTEGER, len INTEGER, name INTEGER, geom BLOB);
        CREATE INDEX IF NOT EXISTS edges_a ON edges (a);
        CREATE INDEX IF NOT EXISTS edges_b ON edges (b);
        CREATE TABLE IF NOT EXISTS edge_cells (cell INTEGER, edge INTEGER,
            PRIMARY KEY (cell, edge)) WITHOUT ROWID;
    """)
    return db


def _open_search(path):
    db = sqlite3.connect(path)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA synchronous=NORMAL")
    db.executescript("""
        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS tiles (key INTEGER PRIMARY KEY, first INTEGER, last INTEGER);
        CREATE TABLE IF NOT EXISTS entries (id INTEGER PRIMARY KEY,
            kind TEXT, cls TEXT, sub TEXT, name TEXT, alt TEXT, x REAL, y REAL, rank INTEGER);
        CREATE INDEX IF NOT EXISTS entries_sub ON entries (sub, x, y);
        CREATE INDEX IF NOT EXISTS entries_kind ON entries (kind, x, y);
        CREATE VIRTUAL TABLE IF NOT EXISTS fts USING fts5 (name, alt,
            tokenize = "unicode61 remove_diacritics 2");
    """)
    return db


def _version_ok(db):
    row = db.execute("SELECT value FROM meta WHERE key='version'").fetchone()
    return row is not None and row[0] == str(VERSION)


def _set_version(db):
    db.execute("INSERT OR REPLACE INTO meta VALUES ('version', ?)", (str(VERSION),))


CELL_BITS = 10      # lookup cells of 1024 world units (zoom 16, about 450 m in Spain)


def cell_id(cx, cy):
    return (cx << 16) | cy


def tile_key(x, y):
    return (x << Z) | y


def _node(db, cache, gx, gy, boundary):
    """The node at world point (gx, gy), made if new. Points on a tile edge
    match a node within BOUNDARY_TOL on the same edge line (the next tile's
    copy of the road)."""
    key = (gx, gy)
    nid = cache.get(key)
    if nid is not None:
        return nid
    if boundary:
        row = None
        if gx % E == 0:
            row = db.execute("SELECT id FROM nodes WHERE x=? AND y BETWEEN ? AND ? "
                             "ORDER BY abs(y-?) LIMIT 1",
                             (gx, gy - BOUNDARY_TOL, gy + BOUNDARY_TOL, gy)).fetchone()
        if row is None and gy % E == 0:
            row = db.execute("SELECT id FROM nodes WHERE y=? AND x BETWEEN ? AND ? "
                             "ORDER BY abs(x-?) LIMIT 1",
                             (gy, gx - BOUNDARY_TOL, gx + BOUNDARY_TOL, gx)).fetchone()
        if row is not None:
            cache[key] = row[0]
            return row[0]
    nid = db.execute("INSERT INTO nodes (x, y) VALUES (?, ?)", (gx, gy)).lastrowid
    cache[key] = nid
    return nid


def _name_id(db, cache, name, ref):
    if not name and not ref:
        return 0
    key = (name, ref)
    nid = cache.get(key)
    if nid is None:
        row = db.execute("SELECT id FROM names WHERE name=? AND ref=?", key).fetchone()
        nid = row[0] if row else db.execute("INSERT INTO names (name, ref) VALUES (?, ?)", key).lastrowid
        cache[key] = nid
    return nid


def index_roads(db, tx, ty, layers, name_cache):
    feats = layers.get("transportation")
    if not feats:
        return 0
    ext = feats[0]
    scale = E / ext if ext != E else 1
    tfeats = feats[1]
    if scale != 1:
        tfeats = [(g, p, [[(x * scale, y * scale) for x, y in part] for part in geo])
                  for g, p, geo in tfeats]
    names = name_grid(layers.get("transportation_name", (E, []))[1])
    pieces = tile_roads(tfeats)
    ox, oy = tx * E, ty * E
    mpu = meters_per_unit(oy + E / 2)
    cache = {}
    key = tile_key(tx, ty)
    rows = []
    for pts, cls, flags, layer in pieces:
        g = [(ox + int(x), oy + int(y)) for x, y in pts]
        a = _node(db, cache, g[0][0], g[0][1], on_boundary(pts[0]))
        b = _node(db, cache, g[-1][0], g[-1][1], on_boundary(pts[-1]))
        if a == b and len(g) < 3:
            continue
        length = sum(math.hypot(g[i + 1][0] - g[i][0], g[i + 1][1] - g[i][1])
                     for i in range(len(g) - 1)) * mpu
        name, ref = find_name(names, pts, cls)
        nid = _name_id(db, name_cache, name, ref)
        # points relative to the tile (0..4096): two bytes each
        blob = array.array("h", [int(c) for q in pts for c in q]).tobytes()
        # length in decimetres
        eid = db.execute("INSERT INTO edges (a, b, cls, flags, len, name, geom) "
                         "VALUES (?, ?, ?, ?, ?, ?, ?)",
                         (a, b, cls, flags, int(length * 10 + 0.5), nid, blob)).lastrowid
        xs = [q[0] for q in g]
        ys = [q[1] for q in g]
        for cx in range(min(xs) >> CELL_BITS, (max(xs) >> CELL_BITS) + 1):
            for cy in range(min(ys) >> CELL_BITS, (max(ys) >> CELL_BITS) + 1):
                rows.append((cell_id(cx, cy), eid))
    db.executemany("INSERT OR IGNORE INTO edge_cells VALUES (?, ?)", rows)
    return len(rows)


def _names(p):
    name = p.get("name") or ""
    alt = []
    for k in ("name:latin", "name_en", "name_int", "name:en"):
        v = p.get(k)
        if v and v != name and v not in alt:
            alt.append(v)
    return name, " ".join(alt)


def index_search(db, tx, ty, layers):
    ox, oy = tx * E, ty * E
    key = tile_key(tx, ty)
    rows = []

    def inside(pt, ext):
        return 0 <= pt[0] < ext and 0 <= pt[1] < ext

    def ll(pt, ext):
        s = E / ext
        return lonlat(ox + pt[0] * s, oy + pt[1] * s)

    ext, feats = layers.get("place", (E, []))
    for gtype, p, geom in feats:
        name, alt = _names(p)
        if gtype != mvt.POINT or not geom or not name or not inside(geom[0], ext):
            continue
        cls = p.get("class") or "place"
        x, y = ll(geom[0], ext)
        rows.append(("place", cls, cls, name, alt, x, y, PLACE_RANK.get(cls, 8)))

    ext, feats = layers.get("poi", (E, []))
    for gtype, p, geom in feats:
        if gtype != mvt.POINT or not geom or not inside(geom[0], ext):
            continue
        name, alt = _names(p)
        cls, sub = p.get("class") or "", p.get("subclass") or ""
        if not name and sub not in USEFUL_UNNAMED:
            continue
        x, y = ll(geom[0], ext)
        rows.append(("poi", cls, sub, name, alt, x, y, 20 + (p.get("rank") or 30)))

    # streets: one entry per name per tile, at the middle of its longest part
    ext, feats = layers.get("transportation_name", (E, []))
    streets = {}
    for gtype, p, geom in feats:
        name = p.get("name") or ""
        if gtype != mvt.LINE or not name:
            continue
        for part in geom:
            inside_pts = [q for q in part if inside(q, ext)]
            if len(inside_pts) < 2:
                continue
            length = sum(math.hypot(inside_pts[i + 1][0] - inside_pts[i][0],
                                    inside_pts[i + 1][1] - inside_pts[i][1])
                         for i in range(len(inside_pts) - 1))
            if name not in streets or length > streets[name][0]:
                streets[name] = (length, inside_pts[len(inside_pts) // 2], _names(p)[1],
                                 p.get("class") or "")
    for name, (length, pt, alt, cls) in streets.items():
        x, y = ll(pt, ext)
        rows.append(("street", cls, cls, name, alt, x, y, 12))

    # house numbers, named after the closest street within about 60 m
    ext_h, feats = layers.get("housenumber", (E, []))
    if feats and streets:
        lines = []
        for gtype, p, geom in layers.get("transportation_name", (E, []))[1]:
            if gtype == mvt.LINE and p.get("name"):
                for part in geom:
                    lines.append((p["name"], part))
        g = Grid(64)
        for name, part in lines:
            for i in range(len(part) - 1):
                g.add((name, part[i], part[i + 1]), part[i], part[i + 1], pad=100)
        s = ext / ext_h
        for gtype, p, geom in feats:
            num = p.get("housenumber")
            if gtype != mvt.POINT or not geom or not num or not inside(geom[0], ext_h):
                continue
            pt = (geom[0][0] * s, geom[0][1] * s)
            best = None
            for name, a, b in g.near(pt):
                d2, _ = _project(pt, a, b)
                if d2 < 100 * 100 and (best is None or d2 < best[0]):
                    best = (d2, name)
            if best is None:
                continue
            x, y = ll(geom[0], ext_h)
            rows.append(("address", "address", "", "%s %s" % (best[1], num), "", x, y, 15))

    for r in rows:
        eid = db.execute("INSERT INTO entries (kind, cls, sub, name, alt, x, y, rank) "
                         "VALUES (?, ?, ?, ?, ?, ?, ?, ?)", r).lastrowid
        if r[3]:
            db.execute("INSERT INTO fts (rowid, name, alt) VALUES (?, ?, ?)", (eid, r[3], r[4]))
    return len(rows)


def _drop_tiles(roads, search, keys):
    """Remove what these tiles added (each tile's rows are one id range)."""
    per = E >> CELL_BITS
    for key in keys:
        row = roads.execute("SELECT first, last FROM tiles WHERE key=?", (key,)).fetchone()
        if row and row[0] is not None:
            tx, ty = key >> Z, key & ((1 << Z) - 1)
            for cx in range(tx * per, tx * per + per + 1):
                for cy in range(ty * per, ty * per + per + 1):
                    roads.execute("DELETE FROM edge_cells WHERE cell=? AND edge BETWEEN ? AND ?",
                                  (cell_id(cx, cy), row[0], row[1]))
            roads.execute("DELETE FROM edges WHERE id BETWEEN ? AND ?", row)
        roads.execute("DELETE FROM tiles WHERE key=?", (key,))
        row = search.execute("SELECT first, last FROM tiles WHERE key=?", (key,)).fetchone()
        if row and row[0] is not None:
            search.execute("DELETE FROM fts WHERE rowid BETWEEN ? AND ?", row)
            search.execute("DELETE FROM entries WHERE id BETWEEN ? AND ?", row)
        search.execute("DELETE FROM tiles WHERE key=?", (key,))
    if keys:
        roads.execute("DELETE FROM nodes WHERE id NOT IN (SELECT a FROM edges) "
                      "AND id NOT IN (SELECT b FROM edges)")


def _next_id(db, table):
    return (db.execute("SELECT max(id) FROM %s" % table).fetchone()[0] or 0) + 1


# places without a name still worth finding nearby
USEFUL_UNNAMED = {"parking", "toilets", "atm", "fuel", "charging_station", "drinking_water",
                  "bicycle_rental", "pharmacy", "bus_stop", "post_box", "recycling",
                  "bicycle_parking", "motorcycle_parking"}

LAYERS = {"transportation", "transportation_name", "place", "poi", "housenumber"}
PROPS = {
    "transportation": {"class", "subclass", "oneway", "ramp", "toll", "access",
                       "bicycle", "foot", "brunnel", "layer"},
}


def build(mbtiles, wanted, roads_path, search_path, progress=lambda phase, done, total: None,
          cancelled=lambda: False):
    """Bring roads.sqlite and search.sqlite in step with `wanted`, a set of
    zoom-14 (x, y) tiles. Returns (tiles added, tiles dropped)."""
    for path, opener in ((roads_path, _open_roads), (search_path, _open_search)):
        if os.path.exists(path):
            db = opener(path)
            ok = _version_ok(db)
            db.close()
            if not ok:
                for suffix in ("", "-wal", "-shm"):
                    if os.path.exists(path + suffix):
                        os.remove(path + suffix)
    roads = _open_roads(roads_path)
    search = _open_search(search_path)
    _set_version(roads)
    _set_version(search)
    in_roads = {r[0] for r in roads.execute("SELECT key FROM tiles")}
    in_search = {r[0] for r in search.execute("SELECT key FROM tiles")}
    have = in_roads & in_search
    want = {tile_key(x, y): (x, y) for x, y in wanted}
    drop = [k for k in (in_roads | in_search) if k not in want or k not in have]
    todo = [want[k] for k in sorted(want) if k not in have]
    _drop_tiles(roads, search, drop)
    roads.commit()
    search.commit()
    src = sqlite3.connect("file:%s?mode=ro" % mbtiles, uri=True)
    name_cache = {}
    total = len(todo)
    try:
        for i, (x, y) in enumerate(todo):
            if cancelled():
                raise InterruptedError
            row = src.execute("SELECT tile_data FROM tiles WHERE zoom_level=? AND tile_column=? "
                              "AND tile_row=?", (Z, x, (1 << Z) - 1 - y)).fetchone()
            e0, s0 = _next_id(roads, "edges"), _next_id(search, "entries")
            if row is not None:
                data = row[0]
                if data[:2] == b"\x1f\x8b":
                    data = gzip.decompress(data)
                elif data[:1] == b"\x78":
                    data = zlib.decompress(data)
                layers = mvt.decode(data, LAYERS, PROPS)
                index_roads(roads, x, y, layers, name_cache)
                index_search(search, x, y, layers)
            k = tile_key(x, y)
            e1, s1 = _next_id(roads, "edges") - 1, _next_id(search, "entries") - 1
            roads.execute("INSERT OR REPLACE INTO tiles VALUES (?, ?, ?)",
                          (k, e0 if e1 >= e0 else None, e1))
            search.execute("INSERT OR REPLACE INTO tiles VALUES (?, ?, ?)",
                           (k, s0 if s1 >= s0 else None, s1))
            if i % 50 == 49:
                roads.commit()
                search.commit()
                progress("index", i + 1, total)
        roads.commit()
        search.commit()
        progress("index", total, total)
        if drop:
            roads.execute("VACUUM")
            search.execute("VACUUM")
    except BaseException:
        # keep only whole tiles: the last batch is undone and redone next time
        roads.rollback()
        search.rollback()
        raise
    finally:
        roads.close()
        search.close()
        src.close()
    return len(todo), len(drop)


def wanted_tiles(regions):
    """The zoom-14 tiles of the given areas ([w, s, e, n] each)."""
    from poor import offline
    out = set()
    for bbox in regions:
        x0, x1, y0, y1 = offline.tile_range(bbox, Z)
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                out.add((x, y))
    return out


def roads_path():
    from poor import offline
    return os.path.join(offline.folder(), "roads.sqlite")


def search_path():
    from poor import offline
    return os.path.join(offline.folder(), "search.sqlite")


def rebuild(progress=lambda phase, done, total: None):
    """Called by poor.offline after an area is added or removed."""
    from poor import offline
    areas = [r["bbox"] for r in offline.done_regions()]
    if not areas or not os.path.exists(offline.tiles_path()):
        for path in (roads_path(), search_path()):
            for suffix in ("", "-wal", "-shm"):
                if os.path.exists(path + suffix):
                    os.remove(path + suffix)
        return
    build(offline.tiles_path(), wanted_tiles(areas), roads_path(), search_path(), progress,
          cancelled=lambda: offline._cancel.is_set())


def pending():
    """True if the saved areas have tiles not indexed yet (or the index is
    from an older version)."""
    from poor import offline
    areas = [r["bbox"] for r in offline.done_regions()]
    if not areas or not os.path.exists(offline.tiles_path()):
        return False
    have = None
    for path in (roads_path(), search_path()):
        if not os.path.exists(path):
            return True
        db = sqlite3.connect("file:%s?mode=ro" % path, uri=True)
        try:
            if not _version_ok(db):
                return True
            keys = {r[0] for r in db.execute("SELECT key FROM tiles")}
        except sqlite3.Error:
            return True
        finally:
            db.close()
        have = keys if have is None else have & keys
    want = {tile_key(x, y) for x, y in wanted_tiles(areas)}
    return want != have

