# -*- coding: utf-8 -*-
"""LibreMaps offline search over search.sqlite (built by poor.offline_index):
places, streets, house numbers and points of interest in the saved areas.

Also `fallback()`, which the online geocoder, guide and router use to answer
from the saved areas when their server can't be reached or doesn't answer
in time.
"""

import concurrent.futures
import math
import os
import re
import sqlite3
import threading
import unicodedata

from poor import offline_index as oi

WAIT_ONLINE = 6.0       # seconds before an unanswered online request gives way

# Nearby categories (the labels of guides/libremaps.py) -> OpenMapTiles subclasses
CATEGORIES = {
    "Restaurant": {"restaurant"},
    "Café": {"cafe"},
    "Bar or pub": {"bar", "pub"},
    "Fast food": {"fast_food"},
    "Bakery": {"bakery"},
    "Supermarket": {"supermarket", "convenience"},
    "Pharmacy": {"pharmacy"},
    "Hospital": {"hospital", "clinic"},
    "Fuel station": {"fuel"},
    "Charging station": {"charging_station"},
    "Parking": {"parking"},
    "ATM": {"atm"},
    "Bank": {"bank"},
    "Post office": {"post_office"},
    "Public toilets": {"toilets"},
    "Hotel": {"hotel", "hostel", "guest_house", "motel"},
    "Museum": {"museum"},
    "Cinema": {"cinema"},
    "Park": {"park"},
    "Gym": {"fitness_centre", "sports_centre"},
    "Bus stop": {"bus_stop", "bus_station"},
    "Metro station": {"subway"},
    "Train station": {"station", "halt"},
    "Bicycle rental": {"bicycle_rental"},
}

KIND_WEIGHT = {"place": 0.0, "address": 1.6, "street": 2.0, "poi": 2.4}
PLACE_WEIGHT = {1: -1.0, 2: -0.5, 3: 0.0, 4: 0.4, 5: 0.8, 6: 1.0}
# points that share a name with what people usually mean (the station
# entrance "Alcalá", the bus stop "Atocha")
MINOR = {"entrance", "subway_entrance", "bus_stop", "artwork", "ticket", "platform",
         "waste_basket", "bench", "information", "post_box", "vending_machine"}

_local = threading.local()


def available():
    return os.path.exists(oi.search_path())


def _db():
    path = oi.search_path()
    db = getattr(_local, "db", None)
    if db is None or getattr(_local, "path", None) != path or not os.path.exists(path):
        if db is not None:
            db.close()
        db = sqlite3.connect("file:%s?mode=ro" % path, uri=True)
        _local.db, _local.path = db, path
    return db


def close():
    db = getattr(_local, "db", None)
    if db is not None:
        db.close()
        _local.db = None


def _plain(text):
    text = unicodedata.normalize("NFKD", text.lower())
    return "".join(c for c in text if not unicodedata.combining(c))


def _fts_query(text):
    words = re.findall(r"\w+", _plain(text))
    if not words:
        return None
    return " ".join('"%s"*' % w for w in words)


def _km(x1, y1, x2, y2):
    dx = (x2 - x1) * math.cos(math.radians((y1 + y2) / 2))
    dy = y2 - y1
    return math.hypot(dx, dy) * 111.32


def _pretty(sub):
    return sub.replace("_", " ").capitalize() if sub else ""


KIND_LABEL = {"street": "Street", "address": "Address"}


def _locality(db, x, y, exclude=""):
    """The closest town, village or suburb, for descriptions."""
    d = 0.08
    best = None
    for name, cls, px, py in db.execute(
            "SELECT name, cls, x, y FROM entries WHERE kind='place' AND x BETWEEN ? AND ? "
            "AND y BETWEEN ? AND ? AND cls IN ('city','town','village','suburb','hamlet')",
            (x - d, x + d, y - d, y + d)):
        if name == exclude:
            continue
        km = _km(x, y, px, py) * (0.5 if cls in ("city", "town") else 1.0)
        if best is None or km < best[0]:
            best = (km, name)
    return best[1] if best else ""


def _result(db, kind, cls, sub, name, x, y, distance=None):
    big = kind == "place" and cls in ("city", "town", "country", "state", "province")
    where = "" if big else _locality(db, x, y, exclude=name)
    if kind == "place":
        what = _pretty(cls)
    elif kind == "poi":
        what = _pretty(sub or cls)
    else:
        what = KIND_LABEL.get(kind, "")
    description = ", ".join(v for v in (what, where) if v)
    out = dict(title=name, description=description,
               address=", ".join(v for v in (name, where) if v),
               label=", ".join(v for v in (name, where) if v),
               poi_type=what, postcode="", x=float(x), y=float(y), offline=True)
    if distance is not None:
        out["distance"] = distance
    return out


