# -*- coding: utf-8 -*-
# LibreMaps: road alerts.
#
# Two sources, merged into one list:
#  - Official incidents from Spain's traffic authority (DGT), from its open
#    DATEX II feed: closures, roadworks, accidents, stopped vehicles (V16
#    beacons), obstacles, slow traffic, weather. Only fetched in Spain.
#  - Reports by drivers (police, accident, hazard, road closed, traffic jam,
#    mobile speed camera), shared through public Nostr relays. Each report
#    and each vote is signed with a fresh one-use key, so nothing links
#    them to each other or to the phone. Reports expire on their own.
#
# Everything runs on a background thread; results reach QML through
# pyotherside events "alerts.updated", "alerts.reported" and "alerts.voted".
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

import gzip
import io
import math
import os
import threading
import time
import urllib.request
import xml.etree.ElementTree as ET

import poor
import pyotherside
from poor import nostr

USER_AGENT = "LibreMaps/0.9 (+https://github.com/juujbyg/libremaps-touch)"

# Nostr: an unassigned regular event kind, and relays that were seen to
# store and return it.
KIND = 8573
TOPIC = "libremaps-road"
RELAYS = ["wss://relay.damus.io", "wss://nos.lol",
          "wss://relay.primal.net", "wss://offchain.pub"]

# how long a driver's report stays up without new confirmations (seconds)
LIFETIME = {"police": 45*60, "camera": 45*60, "accident": 60*60,
            "hazard": 60*60, "jam": 30*60, "closed": 3*60*60}
REPORT_TYPES = tuple(LIFETIME)
# confirmations keep a report up, but never past this many lifetimes
MAX_LIFETIMES = 3

# NIP-13 proof of work on every report and vote. Keys are one-use, so they
# can't stop one person posting many fake votes; making each event cost
# work can (about 0.3 s on a PC and a few seconds on a phone at 18 bits).
POW_BITS = 18

# memory bounds for what relays send
MAX_REPORTS = 3000
MAX_VOTES_PER_REPORT = 200

DGT_URL = "https://nap.dgt.es/datex2/v3/dgt/SituationPublication/datex2_v37.xml"
DGT_MAX_AGE = 5*60
SPAIN = (27.0, -18.5, 44.5, 4.6)   # south, west, north, east

XSI_TYPE = "{http://www.w3.org/2001/XMLSchema-instance}type"
_DETAIL_TAGS = ("roadMaintenanceType", "obstructionType", "vehicleObstructionType",
                "accidentType", "abnormalTrafficType", "poorEnvironmentType",
                "environmentalObstructionType")

_lock = threading.Lock()
_state = {
    "points": [],        # [[lon, lat], ...] the area to watch
    "busy": False,
    "again": False,
    "dgt": [],           # parsed DGT incidents, whole country
    "dgt_time": 0,
    "community": {},     # id -> alert
    "votes": {},         # report id -> {voter pubkey: (up, created)}
    "dismissed": set(),  # report ids this phone said are gone
    "last": [],
}


# ---------------------------------------------------------------- helpers

def _local_name(tag):
    return tag.rsplit("}", 1)[-1]


def _dist(lat1, lon1, lat2, lon2):
    """Approximate distance in metres."""
    x = math.radians(lon2 - lon1) * math.cos(math.radians((lat1 + lat2) / 2))
    y = math.radians(lat2 - lat1)
    return 6371000 * math.hypot(x, y)


def _bbox(points, pad):
    lats = [p[1] for p in points]
    lons = [p[0] for p in points]
    return (min(lats) - pad, min(lons) - pad, max(lats) + pad, max(lons) + pad)


def _in_bbox(lat, lon, b):
    return b[0] <= lat <= b[2] and b[1] <= lon <= b[3]


def _cells(points, precision=5, cap=80):
    """Geohash cells around the points: the cell of each point plus the
    cells a little to each side, so reports just over an edge are found."""
    out = []
    d = 0.02   # about 2 km
    for lon, lat in points:
        for dy, dx in ((0, 0), (d, 0), (-d, 0), (0, d), (0, -d)):
            c = nostr.geohash(lat + dy, lon + dx, precision)
            if c not in out:
                out.append(c)
            if len(out) >= cap:
                return out
    return out


