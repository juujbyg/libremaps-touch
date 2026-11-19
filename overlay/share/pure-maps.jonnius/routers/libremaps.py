# -*- coding: utf-8 -*-

# Copyright (C) 2018 Rinigus (Pure Maps), LibreMaps changes 2026 juujbyg
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

"""
LibreMaps router: one place to choose how you travel.

 * walk, bike, car, motor scooter, taxi, bus lane: Valhalla run by FOSSGIS
   (https://valhalla.openstreetmap.de/), no key.
 * public transport (bus, metro, tram, train): Transitous
   (https://transitous.org/), a community service built on open timetables.
   Coverage depends on the city, e.g. Madrid has buses and Cercanias but the
   Metro de Madrid timetable is not in it (yet).

Only the start and end points of the trip are sent to those servers.
"""

import copy
import datetime
import json
import poor
import urllib.parse

CONF_DEFAULTS = {
    "mode": "auto",                  # auto, motor_scooter, taxi, bus, bicycle, pedestrian, transit
    "transit_modes": "all",          # all, bus, subway, tram, rail
    "language": poor.util.get_default_language("en"),
    "use_highways": 1.0,
    "use_tolls": 0.5,
}

VALHALLA = "https://valhalla1.openstreetmap.de/route"
TRANSITOUS = "https://api.transitous.org/api/v5/plan"
USER_AGENT = "LibreMaps/0.1 (open source Ubuntu Touch maps; https://github.com/juujbyg)"

TRANSIT_FILTER = {
    "all": None,
    "bus": "BUS",
    "subway": "SUBWAY",
    "tram": "TRAM",
    "rail": "RAIL",
}

MODE = {
    "auto": "car",
    "motor_scooter": "car",
    "taxi": "car",
    "bus": "car",
    "bicycle": "bicycle",
    "pedestrian": "foot",
    "transit": "transit",
}

ICONS = {
     0: "flag", 1: "depart", 2: "depart-right", 3: "depart-left", 4: "arrive",
     5: "arrive-right", 6: "arrive-left", 7: "continue", 8: "continue",
     9: "turn-slight-right", 10: "turn-right", 11: "turn-sharp-right",
    12: "uturn", 13: "uturn", 14: "turn-sharp-left", 15: "turn-left",
    16: "turn-slight-left", 17: "continue", 18: "off-ramp-slight-right",
    19: "off-ramp-slight-left", 20: "off-ramp-slight-right",
    21: "off-ramp-slight-left", 22: "fork-straight", 23: "fork-slight-right",
    24: "fork-slight-left", 25: "merge-slight-left", 26: "roundabout",
    27: "off-ramp-slight-right", 28: "ferry", 29: "depart",
}

# Transitous walking steps
STEP_ICONS = {
    "DEPART": "depart", "CONTINUE": "continue", "LEFT": "turn-left", "RIGHT": "turn-right",
    "SLIGHTLY_LEFT": "turn-slight-left", "SLIGHTLY_RIGHT": "turn-slight-right",
    "HARD_LEFT": "turn-sharp-left", "HARD_RIGHT": "turn-sharp-right",
    "UTURN_LEFT": "uturn", "UTURN_RIGHT": "uturn",
    "CIRCLE_CLOCKWISE": "roundabout", "CIRCLE_COUNTERCLOCKWISE": "roundabout",
}
STEP_TEXT = {
    "DEPART": "Head out", "CONTINUE": "Continue", "LEFT": "Turn left",
    "RIGHT": "Turn right", "SLIGHTLY_LEFT": "Bear left", "SLIGHTLY_RIGHT": "Bear right",
    "HARD_LEFT": "Turn sharp left", "HARD_RIGHT": "Turn sharp right",
    "UTURN_LEFT": "Make a U-turn", "UTURN_RIGHT": "Make a U-turn",
    "CIRCLE_CLOCKWISE": "Take the roundabout", "CIRCLE_COUNTERCLOCKWISE": "Take the roundabout",
    "ELEVATOR": "Take the elevator", "STAIRS": "Take the stairs", "ESCALATOR": "Take the escalator",
    "ENTER_STATION": "Enter the station", "EXIT_STATION": "Exit the station",
    "FOLLOW_SIGNS": "Follow the signs",
}

TRANSIT_NAME = {
    "BUS": "bus", "SUBWAY": "metro", "TRAM": "tram", "REGIONAL_RAIL": "train",
    "RAIL": "train", "HIGHSPEED_RAIL": "train", "LONG_DISTANCE": "train",
    "NIGHT_RAIL": "train", "FERRY": "ferry", "METRO": "metro", "COACH": "coach",
    "SUBURBAN": "train", "FUNICULAR": "funicular", "CABLE_CAR": "cable car",
}

cache = {}


