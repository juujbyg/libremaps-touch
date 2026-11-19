#!/usr/bin/env python3
"""Generate Waze-like night and day map definitions for Pure Maps.

Base: OpenFreeMap "bright" vector style (OpenMapTiles schema, no API key).
Output: JSON files for Pure Maps' maps/ directory with the style embedded
(style_json) plus style_gui so the navigation UI is themed to match.
"""
import copy
import json

BASE = "styles/bright.json"

PALETTES = {
    "night": {
        "background": "#16212f",
        "water": "#0c1623",
        "waterway": "#0c1623",
        "park": "#183428",
        "wood": "#173226",
        "grass": "#183428",
        "sand": "#2b2a24",
        "landuse": "#1b2a3a",
        "landuse_commercial": "#1f2a3d",
        "landuse_industrial": "#222b38",
        "cemetery": "#1a2f2a",
        "hospital": "#2b2230",
        "school": "#222a3d",
        "building": "#243449",
        "building_outline": "#2d4160",
        "aeroway": "#2a3a50",
        "road_minor": "#4a5d78",
        "road_minor_casing": "#101a27",
        "road_major": "#7b92b3",
        "road_major_casing": "#101a27",
        "motorway": "#e8a94a",
        "motorway_casing": "#4a3414",
        "path": "#3a4b63",
        "railway": "#3a4659",
        "boundary": "#3d4f6b",
        "label": "#e6edf7",
        "label_halo": "#0f1823",
        "label_minor": "#a9b8cf",
        "label_water": "#6aa3d9",
        "secondary": "#7b92b3", "secondary_casing": "#101a27",
        "primary": "#7b92b3", "primary_casing": "#101a27",
        "trunk": "#e8a94a", "trunk_casing": "#4a3414",
    },
    "day": {  # openstreetmap.org standard map colours
        "background": "#f2efe9",
        "water": "#aad3df",
        "waterway": "#aad3df",
        "park": "#c8facc",
        "wood": "#add19e",
        "grass": "#cdebb0",
        "sand": "#f5e9c6",
        "landuse": "#e0dfdf",
        "landuse_commercial": "#f2dad9",
        "landuse_industrial": "#ebdbe8",
        "cemetery": "#aacbaf",
        "hospital": "#f4e4d4",
        "school": "#f0f0d8",
        "building": "#d9d0c9",
        "building_outline": "#c4b6ab",
        "aeroway": "#dadae0",
        "road_minor": "#ffffff",
        "road_minor_casing": "#bbbbbb",
        "road_major": "#f7fabf",
        "road_major_casing": "#b2b45c",
        "secondary": "#f7fabf",
        "secondary_casing": "#b2b45c",
        "primary": "#fcd6a4",
        "primary_casing": "#b8854e",
        "trunk": "#f9b29c",
        "trunk_casing": "#c1634b",
        "motorway": "#e892a2",
        "motorway_casing": "#c2506f",
        "path": "#f08070",
        "railway": "#8a8a8a",
        "boundary": "#ac46ac",
        "label": "#222222",
        "label_halo": "#ffffff",
        "label_minor": "#444444",
        "label_water": "#4d80b3",
    },
}

GUI = {
    "night": {
        "fg": "#e6edf7",
        "iconVariant": "white",
        "maneuver": "#0b1320",
        "position": "white",
        "positionUncertainty": "#e8a94a",
        "route": "#a78bfa",
        "routeCasing": "#2e1065",
        "routeOpacity": 1.0,
        "itemFg": "#fafafa",
        "itemBg": "#18181b",
        "shadowColor": "black",
        "accent": "#f4a81d",
        "hudBg": "#18181b",
        "hudMuted": "#a1a1aa",
        "hudText": "#fafafa",
        "dark": True,
    },
    "day": {
        "fg": "#2b3445",
        "iconVariant": "",
        "maneuver": "white",
        "position": "",
        "positionUncertainty": "#e8a94a",
        "route": "#7c4dff",
        "routeCasing": "#4c1d95",
        "routeOpacity": 1.0,
        "itemFg": "#2b3445",
        "itemBg": "#ffffff",
        "accent": "#f4a81d",
        "hudBg": "#ffffff",
        "hudMuted": "#5b6270",
        "hudText": "#1f2430",
    },
}