def _parse_time(s):
    # "2026-11-04T07:49:59.000+01:00" -> unix time
    try:
        from datetime import datetime
        return int(datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp())
    except Exception:
        return 0


# --------------------------------------------------------------------- DGT

def _dgt_type(record_type, cause, detail, lanes):
    if record_type == "SpeedManagement":
        return None
    if record_type == "RoadOrCarriagewayOrLaneManagement" and "allLanesCompleteCarriageway" in lanes:
        return "closed"
    if cause == "accident":
        return "accident"
    if cause == "vehicleObstruction":
        return "fire" if detail == "vehicleOnFire" else "stopped"
    if cause == "roadMaintenance":
        return "roadworks"
    if cause == "abnormalTraffic":
        return "jam"
    if cause == "poorEnvironment":
        return "weather"
    if cause in ("obstruction", "environmentalObstruction", "infrastructureDamageObstruction"):
        return "hazard"
    return None


def _parse_dgt(stream):
    now = time.time()
    out = []
    for _, el in ET.iterparse(stream):
        if _local_name(el.tag) != "situationRecord":
            continue
        rtype = (el.get(XSI_TYPE) or "").split(":")[-1]
        f = {"cause": None, "detail": None, "status": None, "start": None, "end": None,
             "road": "", "km": "", "town": "", "dest": ""}
        lanes = []
        points = {}
        for x in el.iter():
            n = _local_name(x.tag)
            t = (x.text or "").strip()
            if n == "causeType" and not f["cause"]:
                f["cause"] = t
            elif n in _DETAIL_TAGS and not f["detail"]:
                f["detail"] = t
            elif n == "validityStatus":
                f["status"] = t
            elif n == "overallStartTime":
                f["start"] = t
            elif n == "overallEndTime":
                f["end"] = t
            elif n == "laneUsage":
                lanes.append(t)
            elif n == "roadName" and not f["road"]:
                f["road"] = t
            elif n == "roadDestination" and not f["dest"]:
                f["dest"] = t
            elif n == "kilometerPoint" and not f["km"]:
                f["km"] = t
            elif n == "municipality" and not f["town"]:
                f["town"] = t
            elif n in ("from", "to", "pointByCoordinates", "point"):
                lat = lon = None
                for y in x.iter():
                    ln = _local_name(y.tag)
                    if ln == "latitude" and lat is None:
                        lat = y.text
                    elif ln == "longitude" and lon is None:
                        lon = y.text
                if lat and lon and n not in points:
                    points[n] = (float(lat), float(lon))
        rid = el.get("id")
        el.clear()
        if f["status"] not in (None, "active"):
            continue
        start = _parse_time(f["start"]) if f["start"] else 0
        end = _parse_time(f["end"]) if f["end"] else 0
        if start and start > now + 600:
            continue
        if end and end < now:
            continue
        kind = _dgt_type(rtype, f["cause"], f["detail"], lanes)
        if not kind:
            continue
        pt = points.get("from") or points.get("point") or points.get("pointByCoordinates") or points.get("to")
        if not pt:
            continue
        out.append({"id": "dgt:%s" % rid, "source": "dgt", "type": kind,
                    "lat": pt[0], "lon": pt[1], "created": start, "expires": end,
                    "road": f["road"], "km": f["km"], "town": f["town"], "dest": f["dest"],
                    "detail": f["detail"] or "", "up": 0, "down": 0, "heading": -1})
    return out


def _fetch_dgt():
    path = os.path.join(poor.CACHE_HOME_DIR, "dgt-incidents.xml.gz")
    req = urllib.request.Request(DGT_URL, headers={"User-Agent": USER_AGENT,
                                                   "Accept-Encoding": "gzip"})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read()
        if r.headers.get("Content-Encoding", "") != "gzip":
            data = gzip.compress(data)
    try:
        os.makedirs(poor.CACHE_HOME_DIR, exist_ok=True)
        with open(path + ".tmp", "wb") as f:
            f.write(data)
        os.replace(path + ".tmp", path)
    except OSError:
        pass
    return _parse_dgt(gzip.GzipFile(fileobj=io.BytesIO(data)))


# --------------------------------------------------------------- community

def _tag(ev, name):
    for t in ev.get("tags", []):
        if len(t) > 1 and t[0] == name:
            return t[1]
    return None


