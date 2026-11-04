# -*- coding: utf-8 -*-
"""
Nearby places from OpenStreetMap through public Overpass servers.

No account, no API key. Outside services used: the Overpass servers below
(kumi.systems, maps.mail.ru, overpass-api.de) and, only when "near" is typed
as text, the app's own geocoder (Photon).
"""

import copy
import json
import math
import poor
import urllib.parse
import urllib.request

SERVERS = [
    "https://overpass.kumi.systems/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass-api.de/api/interpreter",
]
OVERPASS_TIMEOUT = 8      # seconds per server; public servers are often overloaded
PHOTON = "https://photon.komoot.io/api/"

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


def overpass(query):
    body = ("data=" + urllib.parse.quote(query)).encode()
    last = None
    for server in SERVERS:
        try:
            req = urllib.request.Request(
                server, data=body,
                headers={"User-Agent": USER_AGENT,
                         "Content-Type": "application/x-www-form-urlencoded"})
            with urllib.request.urlopen(req, timeout=OVERPASS_TIMEOUT) as r:
                return json.loads(r.read().decode("utf-8"))
        except Exception as error:
            last = error
    raise last


def photon_places(label, x, y, radius, name):
    """Places of one type through Photon, inside the radius, nearest first."""
    tag, words = PHOTON_TAGS[label]
    dlat = radius / 111320.0
    dlon = radius / (111320.0 * max(0.1, math.cos(math.radians(y))))
    bbox = "%f,%f,%f,%f" % (x - dlon, y - dlat, x + dlon, y + dlat)
    found = {}
    for word in ([name] if name else words):
        url = PHOTON + "?" + urllib.parse.urlencode(
            {"q": word, "bbox": bbox, "osm_tag": tag, "limit": 40, "lat": y, "lon": x})
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=15) as r:
                data = json.loads(r.read().decode("utf-8"))
        except Exception:
            continue
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
    if key in cache:
        return copy.deepcopy(cache[key])
    try:
        data = overpass(build_query(filters, query_name, x, y, int(radius), limit))
    except Exception:
        data = None
    if data is None:
        # every Overpass server failed or timed out
        if query_type in PHOTON_TAGS:
            results = photon_places(query_type, x, y, int(radius), query_name)
            results.sort(key=lambda r: r["distance"])
            results = results[:limit]
            if results:
                cache[key] = copy.deepcopy((x, y, results))
            return x, y, results
        raise RuntimeError("Place servers are busy, try again in a minute")
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
    results = results[:limit]
    if results:
        cache[key] = copy.deepcopy((x, y, results))
    return x, y, results
