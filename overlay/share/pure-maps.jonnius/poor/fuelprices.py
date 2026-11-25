# -*- coding: utf-8 -*-

# LibreMaps: fuel prices for the place sheet, from each country's own open data. No keys.
#
# Where a country publishes one national file, the app downloads all of it, so the service
# learns nothing about the place. Where it only answers questions about an area, the app asks
# about a rounded area around the station, never the exact spot and never the user's position:
#
#   Spain     Ministry for Ecological Transition    one province at a time
#   France    prix-carburants (data.economie.gouv)  a ~10 km area (point rounded to 0.1 deg)
#   Italy     Ministry of Enterprises (MIMIT)       the whole country (two CSV files)
#   Portugal  DGEG                                  the whole country, one file per fuel
#   Austria   E-Control                             a ~1 km area; by law it only publishes
#                                                   the cheaper half of the stations
#   Slovenia  goriva.si                             a ~5 km area (point rounded to 0.05 deg)
#   Mexico    Comision Nacional de Energia          the whole country (two XML files)
#
# Adding a country: write a fetch function that returns {"stations": [[lat, lon, brand,
# hours, [[fuel, price], ...], date], ...]} and add it to COUNTRIES with its boxes.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

"""Fuel prices at a station, worldwide where open data exists."""

import csv
import datetime
import io
import json
import math
import os
import re
import threading
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

import poor
from poor import netlimit

__all__ = ("station", "country_at", "COUNTRIES")

USER_AGENT = "LibreMaps (open source maps for Ubuntu Touch; +https://github.com/juujbyg/libremaps-touch)"
MATCH_M = 150          # the station must be this close to the place
CAP = 32 << 20         # one download; the national files are 2 to 5 MB

_lock = threading.Lock()
_mem = {}              # cache key -> (fetched_at, data)


# ---------------------------------------------------------------- helpers

def _dist(lat1, lon1, lat2, lon2):
    x = math.radians(lon2 - lon1) * math.cos(math.radians((lat1 + lat2) / 2))
    y = math.radians(lat2 - lat1)
    return 6371000 * math.hypot(x, y)


def _get(url, timeout=30, accept="application/json"):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": accept})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return netlimit.read_capped(r, CAP)


def _json(url, timeout=30):
    return json.loads(_get(url, timeout).decode("utf-8"))


def _price(text):
    """'1,859 €' or 1.859 -> '1.859', or '' when it isn't a plain, sane price."""
    if isinstance(text, bool) or text is None:
        return ""
    if isinstance(text, (int, float)):
        v = float(text)
    else:
        m = re.fullmatch(r"\s*(\d{1,4}(?:[.,]\d{1,4})?)\s*€?\s*", str(text))
        if not m:
            return ""
        v = float(m.group(1).replace(",", "."))
    return ("%.3f" % v) if 0.05 < v < 1000 else ""


def _tz(name):
    try:
        from zoneinfo import ZoneInfo
        return ZoneInfo(name)
    except Exception:
        return None


def _show(dt, tz):
    """A datetime -> '24/11 07:31' in the country's time."""
    if dt is None:
        return ""
    z = _tz(tz) if tz else None
    if z is not None:
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=z)
        dt = dt.astimezone(z)
    return dt.strftime("%d/%m %H:%M")


def _parse_dt(text, fmt):
    try:
        return datetime.datetime.strptime(text.strip(), fmt)
    except (ValueError, AttributeError):
        return None


