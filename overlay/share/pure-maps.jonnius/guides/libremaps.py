# -*- coding: utf-8 -*-
"""
Nearby places from OpenStreetMap through public Overpass servers.

No account, no API key. Outside services used: the Overpass servers below
(kumi.systems, maps.mail.ru, overpass-api.de), Photon, Nominatim (one request,
only when Photon finds nothing) and, only when "near" is typed as text, the
app's own geocoder (Photon).

Speed: public Overpass servers often take 20 s or time out, while Photon
answers in about a second. Both are asked at once. Overpass wins if it answers
within FAST seconds; otherwise Photon's list is shown, and a late Overpass
answer still lands in the cache so the next search for the same place is
instant and complete.
"""

import concurrent.futures
import copy
import json
import math
import poor
from poor import netlimit
import threading
import time
import urllib.parse
import urllib.request

SERVERS = [
    "https://overpass.kumi.systems/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass-api.de/api/interpreter",
]
OVERPASS_TIMEOUT = 15     # seconds per server; a late answer still fills the cache
OVERPASS_STAGGER = 1.0    # seconds between starting each server (don't hit all at once)
FAST = 1.5                # how long Overpass gets before Photon's list is shown
PHOTON_TIMEOUT = 6
DEADLINE = 16             # give up entirely after this
PHOTON = "https://photon.komoot.io/api/"
NOMINATIM = "https://nominatim.openstreetmap.org/search"
# Nominatim's special phrases: the English word for each type
NOMINATIM_WORDS = {
    "Restaurant": "restaurant", "Café": "cafe", "Bar or pub": "bar", "Fast food": "fast food",
    "Bakery": "bakery", "Supermarket": "supermarket", "Pharmacy": "pharmacy",
    "Hospital": "hospital", "Fuel station": "fuel", "Charging station": "charging station",
    "Parking": "parking", "ATM": "atm", "Bank": "bank", "Post office": "post office",
    "Public toilets": "toilets", "Hotel": "hotel", "Museum": "museum", "Cinema": "cinema",
    "Park": "park", "Gym": "fitness centre", "Bus stop": "bus stop",
    "Metro station": "subway station", "Train station": "train station",
    "Bicycle rental": "bicycle rental",
}

# Fallback through Photon: it only matches words in a place's name, so each
# type lists an OSM tag filter and the words people use for it.
PHOTON_TAGS = {
    "Restaurant": ("amenity:restaurant", ["restaurante", "restaurant"]),
    "Café": ("amenity:cafe", ["café", "cafe", "cafetería"]),
    "Bar or pub": ("amenity:bar", ["bar", "pub", "taberna"]),
    "Fast food": ("amenity:fast_food", ["burger", "pizza", "kebab"]),
    "Bakery": ("shop:bakery", ["panadería", "bakery", "pastelería"]),
    "Supermarket": ("shop:supermarket", ["supermercado", "supermarket", "mercadona", "carrefour", "dia"]),
    "Pharmacy": ("amenity:pharmacy", ["farmacia", "pharmacy"]),
    "Hospital": ("amenity:hospital", ["hospital", "clínica", "centro de salud"]),
    "Fuel station": ("amenity:fuel", ["gasolinera", "fuel", "repsol", "cepsa", "shell", "bp"]),
    "Charging station": ("amenity:charging_station", ["carga", "charging", "cargador"]),
    "Parking": ("amenity:parking", ["parking", "aparcamiento"]),
    "ATM": ("amenity:atm", ["cajero", "atm"]),
    "Bank": ("amenity:bank", ["banco", "bank", "caixa"]),
    "Post office": ("amenity:post_office", ["correos", "post"]),
    "Public toilets": ("amenity:toilets", ["aseos", "toilets", "wc"]),
    "Hotel": ("tourism:hotel", ["hotel", "hostal"]),
    "Museum": ("tourism:museum", ["museo", "museum"]),
    "Cinema": ("amenity:cinema", ["cine", "cinema"]),
    "Park": ("leisure:park", ["parque", "park"]),
    "Gym": ("leisure:fitness_centre", ["gimnasio", "gym", "fitness"]),
    "Bus stop": ("highway:bus_stop", ["parada", "bus"]),
    "Metro station": ("railway:station", ["metro", "estación"]),
    "Train station": ("railway:station", ["estación", "station", "cercanías"]),
    "Bicycle rental": ("amenity:bicycle_rental", ["bici", "bike"]),
}
USER_AGENT = "LibreMaps/0.1 (+https://github.com/juujbyg)"