def classify(layer):
    """Return the palette role for a layer's main colour, or None."""
    r = classify_base(layer)
    i = layer["id"]
    if layer.get("source-layer") == "transportation" and layer["type"] == "line" \
            and r in ("motorway", "motorway_casing", "road_major", "road_major_casing"):
        casing = "_casing" if i.endswith("casing") else ""
        if "trunk-primary" in i:
            return "primary" + casing   # trunk and primary share a layer; trunk is rare in cities
        if "trunk" in i:
            return "trunk" + casing
        if "primary" in i:
            return "primary" + casing
        if "secondary" in i:
            return "secondary" + casing
        if "motorway" in i:
            return "motorway" + casing
    return r


def classify_base(layer):
    i = layer["id"]
    t = layer["type"]
    sl = layer.get("source-layer")
    if t == "background":
        return "background"
    if t == "symbol":
        if i.startswith("waterway") or i.startswith("water_name"):
            return "label_water"
        if i.startswith("highway-name") or i.startswith("poi"):
            return "label_minor"
        return "label"
    if sl == "water" or i == "water" or i.startswith("water-"):
        return "water"
    if sl == "waterway" or i.startswith("waterway"):
        return "waterway"
    if i in ("park", "landcover-grass-park", "landcover-grass"):
        return "park"
    if i == "landcover-wood":
        return "wood"
    if i == "landcover-sand":
        return "sand"
    if i.startswith("landcover"):
        return "landuse"
    if i == "landuse-commercial":
        return "landuse_commercial"
    if i == "landuse-industrial":
        return "landuse_industrial"
    if i == "landuse-cemetery":
        return "cemetery"
    if i == "landuse-hospital":
        return "hospital"
    if i == "landuse-school":
        return "school"
    if i.startswith("landuse"):
        return "landuse"
    if i.startswith("building"):
        return "building"
    if sl == "aeroway":
        return "aeroway"
    if sl == "boundary":
        return "boundary"
    if "railway" in i or i.startswith("cablecar"):
        return "railway"
    if "path" in i or "pier" in i or "highway-area" in i:
        return "path"
    if sl == "transportation":
        casing = i.endswith("casing")
        if "motorway" in i or "trunk" in i:
            return "motorway_casing" if casing else "motorway"
        if "primary" in i or "secondary" in i or "link" in i:
            return "road_major_casing" if casing else "road_major"
        return "road_minor_casing" if casing else "road_minor"
    if i == "ferry":
        return "label_water"
    return None


def fix_typography(layer, role):
    """Readable labels on a phone: upright faces, bolder places, larger text."""
    lay = layer.setdefault("layout", {})
    fonts = lay.get("text-font")
    if fonts:
        def swap(f):
            return "Noto Sans Regular" if f == "Noto Sans Italic" else f
        if isinstance(fonts, list) and fonts and fonts[0] == "literal":
            fonts = ["literal", [swap(f) for f in fonts[1]]]
        elif isinstance(fonts, list) and all(isinstance(f, str) for f in fonts):
            fonts = [swap(f) for f in fonts]
        lay["text-font"] = fonts
    i = layer["id"]
    if i.startswith(("label_city", "label_town", "label_state", "label_country")):
        lay["text-font"] = ["Noto Sans Bold"]
    if "text-size" in lay:
        k = 1.4 if i.startswith(("highway-shield", "road_shield")) else 1.2
        lay["text-size"] = scale_width(lay["text-size"], k)
    lay.pop("text-letter-spacing", None)


def scale_width(w, k):
    """Scale a width; zoom expressions must stay top-level, so scale the stops."""
    if isinstance(w, (int, float)):
        return w * k
    if isinstance(w, list) and w:
        if w[0] == "interpolate":
            # ["interpolate", type, input, z1, v1, z2, v2, ...]
            return w[:3] + [x if i % 2 == 0 else scale_width(x, k)
                            for i, x in enumerate(w[3:])]
        if w[0] == "step":
            # ["step", input, v0, z1, v1, ...]
            return w[:2] + [scale_width(w[2], k)] + [
                x if i % 2 == 0 else scale_width(x, k) for i, x in enumerate(w[3:])]
        return ["*", k, w]
    return w


