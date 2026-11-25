# -*- coding: utf-8 -*-

# LibreMaps: extra facts for the place sheet, Waze style.
#
# - Fuel stations: prices from each country's open data, see poor/fuelprices.py (Spain,
#   France, Italy, Portugal, Austria, Slovenia, Mexico). In Spain the same data has the
#   station's opening hours.
# - Other places: OpenStreetMap's opening_hours, phone and website, from one Nominatim
#   search around the place (at most one request a second, as its policy asks), or
#   Overpass when Nominatim has nothing.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

"""Opening hours and fuel prices for the place sheet."""

import datetime
import json
import math
import os
import re
import threading
import time
import urllib.parse
import urllib.request

import poor
from poor import fuelprices

__all__ = ("lookup", "request", "parse_osm_hours", "parse_es_hours", "status")

USER_AGENT = "LibreMaps (open source maps for Ubuntu Touch)"
NOMINATIM = "https://nominatim.openstreetmap.org/search"
OVERPASS = ("https://overpass.kumi.systems/api/interpreter",
            "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
            "https://overpass-api.de/api/interpreter")

# the middle of each province's stations, to guess the province when a place has no postcode


_lock = threading.Lock()
_nominatim_lock = threading.Lock()
_nominatim_last = [0.0]


def _dist(lat1, lon1, lat2, lon2):
    """Metres between two points (equirectangular, fine below a few km)."""
    x = math.radians(lon2 - lon1) * math.cos(math.radians((lat1 + lat2) / 2))
    y = math.radians(lat2 - lat1)
    return 6371000 * math.hypot(x, y)


def in_spain(lat, lon):
    return (35.8 <= lat <= 43.9 and -9.4 <= lon <= 4.4) or \
           (27.5 <= lat <= 29.5 and -18.3 <= lon <= -13.3) or \
           (35.1 <= lat <= 35.95 and -5.45 <= lon <= -2.85)


_ZONES = {"fr": "Europe/Paris", "it": "Europe/Rome", "pt": "Europe/Lisbon",
          "at": "Europe/Vienna", "si": "Europe/Ljubljana"}


def _tz(lat, lon):
    try:
        from zoneinfo import ZoneInfo
        if in_spain(lat, lon):
            return ZoneInfo("Atlantic/Canary" if lat < 30 else "Europe/Madrid")
        for c in fuelprices.country_at(lat, lon):
            if c[0] in _ZONES:
                return ZoneInfo(_ZONES[c[0]])
    except Exception:
        pass
    return None


def _now(lat, lon):
    tz = _tz(lat, lon)
    return datetime.datetime.now(tz) if tz else datetime.datetime.now()


# ---------------------------------------------------------------- opening hours
# A week is {weekday 0..6 (Monday 0): [(start_min, end_min), ...]}; end may pass 1440.

_OSM_DAYS = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
_ES_DAYS = ["L", "M", "X", "J", "V", "S", "D"]


def _days(spec, names):
    out = []
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            a, b = (p.strip() for p in part.split("-", 1))
            if a not in names or b not in names:
                return None
            i, j = names.index(a), names.index(b)
            k = i
            while True:
                out.append(k)
                if k == j:
                    break
                k = (k + 1) % 7
        elif part in names:
            out.append(names.index(part))
        else:
            return None
    return out


def _times(spec):
    spec = spec.strip()
    if spec.upper() in ("24H", "24/7", "00:00-24:00", "00:00-23:59"):
        return [(0, 1440)]
    out = []
    for part in re.split(r"\s*(?:,|\by\b)\s*", spec):
        m = re.fullmatch(r"(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})\+?", part.strip())
        if not m:
            return None
        a = int(m.group(1)) * 60 + int(m.group(2))
        b = int(m.group(3)) * 60 + int(m.group(4))
        if b == 1439:
            b = 1440
        if b <= a:
            b += 1440          # past midnight
        out.append((a, b))
    return out or None


def parse_osm_hours(text):
    """OSM opening_hours in its common forms; None when it's something fancier."""
    text = (text or "").strip()
    if not text:
        return None
    if text == "24/7":
        return {d: [(0, 1440)] for d in range(7)}
    week = {d: [] for d in range(7)}
    for rule in text.split(";"):
        rule = re.sub(r"\bPH\s+off\b|,?\s*\bPH\b", "", rule).strip().strip(",").strip()
        if not rule:
            continue
        m = re.fullmatch(r"([A-Za-z,\- ]*?)\s*(off|closed|[\d:,\-+ ]+|24/7)", rule)
        if not m:
            return None
        days = _days(m.group(1).replace(" ", ""), _OSM_DAYS) if m.group(1).strip() else list(range(7))
        if days is None:
            return None
        if m.group(2) in ("off", "closed"):
            for d in days:
                week[d] = []
            continue
        times = _times(m.group(2))
        if times is None:
            return None
        for d in days:
            week[d] = list(times)      # a later rule replaces earlier ones for its days
    return week


def parse_es_hours(text):
    """The Ministry's 'Horario', e.g. 'L-V: 06:00-22:00; S-D: 07:00-22:00' or 'L-D: 24H'."""
    text = (text or "").strip()
    if not text:
        return None
    week = {d: [] for d in range(7)}
    for rule in text.split(";"):
        if not rule.strip():
            continue
        if ":" not in rule:
            return None
        days, times = rule.split(":", 1)
        days = _days(days.replace(" ", ""), _ES_DAYS)
        times = _times(times)
        if days is None or times is None:
            return None
        for d in days:
            week[d] = list(times)
    return week