def _number(text, low, high):
    """A finite float within [low, high] from a tag value, or None."""
    try:
        v = float(text)
    except (TypeError, ValueError, OverflowError):
        return None
    if not math.isfinite(v) or not low <= v <= high:
        return None
    return v


def _merge_one(ev, now):
    # events come from strangers: nostr.query has checked the signature, but
    # the shape and every value are still checked before use
    if not nostr.well_formed(ev) or nostr.pow_bits(ev["id"]) < POW_BITS:
        return
    if _tag(ev, "t") != TOPIC or ev["kind"] != KIND:
        return
    created = ev["created_at"]
    if created > now + 300 or created < now - 24*3600:
        return
    vote = _tag(ev, "vote")
    if vote in ("up", "down"):
        rid = _tag(ev, "e")
        if not rid or len(rid) != 64:
            return
        votes = _state["votes"].setdefault(rid, {})
        if ev["pubkey"] not in votes and len(votes) >= MAX_VOTES_PER_REPORT:
            # full: the newest votes say most about now, so the oldest goes
            oldest = min(votes, key=lambda k: votes[k][1])
            if votes[oldest][1] >= created:
                return
            del votes[oldest]
        # one vote per key; a newer one from the same key replaces it
        old = votes.get(ev["pubkey"])
        if old is None or old[1] < created:
            votes[ev["pubkey"]] = (vote == "up", created)
        return
    kind = _tag(ev, "alert")
    if kind not in LIFETIME:
        return
    lat = _number(_tag(ev, "lat"), -90, 90)
    lon = _number(_tag(ev, "lon"), -180, 180)
    if lat is None or lon is None:
        return
    heading = _number(_tag(ev, "heading"), 0, 360)
    if ev["id"] not in _state["community"] and len(_state["community"]) >= MAX_REPORTS:
        _make_room()
    _state["community"][ev["id"]] = {
        "id": ev["id"], "source": "community", "type": kind,
        "lat": lat, "lon": lon, "created": created, "expires": 0,
        "road": "", "km": "", "town": "", "dest": "", "detail": "",
        "up": 0, "down": 0, "heading": int(heading) % 360 if heading is not None else -1}