def geocode(query, x=0, y=0, limit=10):
    """Places matching `query`, best first, nearer ones favoured."""
    if not available():
        return []
    q = _fts_query(query)
    if not q:
        return []
    db = _db()
    rows = db.execute(
        "SELECT e.kind, e.cls, e.sub, e.name, e.x, e.y, e.rank, bm25(fts) FROM fts "
        "JOIN entries e ON e.id = fts.rowid WHERE fts MATCH ? ORDER BY bm25(fts) LIMIT 400",
        (q,)).fetchall()
    plain_q = _plain(query).strip()
    scored = []
    for kind, cls, sub, name, ex, ey, rank, bm in rows:
        s = KIND_WEIGHT.get(kind, 2.5) + 0.25 * bm
        if kind == "place":
            s += PLACE_WEIGHT.get(rank, 1.2)
        elif sub in MINOR or cls in MINOR:
            s += 1.5
        pn = _plain(name)
        if pn == plain_q:
            s -= 2.5
        elif pn.startswith(plain_q):
            s -= 1.2
        if x or y:
            s += 1.4 * math.log10(1 + _km(x, y, ex, ey))
        scored.append((s, kind, cls, sub, name, ex, ey))
    scored.sort(key=lambda r: r[0])
    out, kept = [], []
    for s, kind, cls, sub, name, ex, ey in scored:
        # one street per name and neighbourhood (each tile has its own entry)
        if any(k[0] == name and k[1] == kind and _km(ex, ey, k[2], k[3]) < 2.0 for k in kept):
            continue
        kept.append((name, kind, ex, ey))
        out.append(_result(db, kind, cls, sub, name, ex, ey))
        if len(out) >= limit:
            break
    return out


def nearby(category, query_name, x, y, radius, limit=40):
    """Points of interest of a Nearby category within `radius` metres."""
    if not available():
        return []
    subs = CATEGORIES.get(category)
    db = _db()
    d_lat = radius / 111320.0
    d_lon = radius / (111320.0 * max(0.05, math.cos(math.radians(y))))
    box = (x - d_lon, x + d_lon, y - d_lat, y + d_lat)
    if subs:
        marks = ",".join("?" * len(subs))
        rows = db.execute(
            "SELECT kind, cls, sub, name, x, y FROM entries WHERE sub IN (%s) AND kind='poi' "
            "AND x BETWEEN ? AND ? AND y BETWEEN ? AND ?" % marks, tuple(subs) + box).fetchall()
    else:
        q = _fts_query(" ".join(v for v in (query_name, category) if v))
        if not q:
            return []
        rows = db.execute(
            "SELECT e.kind, e.cls, e.sub, e.name, e.x, e.y FROM fts JOIN entries e "
            "ON e.id = fts.rowid WHERE fts MATCH ? AND e.x BETWEEN ? AND ? AND e.y BETWEEN ? AND ?",
            (q,) + box).fetchall()
    want = _plain(query_name or "")
    out = []
    for kind, cls, sub, name, ex, ey in rows:
        dist = _km(x, y, ex, ey) * 1000
        if dist > radius:
            continue
        if want and want not in _plain(name or ""):
            continue
        r = _result(db, kind, cls, sub, name or category, ex, ey, distance=dist)
        r["poi_type"] = category
        out.append(r)
    out.sort(key=lambda r: r["distance"])
    return out[:limit]


def reverse(x, y, radius=200, limit=1):
    """What is at (x, y): a house number, else the street, else the area."""
    if not available():
        return []
    db = _db()
    d_lat = radius / 111320.0
    d_lon = radius / (111320.0 * max(0.05, math.cos(math.radians(y))))
    best = None
    for kind, cls, sub, name, ex, ey in db.execute(
            "SELECT kind, cls, sub, name, x, y FROM entries WHERE kind IN ('address','poi') "
            "AND x BETWEEN ? AND ? AND y BETWEEN ? AND ? AND name != ''",
            (x - d_lon, x + d_lon, y - d_lat, y + d_lat)):
        dist = _km(x, y, ex, ey) * 1000
        if kind == "poi":
            dist += 15      # an address is the better answer at equal distance
        if dist <= min(radius, 40) and (best is None or dist < best[0]):
            best = (dist, kind, cls, sub, name, ex, ey)
    if best is None:
        street = _street_at(x, y)
        if street:
            return [_result(db, "street", "", "", street, x, y)]
        where = _locality(db, x, y)
        if not where:
            return []
        return [_result(db, "place", "", "", where, x, y)]
    return [_result(db, *best[1:])]


def _street_at(x, y):
    try:
        from poor import offline_route as orr
        g = orr.Graph(oi.roads_path())
    except Exception:
        return ""
    try:
        gx, gy = oi.world(x, y)
        mpu = oi.meters_per_unit(gy)
        orr_snap = g.snap(gx, gy, "foot", mpu)
        name, ref = g.name(orr_snap["edge"][6])
        return name or ref
    except Exception:
        return ""
    finally:
        g.close()


# ------------------------------------------------------------------ fallback

_pool = concurrent.futures.ThreadPoolExecutor(max_workers=4)


def fallback(online, offline, wait=WAIT_ONLINE):
    """Run online(); if it fails, or hasn't answered after `wait` seconds,
    return offline() instead when that gives an answer. An online answer that
    is empty also falls back. offline() returns None or [] for "no answer"."""
    job = _pool.submit(online)
    try:
        result = job.result(timeout=wait)
        if result:
            return result
        error = None
    except concurrent.futures.TimeoutError:
        error = TimeoutError("no answer from the server")
    except Exception as e:
        error = e
    try:
        local = offline()
    except Exception:
        local = None
    if local:
        return local
    if error is None:
        return result
    if isinstance(error, TimeoutError):
        # nothing offline: keep waiting for the server after all
        return job.result()
    raise error