# label -> list of Overpass tag filters
TYPES = {
    "Restaurant": ['["amenity"="restaurant"]'],
    "Café": ['["amenity"="cafe"]'],
    "Bar or pub": ['["amenity"~"^(bar|pub)$"]'],
    "Fast food": ['["amenity"="fast_food"]'],
    "Bakery": ['["shop"="bakery"]'],
    "Supermarket": ['["shop"~"^(supermarket|convenience)$"]'],
    "Pharmacy": ['["amenity"="pharmacy"]'],
    "Hospital": ['["amenity"~"^(hospital|clinic)$"]'],
    "Fuel station": ['["amenity"="fuel"]'],
    "Charging station": ['["amenity"="charging_station"]'],
    "Parking": ['["amenity"="parking"]'],
    "ATM": ['["amenity"="atm"]'],
    "Bank": ['["amenity"="bank"]'],
    "Post office": ['["amenity"="post_office"]'],
    "Public toilets": ['["amenity"="toilets"]'],
    "Hotel": ['["tourism"~"^(hotel|hostel|guest_house)$"]'],
    "Museum": ['["tourism"="museum"]'],
    "Cinema": ['["amenity"="cinema"]'],
    "Park": ['["leisure"="park"]'],
    "Gym": ['["leisure"="fitness_centre"]'],
    "Bus stop": ['["highway"="bus_stop"]'],
    "Metro station": ['["railway"="station"]["station"="subway"]', '["station"="subway"]'],
    "Train station": ['["railway"="station"]["station"!="subway"]'],
    "Bicycle rental": ['["amenity"="bicycle_rental"]'],
}

cache = {}
cache_source = {}         # key -> "overpass" or "photon"
_lock = threading.Lock()
_pool = concurrent.futures.ThreadPoolExecutor(max_workers=8)    # one search = 2 jobs
_net = concurrent.futures.ThreadPoolExecutor(max_workers=12)    # Overpass requests


def normalize(t):
    return t.lower().replace("é", "e")


def autocomplete_type(query, params=None):
    query = normalize(query)
    out = []
    for label in TYPES:
        pos = normalize(label).find(query)
        if pos >= 0:
            out.append((pos, label))
    out.sort()
    return [{"label": label} for _pos, label in out]


def prepare_point(point):
    if isinstance(point, (list, tuple)):
        return float(point[0]), float(point[1])
    results = poor.Geocoder("default").geocode(point, params=dict(limit=1))
    return float(results[0]["x"]), float(results[0]["y"])


def build_query(filters, name, x, y, radius, limit):
    around = "(around:%d,%.6f,%.6f)" % (radius, y, x)
    namef = ""
    if name:
        # case-insensitive name match; strip characters with meaning in regex
        safe = "".join(c for c in name if c.isalnum() or c in " -'")
        namef = '["name"~"%s",i]' % safe
    lines = []
    for f in filters:
        lines.append("nwr%s%s%s;" % (around, f, namef))
    return "[out:json][timeout:25];(%s);out center %d;" % ("".join(lines), limit * 3)


def _overpass_one(server, body, delay, done):
    if delay and done.wait(delay):
        return None                      # another server already answered
    req = urllib.request.Request(
        server, data=body,
        headers={"User-Agent": USER_AGENT,
                 "Content-Type": "application/x-www-form-urlencoded"})
    with urllib.request.urlopen(req, timeout=OVERPASS_TIMEOUT) as r:
        data = json.loads(netlimit.read_capped(r, netlimit.REPLY).decode("utf-8"))
    if "elements" not in data:
        raise RuntimeError("bad Overpass answer")
    return data