def _iso(text):
    try:
        return datetime.datetime.fromisoformat(text.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None


def _cached(key, max_age, fetch):
    """fetch() once per max_age, kept in memory and in the cache folder."""
    with _lock:
        hit = _mem.get(key)
        if hit and time.time() - hit[0] < max_age:
            return hit[1]
    path = os.path.join(poor.CACHE_HOME_DIR, "fuel-%s.json" % key)
    data = None
    try:
        if time.time() - os.path.getmtime(path) < max_age:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
    except Exception:
        data = None
    if data is None:
        try:
            data = fetch()
        except Exception:
            return None
        if data is None:
            return None
        try:
            os.makedirs(poor.CACHE_HOME_DIR, exist_ok=True)
            with open(path + ".tmp", "w", encoding="utf-8") as f:
                json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
            os.replace(path + ".tmp", path)
        except OSError:
            pass
    with _lock:
        _mem[key] = (time.time(), data)
    return data


# ---------------------------------------------------------------- Spain

ES_URL = ("https://sedeaplicaciones.minetur.gob.es/ServiciosRESTCarburantes/"
          "PreciosCarburantes/EstacionesTerrestres/FiltroProvincia/%s")
ES_FUELS = (("Precio Gasoleo A", "Diesel"),
            ("Precio Gasolina 95 E5", "95"),
            ("Precio Gasolina 98 E5", "98"),
            ("Precio Gasoleo Premium", "Diesel+"),
            ("Precio Gasolina 95 E10", "95 E10"),
            ("Precio Gasolina 95 E5 Premium", "95+"),
            ("Precio Gases licuados del petróleo", "LPG"),
            ("Precio Gas Natural Comprimido", "CNG"),
            ("Precio Diésel Renovable", "HVO"),
            ("Precio Adblue", "AdBlue"))
PROVINCES = {"01":(42.85,-2.7),"02":(38.95,-1.87),"03":(38.38,-0.53),"04":(36.99,-2.41),"05":(40.64,-4.79),"06":(38.74,-6.34),"07":(39.57,2.85),"08":(41.48,2.09),"09":(42.31,-3.6),"10":(39.75,-6.09),"11":(36.5,-5.95),"12":(40.05,-0.06),"13":(38.98,-3.56),"14":(37.77,-4.73),"15":(43.16,-8.47),"16":(39.74,-2.34),"17":(42.07,2.84),"18":(37.19,-3.5),"19":(40.7,-3.01),"20":(43.23,-2.09),"21":(37.39,-6.88),"22":(42.04,-0.03),"23":(37.97,-3.6),"24":(42.55,-5.88),"25":(41.8,0.9),"26":(42.38,-2.37),"27":(43.08,-7.5),"28":(40.37,-3.69),"29":(36.7,-4.62),"30":(37.82,-1.23),"31":(42.62,-1.72),"32":(42.24,-7.74),"33":(43.43,-5.88),"34":(42.23,-4.48),"35":(28.22,-14.98),"36":(42.14,-8.39),"37":(40.86,-5.86),"38":(28.34,-16.65),"39":(43.1,-3.84),"40":(41.09,-4.12),"41":(37.36,-5.8),"42":(41.63,-2.53),"43":(41.06,1.02),"44":(40.67,-0.78),"45":(39.9,-4.04),"46":(39.36,-0.48),"47":(41.59,-4.79),"48":(43.27,-2.88),"49":(41.72,-5.78),"50":(41.64,-1.04),"51":(35.89,-5.32),"52":(35.28,-2.94)}


def es_provinces(lat, lon, postcode):
    pc = re.sub(r"\D", "", postcode or "")
    if len(pc) == 5 and pc[:2] in PROVINCES:
        return [pc[:2]]
    return sorted(PROVINCES, key=lambda k: _dist(lat, lon, *PROVINCES[k]))[:2]


def _es_fetch(pid):
    full = _json(ES_URL % pid, timeout=15)
    when = _show(_parse_dt(full.get("Fecha", ""), "%d/%m/%Y %H:%M:%S"), None)
    out = []
    for e in full.get("ListaEESSPrecio", []):
        try:
            lat = float(e["Latitud"].replace(",", "."))
            lon = float(e["Longitud (WGS84)"].replace(",", "."))
        except Exception:
            continue
        prices = [[name, _price(e.get(key))] for key, name in ES_FUELS if _price(e.get(key))]
        out.append([lat, lon, e.get("Rótulo", ""), e.get("Horario", ""), prices, when])
    return {"stations": out}


def _es(lat, lon, postcode):
    for pid in es_provinces(lat, lon, postcode):
        # "es-28", not "28": older versions kept another layout in fuel-28.json
        yield _cached("es-" + pid, 6 * 3600, lambda pid=pid: _es_fetch(pid))


# ---------------------------------------------------------------- France

FR_URL = ("https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/"
          "prix-des-carburants-en-france-flux-instantane-v2/exports/json?")
FR_FUELS = (("gazole", "Diesel"), ("sp95", "95"), ("e10", "95 E10"), ("sp98", "98"),
            ("e85", "E85"), ("gplc", "LPG"))


def _fr_fetch(clat, clon):
    where = "within_distance(geom, geom'POINT(%.1f %.1f)', 15km)" % (clon, clat)
    fields = ["id", "geom", "adresse"] + ["%s_%s" % (k, s) for k, _ in FR_FUELS for s in ("prix", "maj")]
    rows = _json(FR_URL + urllib.parse.urlencode({"where": where, "select": ",".join(fields)}))
    out = []
    for r in rows if isinstance(rows, list) else []:
        g = r.get("geom") or {}
        try:
            lat, lon = float(g["lat"]), float(g["lon"])
        except Exception:
            continue
        prices = [[name, _price(r.get(k + "_prix"))] for k, name in FR_FUELS if _price(r.get(k + "_prix"))]
        times = [t for t in (_iso(r.get(k + "_maj") or "") for k, _ in FR_FUELS) if t]
        if prices:
            out.append([lat, lon, "", "", prices, _show(max(times), "Europe/Paris") if times else ""])
    return {"stations": out}


def _fr(lat, lon, postcode):
    clat, clon = round(lat, 1), round(lon, 1)
    yield _cached("fr-%.1f_%.1f" % (clat, clon), 3 * 3600, lambda: _fr_fetch(clat, clon))


# ---------------------------------------------------------------- Italy

IT_PRICES = "https://www.mimit.gov.it/images/exportCSV/prezzo_alle_8.csv"
IT_STATIONS = "https://www.mimit.gov.it/images/exportCSV/anagrafica_impianti_attivi.csv"


def _it_fuel(desc):
    d = desc.lower()
    if d == "benzina":
        return "95"
    if d == "gasolio":
        return "Diesel"
    if d == "gpl":
        return "LPG"
    if d in ("metano", "l-gnc"):
        return "CNG"
    if "gnl" in d:
        return "LNG"
    if "hvo" in d:
        return "HVO"
    if "gasolio" in d or "diesel" in d:
        return "Diesel+"
    if "benzina" in d or "super" in d or "perform" in d or "v-power" in d or "v power" in d:
        return "95+"
    return None


def _csv_rows(raw):
    text = raw.decode("utf-8", errors="replace")
    lines = text.splitlines()
    # the first line is "Estrazione del <date>", the second the header
    return csv.reader(io.StringIO("\n".join(lines[2:])), delimiter="|", quoting=csv.QUOTE_NONE)


def _it_fetch():
    where = {}
    for row in _csv_rows(_get(IT_STATIONS, 60, "text/csv")):
        if len(row) < 10:
            continue
        try:
            where[row[0]] = (float(row[-2]), float(row[-1]), row[2])
        except ValueError:
            continue
    best = {}   # (id, fuel) -> (self?, price, date)
    for row in _csv_rows(_get(IT_PRICES, 60, "text/csv")):
        if len(row) < 5 or row[0] not in where:
            continue
        fuel = _it_fuel(row[1].strip())
        price = _price(row[2])
        if not fuel or not price:
            continue
        cand = (row[3].strip() == "1", -float(price), row[4])
        key = (row[0], fuel)
        # self-service price first (that's the one most drivers pay), then the lowest
        if key not in best or cand[:2] > best[key][:2]:
            best[key] = cand
    by_id = {}
    for (sid, fuel), (_, neg, when) in best.items():
        by_id.setdefault(sid, []).append([fuel, "%.3f" % -neg, when])
    order = ["Diesel", "95", "Diesel+", "95+", "LPG", "CNG", "LNG", "HVO"]
    out = []
    for sid, items in by_id.items():
        lat, lon, brand = where[sid]
        items.sort(key=lambda i: order.index(i[0]))
        dates = [d for d in (_parse_dt(i[2], "%d/%m/%Y %H:%M:%S") for i in items) if d]
        out.append([lat, lon, brand, "", [[i[0], i[1]] for i in items],
                    _show(max(dates), "Europe/Rome") if dates else ""])
    return {"stations": out}


def _it(lat, lon, postcode):
    # the Ministry publishes once a day, at 8 in the morning
    yield _cached("it", 8 * 3600, _it_fetch)


# ---------------------------------------------------------------- Portugal

PT_URL = ("https://precoscombustiveis.dgeg.gov.pt/api/PrecoComb/PesquisarPostos?"
          "idsTiposComb=%d&qtdPorPagina=20000&pagina=1")
PT_FUELS = ((2101, "Diesel"), (3201, "95"), (3405, "98"), (2105, "Diesel+"), (1120, "LPG"))


def _pt_fetch():
    stations = {}
    for code, name in PT_FUELS:
        for e in _json(PT_URL % code, timeout=60).get("resultado") or []:
            try:
                lat, lon = float(e["Latitude"]), float(e["Longitude"])
            except Exception:
                continue
            price = _price(e.get("Preco"))
            if not price:
                continue
            s = stations.setdefault(e.get("Id"), [lat, lon, e.get("Marca") or "", "", [], None])
            s[4].append([name, price])
            d = _parse_dt(e.get("DataAtualizacao", ""), "%Y-%m-%d %H:%M")
            if d and (s[5] is None or d > s[5]):
                s[5] = d
    for s in stations.values():
        s[5] = _show(s[5], "Europe/Lisbon")
    return {"stations": list(stations.values())}


def _pt(lat, lon, postcode):
    yield _cached("pt", 6 * 3600, _pt_fetch)


# ---------------------------------------------------------------- Austria

AT_URL = ("https://api.e-control.at/sprit/1.0/search/gas-stations/by-address?"
          "latitude=%.2f&longitude=%.2f&fuelType=%s&includeClosed=true")
AT_FUELS = (("DIE", "Diesel"), ("SUP", "95"), ("GAS", "CNG"))


def _at_fetch(clat, clon):
    stations = {}
    for code, name in AT_FUELS:
        rows = _json(AT_URL % (clat, clon, code), timeout=15)
        for e in rows if isinstance(rows, list) else []:
            loc = e.get("location") or {}
            try:
                lat, lon = float(loc["latitude"]), float(loc["longitude"])
            except Exception:
                continue
            for p in e.get("prices") or []:
                price = _price(p.get("amount"))
                if price:
                    s = stations.setdefault(e.get("id"), [lat, lon, e.get("name") or "", "", [], ""])
                    s[4].append([name, price])
    when = _show(datetime.datetime.now(datetime.timezone.utc), "Europe/Vienna")
    for s in stations.values():
        s[5] = when
    return {"stations": list(stations.values())}


def _at(lat, lon, postcode):
    clat, clon = round(lat, 2), round(lon, 2)
    yield _cached("at-%.2f_%.2f" % (clat, clon), 3600, lambda: _at_fetch(clat, clon))


# ---------------------------------------------------------------- Slovenia

SI_URL = "https://goriva.si/api/v1/search/?position=%.2f,%.2f&radius=10000"
SI_FUELS = (("dizel", "Diesel"), ("95", "95"), ("98", "98"), ("100", "100"),
            ("dizel-premium", "Diesel+"), ("avtoplin-lpg", "LPG"), ("hvo", "HVO"),
            ("cng", "CNG"), ("lng", "LNG"))


def _si_fetch(clat, clon):
    url, out, pages = SI_URL % (clat, clon), [], 0
    while url and pages < 10:
        page = _json(url, timeout=15)
        pages += 1
        for e in page.get("results") or []:
            try:
                lat, lon = float(e["lat"]), float(e["lng"])
            except Exception:
                continue
            p = e.get("prices") or {}
            prices = [[name, _price(p.get(k))] for k, name in SI_FUELS if _price(p.get(k))]
            if prices:
                out.append([lat, lon, e.get("name") or "", "", prices, ""])
        url = page.get("next")
        if url and not url.startswith("https://goriva.si/"):
            break
    return {"stations": out}


def _si(lat, lon, postcode):
    clat, clon = round(lat * 20) / 20, round(lon * 20) / 20
    yield _cached("si-%.2f_%.2f" % (clat, clon), 6 * 3600, lambda: _si_fetch(clat, clon))


# ---------------------------------------------------------------- Mexico

MX_PLACES = "https://publicacionexterna.azurewebsites.net/publicaciones/places"
MX_PRICES = "https://publicacionexterna.azurewebsites.net/publicaciones/prices"
MX_FUELS = {"regular": "Regular", "premium": "Premium", "diesel": "Diesel"}


def _mx_fetch():
    where = {}
    for _, el in ET.iterparse(io.BytesIO(_get(MX_PLACES, 60, "application/xml"))):
        if el.tag != "place":
            continue
        try:
            where[el.get("place_id")] = (float(el.findtext("location/y")),
                                         float(el.findtext("location/x")),
                                         (el.findtext("name") or "").strip())
        except (TypeError, ValueError):
            pass
        el.clear()
    out = []
    for _, el in ET.iterparse(io.BytesIO(_get(MX_PRICES, 60, "application/xml"))):
        if el.tag != "place":
            continue
        pid = el.get("place_id")
        prices = []
        for g in el.findall("gas_price"):
            name, price = MX_FUELS.get(g.get("type", "")), _price(g.text)
            if name and price:
                prices.append([name, price])
        if pid in where and prices:
            lat, lon, brand = where[pid]
            out.append([lat, lon, brand, "", prices, ""])
        el.clear()
    return {"stations": out}


def _mx(lat, lon, postcode):
    yield _cached("mx", 12 * 3600, _mx_fetch)


# ---------------------------------------------------------------- countries

# code, boxes (south, west, north, east), source shown on the sheet, unit, fetch
COUNTRIES = (
    ("es", ((35.8, -9.4, 43.9, 4.4), (27.5, -18.3, 29.5, -13.3), (35.1, -5.45, 35.95, -2.85)),
     "MITECO", "€/L", _es),
    ("pt", ((36.9, -9.6, 42.2, -6.15),), "DGEG", "€/L", _pt),
    ("si", ((45.42, 13.37, 46.88, 16.61),), "goriva.si", "€/L", _si),
    ("at", ((46.37, 9.53, 49.02, 17.16),), "E-Control", "€/L", _at),
    ("it", ((36.6, 6.6, 47.1, 18.6), (35.4, 11.9, 37.6, 15.7), (38.8, 8.1, 41.3, 9.9)),
     "MIMIT", "€/L", _it),
    ("fr", ((42.3, -5.2, 51.1, 8.3), (41.3, 8.5, 43.1, 9.6)),
     "prix-carburants.gouv.fr", "€/L", _fr),
    ("mx", ((14.5, -118.5, 32.8, -86.7),), "CNE", "MX$/L", _mx),
)


def country_at(lat, lon):
    """The countries whose data may cover this point, smallest box first."""
    found = []
    for c in COUNTRIES:
        for b in c[1]:
            if b[0] <= lat <= b[2] and b[1] <= lon <= b[3]:
                found.append(((b[2] - b[0]) * (b[3] - b[1]), c))
                break
    return [c for _, c in sorted(found, key=lambda f: f[0])]


def station(lat, lon, postcode=""):
    """The open-data entry for the fuel station at this point, or None:
    {"country", "brand", "hours", "prices": [[fuel, "1.234"]], "date", "source", "unit"}."""
    for code, _, source, unit, fetch in country_at(lat, lon):
        for data in fetch(lat, lon, postcode):
            if not data:
                continue
            best, best_d = None, MATCH_M
            for s in data.get("stations", []):
                d = _dist(lat, lon, s[0], s[1])
                if d < best_d:
                    best, best_d = s, d
            if best and len(best) >= 6 and best[4]:
                return {"country": code, "brand": best[2], "hours": best[3], "prices": best[4],
                        "date": best[5], "source": source, "unit": unit}
    return None