def prepare_point(point):
    """Return `point` as a dict with lat, lon, and optional name."""
    if isinstance(point, (list, tuple)):
        return dict(lat=point[1], lon=point[0])
    if isinstance(point, dict):
        d = dict(lat=point["y"], lon=point["x"])
        if "text" in point:
            d["name"] = point["text"]
        if "destination" in point and not point["destination"]:
            d["type"] = "break_through"
        else:
            d["type"] = "break"
        return d
    geocoder = poor.Geocoder("default")
    results = geocoder.geocode(point, params=dict(limit=1))
    return prepare_point((results[0]["x"], results[0]["y"]))


def route(locations, params):
    """Find route and return its properties as a dictionary."""
    mode = poor.conf.routers.libremaps.mode
    if mode == "transit":
        return route_transit(locations, params)
    # Valhalla, or the saved offline areas when it can't be reached
    return poor.offline_search.fallback(
        lambda: route_valhalla(locations, params, mode),
        lambda: route_offline(locations, mode),
        wait=8.0)


def route_offline(locations, costing):
    """A route over the roads of the saved offline areas, or None."""
    pts = [prepare_point(p) for p in locations]
    pts = [(p["lon"], p["lat"]) for p in pts]
    if not all(poor.offline_route.covers(x, y) for x, y in pts):
        return None
    try:
        out = poor.offline_route.route(pts, costing, tr=poor.i18n._)
    except poor.offline_route.NoRoute:
        return None
    seconds, meters = out.pop("seconds"), out.pop("meters")
    out["locations"] = list(locations)
    out["language"] = poor.util.get_default_language("en")
    out["summary"] = dict(seconds=seconds, meters=meters,
                          time=poor.util.format_time(seconds),
                          distance=poor.util.format_distance(meters),
                          via=main_roads(out["maneuvers"]))
    return out


# ---------------------------------------------------------------- Valhalla

def parse_exit(maneuver, key):
    if "sign" not in maneuver or key not in maneuver["sign"]:
        return None
    return [i.get("text", "") for i in maneuver["sign"][key]]


def route_valhalla(locations, params, costing):
    loc = list(map(prepare_point, locations))
    heading = params.get("heading", None)
    if heading is not None:
        loc[0]["heading"] = heading
    conf = poor.conf.routers.libremaps
    units = "kilometers" if poor.conf.units == "metric" else "miles"
    options = {}
    if costing in ("auto", "taxi", "bus", "motor_scooter"):
        options = {"use_highways": conf.use_highways, "use_tolls": conf.use_tolls}
    request = dict(locations=loc, costing=costing,
                   costing_options={costing: options},
                   directions_options=dict(language=conf.language, units=units))
    # Other ways there when the user is choosing a route (not when rerouting
    # mid-trip): Valhalla's "alternates", shown grey on the map to pick from
    want_alternatives = bool(params.get("alternatives", False)) and len(loc) == 2
    if want_alternatives:
        request["alternates"] = 2
    body = json.dumps(request)
    key = VALHALLA + "_" + body
    with poor.util.silent(KeyError):
        return copy.deepcopy(cache[key])
    result = poor.AttrDict(poor.http.post_json(
        VALHALLA, body=body, headers={"Content-Type": "application/json",
                                      "User-Agent": USER_AGENT}))
    out = parse_trip(result.trip, locations, costing)
    if want_alternatives:
        routes = [out]
        for alt in result.get("alternates", None) or []:
            try:
                r = parse_trip(poor.AttrDict(alt).trip, locations, costing)
            except Exception:
                continue
            if r["x"]:
                routes.append(r)
        out = routes if len(routes) > 1 else out
    if (out[0] if isinstance(out, list) else out)["x"]:
        cache[key] = copy.deepcopy(out)
    return out


def parse_trip(trip, locations, costing):
    X, Y, Man, ind = [], [], [], [0]
    for leg in trip.legs:
        x, y = poor.util.decode_epl(leg.shape, precision=6)
        Man.extend([dict(
            x=float(x[m.begin_shape_index]),
            y=float(y[m.begin_shape_index]),
            icon=ICONS.get(m.type, "flag"),
            narrative=m.instruction,
            sign=dict(exit_branch=parse_exit(m, "exit_branch_elements"),
                      exit_name=parse_exit(m, "exit_name_elements"),
                      exit_number=parse_exit(m, "exit_number_elements"),
                      exit_toward=parse_exit(m, "exit_toward_elements")),
            street=m.get("begin_street_names", m.get("street_names", None)),
            arrive_instruction=m.get("arrive_instruction", None),
            depart_instruction=m.get("depart_instruction", None),
            roundabout_exit_count=m.get("roundabout_exit_count", None),
            travel_type=m.get("travel_type", None),
            verbal_alert=m.get("verbal_transition_alert_instruction", None),
            verbal_pre=m.get("verbal_pre_transition_instruction", None),
            verbal_post=m.get("verbal_post_transition_instruction", None),
            duration=float(m.time),
        ) for m in leg.maneuvers])
        X.extend(x)
        Y.extend(y)
        ind.append(len(X) - 1)
    summary = trip.get("summary", None) or {}
    seconds = float(summary.get("time", 0) or 0)
    meters = float(summary.get("length", 0) or 0) * (1000 if poor.conf.units == "metric" else 1609.344)
    out = dict(x=X, y=Y,
               locations=[locations[i.original_index] for i in trip.locations],
               location_indexes=ind, maneuvers=Man, mode=MODE.get(costing, "car"),
               optimized=False,
               # for the route chooser: total time and length, and the main roads
               summary=dict(seconds=seconds, meters=meters,
                            time=poor.util.format_time(seconds),
                            distance=poor.util.format_distance(meters),
                            via=main_roads(Man)))
    out["language"] = trip.language.replace("-", "_")
    return out