def overpass(query):
    """Ask the servers a second apart; the first good answer wins."""
    body = ("data=" + urllib.parse.quote(query)).encode()
    done = threading.Event()
    futures = [_net.submit(_overpass_one, s, body, i * OVERPASS_STAGGER, done)
               for i, s in enumerate(SERVERS)]
    last = None
    for f in concurrent.futures.as_completed(futures):
        try:
            data = f.result()
        except Exception as error:
            last = error
            continue
        if data is not None:
            done.set()
            return data
    raise last or RuntimeError("no Overpass answer")


def photon_places(label, x, y, radius, name):
    """Places of one type through Photon, inside the radius, nearest first."""
    tag, words = PHOTON_TAGS[label]
    dlat = radius / 111320.0
    dlon = radius / (111320.0 * max(0.1, math.cos(math.radians(y))))
    bbox = "%f,%f,%f,%f" % (x - dlon, y - dlat, x + dlon, y + dlat)
    found = {}

    def ask(word):
        url = PHOTON + "?" + urllib.parse.urlencode(
            {"q": word, "bbox": bbox, "osm_tag": tag, "limit": 40, "lat": y, "lon": x})
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=PHOTON_TIMEOUT) as r:
                return json.loads(netlimit.read_capped(r, netlimit.REPLY).decode("utf-8"))
        except Exception:
            return {}

    # own small pool: photon_places runs inside a _pool worker, so reusing
    # _pool here could wait on itself
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        answers = list(pool.map(ask, [name] if name else words[:3]))  # be gentle on a free service
    for data in answers:
        for f in data.get("features", []):
            p = f.get("properties", {})
            ex, ey = f["geometry"]["coordinates"][:2]
            d = distance(x, y, ex, ey)
            if d > radius * 1.05:
                continue
            title = p.get("name") or label
            found[(title, round(ex, 4), round(ey, 4))] = dict(
                title=title,
                description=label,
                address=", ".join(v for v in (
                    " ".join(v for v in (p.get("street", ""), p.get("housenumber", "")) if v),
                    p.get("city", "")) if v),
                link="", phone="", poi_type=label,
                postcode=p.get("postcode", ""),
                distance=d, x=float(ex), y=float(ey))
    return list(found.values())


def nominatim_places(label, x, y, radius):
    """One Nominatim search for a type inside the radius; only places of that type."""
    word = NOMINATIM_WORDS.get(label)
    if not word:
        return []
    tag = PHOTON_TAGS[label][0].split(":")
    dlat = radius / 111320.0
    dlon = radius / (111320.0 * max(0.1, math.cos(math.radians(y))))
    url = NOMINATIM + "?" + urllib.parse.urlencode(
        {"q": word, "format": "jsonv2", "limit": 40, "bounded": 1, "addressdetails": 1,
         "viewbox": "%f,%f,%f,%f" % (x - dlon, y + dlat, x + dlon, y - dlat)})
    try:
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(req, timeout=PHOTON_TIMEOUT) as r:
            data = json.loads(netlimit.read_capped(r, netlimit.REPLY).decode("utf-8"))
    except Exception:
        return []
    out = []
    for p in data if isinstance(data, list) else []:
        if (p.get("category"), p.get("type")) != (tag[0], tag[1]):
            continue
        ex, ey = float(p["lon"]), float(p["lat"])
        d = distance(x, y, ex, ey)
        if d > radius * 1.05:
            continue
        a = p.get("address") or {}
        out.append(dict(
            title=p.get("name") or label,
            description=label,
            address=", ".join(v for v in (
                " ".join(v for v in (a.get("road", ""), a.get("house_number", "")) if v),
                a.get("city", a.get("town", ""))) if v),
            link="", phone="", poi_type=label,
            postcode=a.get("postcode", ""),
            distance=d, x=ex, y=ey))
    return out