def status(week, now):
    """{"state": "always"|"open"|"closed", "time": "HH:MM", "day": weekday or -1} or None."""
    if not week or not any(week.values()):
        return None
    if all(week[d] == [(0, 1440)] for d in range(7)):
        return {"state": "always", "time": "", "day": -1}
    today = now.weekday()
    minute = now.hour * 60 + now.minute
    # open now? (also ranges from yesterday that run past midnight)
    for day, offset in ((today, 0), ((today - 1) % 7, 1440)):
        for a, b in week[day]:
            if a <= minute + offset < b:
                end = b - offset
                # a range ending at midnight that continues tomorrow from 00:00
                if end >= 1440 and week[(today + 1) % 7] and week[(today + 1) % 7][0][0] == 0:
                    end = 1440 + week[(today + 1) % 7][0][1]
                if end - minute >= 1440:
                    return {"state": "open", "time": "", "day": -1}
                return {"state": "open", "time": "%02d:%02d" % ((end // 60) % 24, end % 60), "day": -1}
    for k in range(8):
        day = (today + k) % 7
        for a, b in sorted(week[day]):
            if k > 0 or a > minute:
                return {"state": "closed", "time": "%02d:%02d" % (a // 60, a % 60),
                        "day": -1 if k == 0 else (-2 if k == 1 else day)}
    return None


# ---------------------------------------------------------------- fuel (Spain)

def _province_guess(lat, lon, postcode):
    return fuelprices.es_provinces(lat, lon, postcode)


def _is_fuel(poi_type, title):
    t = (poi_type or "").lower()
    return any(w in t for w in ("fuel", "gasolin", "carbur", "petrol", "gas station", "tankstelle",
                                "station-service", "distributore", "combust", "bencin", "tankovaln"))


def fuel_station(lat, lon, title, postcode, poi_type):
    """The open-data entry for the fuel station at this place, or None."""
    if not _is_fuel(poi_type, title):
        return None
    return fuelprices.station(lat, lon, postcode)


# ---------------------------------------------------------------- OpenStreetMap

def nominatim_tags(lat, lon, title):
    """Extra tags of the named place within ~150 m, from Nominatim; None if it failed."""
    d = 0.0015
    url = NOMINATIM + "?" + urllib.parse.urlencode({
        "q": title, "format": "jsonv2", "limit": 3, "bounded": 1, "extratags": 1,
        "viewbox": "%f,%f,%f,%f" % (lon - d, lat + d, lon + d, lat - d)})
    with _nominatim_lock:
        wait = 1.0 - (time.time() - _nominatim_last[0])
        if wait > 0:
            time.sleep(wait)
        _nominatim_last[0] = time.time()
    try:
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=6) as r:
            data = json.loads(r.read(1024 * 1024).decode("utf-8"))
    except Exception:
        return None
    best = None
    for p in data if isinstance(data, list) else []:
        try:
            dist = _dist(lat, lon, float(p["lat"]), float(p["lon"]))
        except Exception:
            continue
        if dist < 200 and (best is None or dist < best[0]):
            best = (dist, p.get("extratags") or {})
    return best[1] if best else {}


def osm_tags(lat, lon, title):
    """Tags of the named place at this point: Nominatim first, then the first Overpass server."""
    if not title:
        return {}
    tags = nominatim_tags(lat, lon, title)
    if tags:
        return tags
    name = title.replace("\\", "\\\\").replace('"', '\\"')
    q = '[out:json][timeout:8];nwr(around:60,%f,%f)["name"="%s"];out tags 1;' % (lat, lon, name)
    body = urllib.parse.urlencode({"data": q}).encode()
    for url in OVERPASS:
        try:
            req = urllib.request.Request(url, data=body, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=7) as r:
                data = json.loads(r.read(1024 * 1024).decode("utf-8"))
            els = data.get("elements") or []
            return els[0].get("tags", {}) if els else {}
        except Exception:
            continue
    return {}


def _when(lat, lon):
    return _now(lat, lon)


def lookup(x, y, title, poi_type, postcode, early=None):
    """Everything extra for the sheet: {"hours", "fuel", "fuel_date", "fuel_source",
    "fuel_unit", "phone", "website"}. early(partial) gets the fuel prices first, when
    the opening hours still have to be looked up."""
    lat, lon = float(y), float(x)
    out = {"hours": None, "fuel": [], "fuel_date": "", "fuel_source": "", "fuel_unit": "",
           "phone": "", "website": ""}
    week = None
    try:
        st = fuel_station(lat, lon, title, postcode, poi_type)
    except Exception:
        st = None
    if st:
        out["fuel"] = [{"name": n, "price": p} for n, p in st["prices"]]
        out["fuel_date"] = st["date"]
        out["fuel_source"] = st["source"]
        out["fuel_unit"] = st["unit"]
        if st["country"] == "es":
            week = parse_es_hours(st["hours"])
        if week is None and early:
            # show the prices now; the OpenStreetMap lookup for hours can take many seconds
            early(dict(out))
    if week is None:
        try:
            tags = osm_tags(lat, lon, title)
        except Exception:
            tags = {}
        week = parse_osm_hours(tags.get("opening_hours", ""))
        out["phone"] = tags.get("phone") or tags.get("contact:phone") or ""
        out["website"] = tags.get("website") or tags.get("contact:website") or ""
    if week is not None:
        out["hours"] = status(week, _when(lat, lon))
    return out


def request(key, x, y, title, poi_type, postcode):
    """Look up on a thread (a download can take seconds) and answer with a "placeinfo.ready" event."""
    def send(result):
        try:
            import pyotherside
            pyotherside.send("placeinfo.ready", key, result)
        except Exception:
            pass

    sent = []

    def early(partial):
        sent.append(partial)
        send(partial)

    def work():
        try:
            result = lookup(x, y, title, poi_type, postcode, early=early)
        except Exception:
            result = sent[-1] if sent else None   # keep the prices already shown
        send(result)
    threading.Thread(target=work, daemon=True).start()