def build(mode):
    pal = PALETTES[mode]
    style = json.load(open(BASE))
    style = copy.deepcopy(style)
    for layer in style["layers"]:
        role = classify(layer)
        paint = layer.setdefault("paint", {})
        if layer["type"] == "symbol":
            fix_typography(layer, role)
            if layer["id"].startswith(("highway-shield", "road_shield", "road_oneway")):
                role = None  # keep the stock shield artwork, no halo smudge
        if role:
            col = pal[role]
            for prop in ("background-color", "fill-color", "line-color", "text-color"):
                if prop in paint:
                    paint[prop] = col
            if "fill-outline-color" in paint:
                paint["fill-outline-color"] = pal.get("building_outline", col)
            if layer["type"] == "symbol":
                paint["text-halo-color"] = pal["label_halo"]
                paint["text-halo-width"] = 2.0 if mode == "night" else 1.5
                paint["text-halo-blur"] = 0.6
            if layer["type"] in ("fill",) and "fill-opacity" in paint and role not in ("building",):
                paint["fill-opacity"] = 1
            if layer["type"] == "fill" and role.startswith("landuse"):
                paint["fill-opacity"] = 0.9
        # chunkier roads, the Waze signature
        if layer["type"] == "line" and layer.get("source-layer") == "transportation" \
                and role in ("road_minor", "road_minor_casing", "road_major", "road_major_casing",
                             "motorway", "motorway_casing"):
            if "line-width" in paint and mode == "night":
                paint["line-width"] = scale_width(paint["line-width"], 1.3)
            if "line-opacity" in paint:
                paint["line-opacity"] = 1
        # opaque casings at night so roads read on the dark base
        if mode == "night" and layer["type"] == "line" and role == "road_minor":
            paint["line-opacity"] = 1
    for layer in style["layers"]:
        if layer["id"].startswith("poi_"):
            layer["minzoom"] = max(layer.get("minzoom", 0), 16.5)
    add_osm_detail(style, mode)
    style["name"] = "Waze " + mode
    return style


# Countryside detail in openstreetmap.org's colours (day) and quiet night
# equivalents. OpenMapTiles has these classes from zoom 9, but Bright draws
# only wood and grass, which left farmland regions blank.
RURAL = {
    "day": {"farmland": "#eef0d5", "orchard": "#aedfa3", "vineyard": "#aedfa3",
            "meadow": "#cdebb0", "grassland": "#cdebb0", "grass": "#cdebb0",
            "scrub": "#c8d7ab", "heath": "#d6d99f", "wetland": "#d6e5c9",
            "rock": "#eee5dc", "allotments": "#c9e1bf"},
    "night": {"farmland": "#1a2634", "orchard": "#173026", "vineyard": "#173026",
              "meadow": "#183428", "grassland": "#183428", "grass": "#183428",
              "scrub": "#1a3027", "heath": "#222c25", "wetland": "#1a2c30",
              "rock": "#262a30", "allotments": "#183428"},
}
TRACK = {"day": "#996600", "night": "#7d6b52"}
MUNICIPAL = {"day": "#c7a3c7", "night": "#34445c"}


def zoom_curve(*stops, kind=("exponential", 1.2)):
    return ["interpolate", list(kind), ["zoom"]] + [v for s in stops for v in s]