def _make_room():
    """The report table is full: drop a tenth of it, first reports outside
    the watched area, then the oldest. New reports are never refused, so a
    flood can't lock out real ones; it can only push out old ones."""
    pts = _state["points"]
    box = _bbox(pts, 0.1) if pts else None
    reports = _state["community"]

    def keep_score(rid):
        a = reports[rid]
        inside = bool(box) and _in_bbox(a["lat"], a["lon"], box)
        return (inside, a["created"])
    for rid in sorted(reports, key=keep_score)[:max(1, MAX_REPORTS // 10)]:
        del reports[rid]


def _merge_community(events):
    now = time.time()
    with _lock:
        for ev in events:
            try:
                _merge_one(ev, now)
            except Exception:
                # one bad event must not drop the others
                continue


def _community_visible():
    """Reports still standing: within their lifetime since the report or the
    last confirmation (but never past MAX_LIFETIMES), and not voted down."""
    now = time.time()
    out = []
    with _lock:
        for rid, a in list(_state["community"].items()):
            votes = _state["votes"].get(rid, {}).values()
            life = LIFETIME[a["type"]]
            # only votes cast after the report and within its longest life count
            votes = [(up, c) for up, c in votes
                     if a["created"] - 60 <= c <= a["created"] + MAX_LIFETIMES * life]
            ups = [c for up, c in votes if up]
            downs = [c for up, c in votes if not up]
            last = max([a["created"]] + ups)
            expires = min(last + life, a["created"] + MAX_LIFETIMES * life)
            if now > expires:
                if now > expires + 3600:
                    del _state["community"][rid]
                continue
            if rid in _state["dismissed"]:
                continue
            if len(downs) >= 2 and len(downs) > len(ups):
                continue
            b = dict(a, up=len(ups), down=len(downs), expires=expires)
            out.append(b)
        # forget votes on reports that are gone
        for rid in list(_state["votes"]):
            if rid not in _state["community"]:
                cs = [c for _, c in _state["votes"][rid].values()]
                if not cs or max(cs) < now - 6*3600 or len(_state["votes"]) > 2 * MAX_REPORTS:
                    del _state["votes"][rid]
    return out


# ------------------------------------------------------------------ worker

def _work():
    while True:
        with _lock:
            points = list(_state["points"])
            _state["again"] = False
        result = []
        errors = []
        if points:
            box = _bbox(points, 0.05)
            # official incidents, Spain only
            if any(_in_bbox(p[1], p[0], SPAIN) for p in points):
                if time.time() - _state["dgt_time"] > DGT_MAX_AGE:
                    try:
                        _state["dgt"] = _fetch_dgt()
                        _state["dgt_time"] = time.time()
                    except Exception as e:
                        errors.append("DGT: %s" % e)
                result += [a for a in _state["dgt"] if _in_bbox(a["lat"], a["lon"], box)]
            # drivers' reports
            try:
                since = int(time.time()) - 4*3600
                events = nostr.query([{"kinds": [KIND], "#g": _cells(points), "since": since}],
                                     RELAYS, timeout=8, min_pow=POW_BITS)
                _merge_community(events)
            except Exception as e:
                errors.append("relays: %s" % e)
            result += [a for a in _community_visible() if _in_bbox(a["lat"], a["lon"], box)]
        with _lock:
            _state["last"] = result
            _state["last_box"] = box if points else None
        pyotherside.send("alerts.updated", result, "; ".join(errors))
        with _lock:
            if not _state["again"]:
                _state["busy"] = False
                return


def refresh(points):
    """Watch this area: points is a list of [lon, lat] (the route ahead, or
    just the current position). Results arrive as "alerts.updated"."""
    pts = [[float(p[0]), float(p[1])] for p in points if p and len(p) >= 2][:200]
    with _lock:
        _state["points"] = pts
        if _state["busy"]:
            _state["again"] = True
            return
        _state["busy"] = True
    threading.Thread(target=_work, daemon=True).start()


def current():
    """The last area's alerts again, with this phone's own reports and votes
    since then (no network)."""
    with _lock:
        box = _state.get("last_box")
        if box is None:
            return list(_state["last"])
        official = [a for a in _state["last"] if a["source"] != "community"]
    return official + [a for a in _community_visible() if _in_bbox(a["lat"], a["lon"], box)]


def _cell_tags(lat, lon):
    gh = nostr.geohash(lat, lon, 7)
    return [["g", gh[:4]], ["g", gh[:5]], ["g", gh[:6]]]


def report(kind, lat, lon, heading=-1):
    """Share a report. It shows on this phone at once; "alerts.reported"
    says how many relays took it."""
    if kind not in LIFETIME:
        raise ValueError("unknown alert type: %s" % kind)
    now = int(time.time())
    tags = [["t", TOPIC], ["alert", kind]] + _cell_tags(lat, lon) + [
        ["lat", "%.5f" % lat], ["lon", "%.5f" % lon],
        ["expiration", str(now + LIFETIME[kind] + 3600)],
        ["client", "LibreMaps"]]
    if heading is not None and heading >= 0:
        tags.append(["heading", str(int(heading) % 360)])

    def send():
        # proof of work takes seconds on a phone: keep it off the call queue
        ev = nostr.sign_event(KIND, tags, "", pow=POW_BITS)
        _merge_community([ev])
        res = nostr.publish(ev, RELAYS, timeout=8)
        ok = sum(1 for r in res.values() if r[0])
        pyotherside.send("alerts.reported", kind, ok, len(RELAYS))
    threading.Thread(target=send, daemon=True).start()
    return True


def vote(report_id, up):
    """Say a report is still there (up) or gone (down)."""
    with _lock:
        a = _state["community"].get(report_id)
        if not up:
            _state["dismissed"].add(report_id)
    if not a:
        return False
    now = int(time.time())
    tags = [["t", TOPIC], ["vote", "up" if up else "down"], ["e", report_id]] + \
        _cell_tags(a["lat"], a["lon"]) + [
        ["expiration", str(now + LIFETIME[a["type"]] + 3600)], ["client", "LibreMaps"]]
    def send():
        ev = nostr.sign_event(KIND, tags, "", pow=POW_BITS)
        _merge_community([ev])
        res = nostr.publish(ev, RELAYS, timeout=8)
        ok = sum(1 for r in res.values() if r[0])
        pyotherside.send("alerts.voted", report_id, bool(up), ok)
    threading.Thread(target=send, daemon=True).start()
    return True