def distance(x1, y1, x2, y2):
    r = 6371000.0
    p1, p2 = math.radians(y1), math.radians(y2)
    dp, dl = p2 - p1, math.radians(x2 - x1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def describe(tags, label):
    bits = [label]
    cuisine = tags.get("cuisine")
    if cuisine:
        bits.append(cuisine.replace(";", ", ").replace("_", " "))
    if tags.get("opening_hours"):
        bits.append(tags["opening_hours"])
    return ", ".join(bits)


def address(tags):
    street = tags.get("addr:street", "")
    number = tags.get("addr:housenumber", "")
    city = tags.get("addr:city", "")
    return ", ".join(p for p in (" ".join(p for p in (street, number) if p), city) if p)


def nearby(query_type, query_name, near, radius, params):
    """Places of a type near a point: online, or from the saved offline
    areas when the servers can't be reached."""
    x, y = prepare_point(near)

    def offline():
        found = poor.offline_search.nearby(query_type, query_name, x, y, int(radius),
                                           params.get("limit", 40))
        return (x, y, found) if found else None

    return poor.offline_search.fallback(
        lambda: nearby_online(query_type, query_name, near, radius, params), offline)


def nearby_online(query_type, query_name, near, radius, params):
    x, y = prepare_point(near)
    limit = params.get("limit", 40)
    label = query_type
    filters = TYPES.get(query_type)
    if not filters:
        # unknown type: treat the text as a name search, any named place
        filters = ['["name"]']
        query_name = (query_name + " " + query_type).strip()
        label = ""
    key = (tuple(filters), query_name, round(x, 3), round(y, 3), int(radius), limit)
    with _lock:
        if key in cache:
            return copy.deepcopy(cache[key])
    start = time.time()
    query = build_query(filters, query_name, x, y, int(radius), limit)

    def from_overpass():
        out = (x, y, overpass_results(overpass(query), x, y, label, limit))
        if out[2]:
            with _lock:
                cache[key] = copy.deepcopy(out)
                cache_source[key] = "overpass"
        return out

    def from_photon():
        results = photon_places(query_type, x, y, int(radius), query_name)
        if not results and not query_name:
            # Photon down or empty: one request to Nominatim
            results = nominatim_places(query_type, x, y, int(radius))
        results.sort(key=lambda r: r["distance"])
        out = (x, y, results[:limit])
        if out[2]:
            with _lock:
                if cache_source.get(key) != "overpass":
                    cache[key] = copy.deepcopy(out)
                    cache_source[key] = "photon"
        return out

    over = _pool.submit(from_overpass)
    phot = _pool.submit(from_photon) if query_type in PHOTON_TAGS else None
    try:
        return over.result(timeout=FAST)
    except Exception:
        pass
    if phot is not None:
        try:
            out = phot.result(timeout=max(0.1, DEADLINE - (time.time() - start)))
            if out[2]:
                return out
        except Exception:
            pass
    try:
        return over.result(timeout=max(0.1, DEADLINE - (time.time() - start)))
    except Exception:
        raise RuntimeError("Place servers are busy, try again in a minute")


def overpass_results(data, x, y, label, limit):
    results = []
    seen = set()
    for el in data.get("elements", []):
        tags = el.get("tags", {})
        ex = el.get("lon", el.get("center", {}).get("lon"))
        ey = el.get("lat", el.get("center", {}).get("lat"))
        if ex is None or ey is None:
            continue
        title = tags.get("name") or tags.get("brand") or tags.get("operator") or label or "Place"
        sig = (title, round(ex, 4), round(ey, 4))
        if sig in seen:
            continue
        seen.add(sig)
        results.append(dict(
            title=title,
            description=describe(tags, label),
            address=address(tags),
            link=tags.get("website", tags.get("contact:website", "")),
            phone=tags.get("phone", tags.get("contact:phone", "")),
            poi_type=label,
            postcode=tags.get("addr:postcode", ""),
            distance=distance(x, y, ex, ey),
            x=float(ex), y=float(ey)))
    results.sort(key=lambda r: r["distance"])
    return results[:limit]