def add_osm_detail(style, mode):
    layers = style["layers"]
    ids = [l["id"] for l in layers]
    rural = RURAL[mode]
    colour = ["match", ["get", "subclass"]]
    for sub in ("orchard", "vineyard", "meadow", "grassland", "scrub", "heath", "allotments"):
        colour += [sub, rural[sub]]
    colour += [["match", ["get", "class"],
                "farmland", rural["farmland"], "wetland", rural["wetland"],
                "rock", rural["rock"], rural["grass"]]]
    # under the town landuse, so fields never cover streets' blocks
    layers.insert(ids.index("landcover-glacier") + 1, {
        "id": "landcover-rural", "type": "fill", "source": "openmaptiles",
        "source-layer": "landcover",
        "filter": ["match", ["get", "class"], ["farmland", "grass", "wetland", "rock"], True, False],
        "paint": {"fill-color": colour, "fill-opacity": 1, "fill-antialias": False}})
    layers[:] = [l for l in layers if l["id"] != "landcover-grass"]
    by_id = {l["id"]: l for l in layers}

    # minor roads from zoom 12 (where the tiles start carrying them): a thin
    # grey line first, white with a casing from 13.5, as on openstreetmap.org
    minor_only = ["match", ["get", "class"], ["minor", "service"], True, False]
    for i in ("highway-minor", "highway-minor-casing"):
        f = by_id[i]["filter"]
        by_id[i]["filter"] = [x if not (isinstance(x, list) and x[:2] == ["match", ["get", "class"]]
                                        and "track" in x[2]) else minor_only for x in f]
    m = by_id["highway-minor"]["paint"]
    m["line-width"] = zoom_curve((11.8, 0), (12, 0.8), (13.5, 1.6), (14, 2.5), (20, 11.5))
    if mode == "day":
        m["line-color"] = ["interpolate", ["linear"], ["zoom"], 13, "#b5b5b5", 13.6, "#ffffff"]
    by_id["highway-minor-casing"]["paint"]["line-opacity"] = ["interpolate", ["linear"], ["zoom"], 13.3, 0, 13.8, 1]

    # tracks: brown dashes
    layers.insert([l["id"] for l in layers].index("highway-path") + 1, {
        "id": "highway-track", "type": "line", "source": "openmaptiles",
        "source-layer": "transportation", "minzoom": 12,
        "filter": ["all", ["==", ["get", "class"], "track"], ["!=", ["get", "brunnel"], "tunnel"]],
        "layout": {"line-join": "round"},
        "paint": {"line-color": TRACK[mode], "line-opacity": 0.85,
                  "line-dasharray": [3, 1.5],
                  "line-width": zoom_curve((12, 0.7), (14, 1.2), (16, 2), (20, 4))}})

    # streams from zoom 12
    for i in ("waterway-stream-canal", "waterway-stream-canal-intermittent"):
        by_id[i]["paint"]["line-width"] = zoom_curve((12, 0.5), (14, 1), (20, 6), kind=("exponential", 1.3))

    # municipal boundaries, faint dashes
    layers.insert([l["id"] for l in layers].index("boundary_3"), {
        "id": "boundary_8", "type": "line", "source": "openmaptiles",
        "source-layer": "boundary", "minzoom": 10,
        "filter": ["all", ["==", ["typeof", ["get", "admin_level"]], "number"],
                   [">=", ["get", "admin_level"], 7], ["<=", ["get", "admin_level"], 8],
                   ["!=", ["get", "maritime"], 1]],
        "layout": {"line-join": "round"},
        "paint": {"line-color": MUNICIPAL[mode], "line-dasharray": [3, 2],
                  "line-width": zoom_curve((10, 0.6), (14, 1.2), kind=("linear",))}})


def meta(mode, style):
    return {
        "attribution": {
            "© OpenFreeMap": "https://openfreemap.org/",
            "© OpenMapTiles": "https://www.openmaptiles.org/",
            "© OpenStreetMap contributors": "https://www.openstreetmap.org/copyright",
        },
        "first_label_layer": "waterway_line_label",
        "format": "mapbox-gl",
        "light": mode,
        "name": ("Drive " + mode.capitalize()) if mode == "night" else "Drive Day (OpenStreetMap look)",
        "profiles": ["mixed", "online"],
        "provider": "Drive",
        "style_gui": GUI[mode],
        "style_json": style,
        "type": "default",
        "vehicle": "car",
    }


if __name__ == "__main__":
    for mode in ("night", "day"):
        out = "build/drive_%s.json" % mode
        json.dump(meta(mode, build(mode)), open(out, "w"), separators=(",", ":"))
        print("wrote", out)
