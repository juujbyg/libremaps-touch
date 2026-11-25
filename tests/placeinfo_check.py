"""Checks for the place sheet's opening hours and fuel station matching.

Run from the maps folder:  python3 -I tests/placeinfo_check.py
No network: the province file is written into a temporary cache first.
"""
import datetime, json, os, sys, tempfile, time, types

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.join(os.path.dirname(HERE), "overlay", "share", "pure-maps.jonnius")
sys.path.insert(0, PKG)
poor = types.ModuleType("poor"); poor.__path__ = [os.path.join(PKG, "poor")]
poor.CACHE_HOME_DIR = tempfile.mkdtemp()
sys.modules["poor"] = poor
from poor import placeinfo as pi  # noqa: E402

failures = 0


def check(name, got, want):
    global failures
    ok = got == want
    failures += not ok
    print("ok  " if ok else "FAIL", name, "" if ok else "-> got %r, want %r" % (got, want))


# Wednesday 19 Nov 2026
def at(h, m, day=19):
    return datetime.datetime(2026, 11, day, h, m)


wk = pi.parse_es_hours("L-D: 24H")
check("es 24h", pi.status(wk, at(3, 0)), {"state": "always", "time": "", "day": -1})
wk = pi.parse_es_hours("L-V: 06:00-22:00; S-D: 07:00-22:00")
check("es open", pi.status(wk, at(12, 0)), {"state": "open", "time": "22:00", "day": -1})
check("es closed tonight", pi.status(wk, at(23, 0)), {"state": "closed", "time": "06:00", "day": -2})
check("es closed early", pi.status(wk, at(5, 0)), {"state": "closed", "time": "06:00", "day": -1})
check("es friday night to saturday", pi.status(wk, at(23, 0, 20)), {"state": "closed", "time": "07:00", "day": -2})
wk = pi.parse_es_hours("L-D: 06:00-00:00")
check("es until midnight", pi.status(wk, at(23, 30)), {"state": "open", "time": "00:00", "day": -1})
check("es comma garbage", pi.parse_es_hours("Consultar"), None)

wk = pi.parse_osm_hours("Mo-Fr 08:00-14:00,16:00-20:00; Sa 09:00-14:00; Su off")
check("osm lunch break", pi.status(wk, at(15, 0)), {"state": "closed", "time": "16:00", "day": -1})
check("osm open", pi.status(wk, at(9, 0)), {"state": "open", "time": "14:00", "day": -1})
check("osm saturday to monday", pi.status(wk, at(15, 0, 21)), {"state": "closed", "time": "08:00", "day": 0})
check("osm 24/7", pi.status(pi.parse_osm_hours("24/7"), at(1, 0)), {"state": "always", "time": "", "day": -1})
wk = pi.parse_osm_hours("Mo-Su 20:00-02:00")
check("osm past midnight", pi.status(wk, at(1, 0)), {"state": "open", "time": "02:00", "day": -1})
check("osm PH ignored", pi.parse_osm_hours("Mo-Fr 09:00-17:00; PH off") is not None, True)
check("osm fancy refused", pi.parse_osm_hours("Mo-Fr 09:00-17:00; Jan-Mar Sa 10:00-12:00"), None)
check("osm wrap days", pi.parse_osm_hours("Fr-Mo 10:00-12:00")[6], [(600, 720)])

check("spain", pi.in_spain(40.4169, -3.7035), True)
check("canaries", pi.in_spain(28.12, -15.43), True)
check("not spain", pi.in_spain(48.85, 2.35), False)
check("province from postcode", pi._province_guess(40.4, -3.7, "28050"), ["28"])
check("province guess", pi._province_guess(41.39, 2.17, "")[0], "08")

# a fake Madrid province file, as the cache would hold it
cache = {"stations": [
    [40.4170, -3.7036, "REPSOL", "L-D: 24H", [["Diesel", "1.935"], ["95", "1.719"]], "19/11 00:42"],
    [40.4300, -3.7036, "SHELL", "L-V: 06:00-22:00", [["Diesel", "1.899"]], "19/11 00:42"]]}
with open(os.path.join(poor.CACHE_HOME_DIR, "fuel-es-28.json"), "w", encoding="utf-8") as f:
    json.dump(cache, f)
st = pi.fuel_station(40.4169, -3.7035, "Repsol", "28013", "Fuel station")
check("station matched", st and st["prices"], [["Diesel", "1.935"], ["95", "1.719"]])
check("source and unit", st and (st["source"], st["unit"], st["date"]), ("MITECO", "€/L", "19/11 00:42"))
check("not a fuel place", pi.fuel_station(40.4169, -3.7035, "Bar", "28013", "Bar or pub"), None)
check("too far", pi.fuel_station(40.4230, -3.7035, "Repsol", "28013", "Fuel station"), None)

# prices go out before the slow OpenStreetMap lookup for opening hours
from poor import fuelprices  # noqa: E402
fuelprices.station = lambda lat, lon, postcode="": {"country": "fr", "brand": "", "hours": "",
    "prices": [["Diesel", "1.759"]], "date": "24/11 08:15", "source": "prix-carburants.gouv.fr", "unit": "EUR/L"}
order = []
pi.osm_tags = lambda lat, lon, title: order.append("osm") or {"opening_hours": "24/7"}
res = pi.lookup(2.3523, 48.8567, "Total", "Fuel", "", early=lambda r: order.append(("early", r["fuel"])))
check("early prices before hours", order, [("early", [{"name": "Diesel", "price": "1.759"}]), "osm"])
check("final reply has both", (res["fuel_source"], res["hours"] is not None), ("prix-carburants.gouv.fr", True))

print("all passed" if not failures else "%d failed" % failures)
sys.exit(1 if failures else 0)
