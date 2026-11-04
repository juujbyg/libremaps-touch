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
        "route": "#33ccff",
        "routeOpacity": 0.95,
        "itemFg": "#e6edf7",
        "itemBg": "#16212f",
        "shadowColor": "black",
        "accent": "#f4a81d",
        "hudBg": "#1f2430",
        "hudMuted": "#9fb2cc",
        "hudText": "#ffffff",
    },
    "day": {
        "fg": "#2b3445",
        "iconVariant": "",
        "maneuver": "white",
        "position": "",
        "positionUncertainty": "#e8a94a",
        "route": "#3366ff",
        "routeOpacity": 0.8,
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
    # drop building 3D-ish top layer opacity weirdness
    style["name"] = "Waze " + mode
    return style


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