def main_roads(maneuvers):
    """The named road the route follows longest, to tell alternatives apart ("via A-6")."""
    best, best_time = "", 0.0
    for m in maneuvers:
        names = m.get("street") or []
        if names and m["duration"] > best_time:
            best, best_time = names[0], m["duration"]
    return best


# --------------------------------------------------------------- Transitous

def clock(iso):
    """Local HH:MM from an ISO timestamp."""
    try:
        t = datetime.datetime.fromisoformat(iso.replace("Z", "+00:00"))
        return t.astimezone().strftime("%H:%M")
    except Exception:
        return ""


def route_transit(locations, params):
    start, end = prepare_point(locations[0]), prepare_point(locations[-1])
    q = {"fromPlace": "%.6f,%.6f" % (start["lat"], start["lon"]),
         "toPlace": "%.6f,%.6f" % (end["lat"], end["lon"]),
         "numItineraries": 3}
    flt = TRANSIT_FILTER.get(poor.conf.routers.libremaps.transit_modes)
    if flt:
        q["transitModes"] = flt
    url = TRANSITOUS + "?" + urllib.parse.urlencode(q)
    result = poor.http.get_json(url, headers={"User-Agent": USER_AGENT})
    its = result.get("itineraries") or []
    if not its:
        return dict(error=True, message="No public transport connection found here. "
                    "Transit data may be missing for this city or mode.")
    it = its[0]
    X, Y, Man = [], [], []
    for leg in it["legs"]:
        lx, ly = poor.util.decode_epl(leg["legGeometry"]["points"],
                                      precision=leg["legGeometry"].get("precision", 6))
        first = len(X)
        X.extend(lx)
        Y.extend(ly)
        if leg["mode"] in ("WALK", "BIKE", "CAR"):
            first_step = True
            for s in leg.get("steps") or []:
                sx, sy = poor.util.decode_epl(s["polyline"]["points"],
                                              precision=s["polyline"].get("precision", 6))
                if not sx:
                    continue
                d = s.get("relativeDirection", "CONTINUE")
                text = STEP_TEXT.get(d, "Continue")
                street = s.get("streetName") or ""
                if street:
                    text += " onto " + street if d not in ("CONTINUE", "DEPART") else " along " + street
                if first_step:
                    text = "Walk to %s" % (leg["to"].get("name") or "your destination")
                    first_step = False
                Man.append(dict(x=float(sx[0]), y=float(sy[0]),
                                icon=STEP_ICONS.get(d, "continue"), narrative=text,
                                street=street or None,
                                duration=float(s.get("distance", 0)) / 1.3,
                                travel_type="pedestrian"))
            if not leg.get("steps") and lx:
                Man.append(dict(x=float(lx[0]), y=float(ly[0]), icon="continue",
                                narrative="Walk to %s" % leg["to"].get("name", "the destination"),
                                duration=float(leg.get("duration", 0)), travel_type="pedestrian"))
        else:
            kind = TRANSIT_NAME.get(leg["mode"], "transit")
            line = leg.get("displayName") or leg.get("routeShortName") or ""
            head = leg.get("headsign") or ""
            text = "Take %s %s" % (kind, line)
            if head:
                text += " toward " + head
            text += " from %s at %s" % (leg["from"].get("name", ""), clock(leg.get("startTime", "")))
            Man.append(dict(x=float(lx[0]), y=float(ly[0]), icon="depart", narrative=text,
                            street=line or None, duration=float(leg.get("duration", 0)),
                            travel_type="transit"))
            Man.append(dict(x=float(lx[-1]), y=float(ly[-1]), icon="arrive",
                            narrative="Get off at %s" % leg["to"].get("name", ""),
                            street=None, duration=0.0, travel_type="transit"))
    if not X:
        return dict(error=True, message="No route geometry returned.")
    Man.append(dict(x=float(X[-1]), y=float(Y[-1]), icon="arrive",
                    narrative="Arrive at your destination", duration=0.0))
    out = dict(x=X, y=Y, locations=[locations[0], locations[-1]],
               location_indexes=[0, len(X) - 1], maneuvers=Man, mode="transit",
               optimized=False, language="en_US")
    return out
