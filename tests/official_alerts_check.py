"""Checks for the official traffic incident readers (Spain's DGT, France's Bison Fute, Germany's
Autobahn API), with no network.

Run from the maps folder:  python3 -I tests/official_alerts_check.py
"""
import io, json, os, sys, time, types

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.join(os.path.dirname(HERE), "overlay", "share", "pure-maps.jonnius")
sys.path.insert(0, PKG)
sys.modules["pyotherside"] = types.SimpleNamespace(send=lambda *a: None)
poor = types.ModuleType("poor"); poor.__path__ = [os.path.join(PKG, "poor")]
poor.CACHE_HOME_DIR = "/nonexistent"
sys.modules["poor"] = poor
from poor import alerts  # noqa: E402

failures = 0


def check(name, got, want):
    global failures
    ok = got == want
    failures += not ok
    print("ok  " if ok else "FAIL", name, "" if ok else "-> got %r, want %r" % (got, want))


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%S+00:00", time.gmtime(t))


now = time.time()

# ---- France: DATEX II v2, as Bison Fute publishes it
def fr_record(rid, rtype, inner, start, end=None, status="definedByValidityTimeSpec", lat=45.0, lon=4.8):
    endtag = "<ns2:overallEndTime>%s</ns2:overallEndTime>" % iso(end) if end else ""
    return ('<ns2:situationRecord xsi:type="ns2:%s" id="%s"><ns2:validity><ns2:validityStatus>%s</ns2:validityStatus>'
            '<ns2:validityTimeSpecification><ns2:overallStartTime>%s</ns2:overallStartTime>%s</ns2:validityTimeSpecification>'
            '</ns2:validity>%s<ns2:groupOfLocations xsi:type="ns2:Point"><ns2:tpegPointLocation><ns2:point>'
            '<ns2:pointCoordinates><ns2:latitude>%s</ns2:latitude><ns2:longitude>%s</ns2:longitude></ns2:pointCoordinates>'
            '</ns2:point></ns2:tpegPointLocation></ns2:groupOfLocations></ns2:situationRecord>'
            % (rtype, rid, status, iso(start), endtag, inner, lat, lon))


fr = ('<?xml version="1.0"?><d xmlns:ns2="http://datex2.eu/schema/2/2_0" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><ns2:situation>' +
      fr_record("acc", "Accident", "<ns2:accidentType>accident</ns2:accidentType>", now - 600) +
      fr_record("works", "MaintenanceWorks", "<ns2:roadMaintenanceType>roadworks</ns2:roadMaintenanceType>"
                "<ns2:roadNumber>A0007</ns2:roadNumber>", now - 86400, now + 86400) +
      fr_record("shut", "RoadOrCarriagewayOrLaneManagement",
                "<ns2:roadOrCarriagewayOrLaneManagementType>roadClosed</ns2:roadOrCarriagewayOrLaneManagementType>", now - 3600) +
      fr_record("lane", "RoadOrCarriagewayOrLaneManagement",
                "<ns2:roadOrCarriagewayOrLaneManagementType>laneClosures</ns2:roadOrCarriagewayOrLaneManagementType>", now - 3600) +
      fr_record("old", "RoadOrCarriagewayOrLaneManagement",
                "<ns2:roadOrCarriagewayOrLaneManagementType>laneClosures</ns2:roadOrCarriagewayOrLaneManagementType>", now - 900 * 86400) +
      fr_record("pass", "RoadOrCarriagewayOrLaneManagement",
                "<ns2:roadOrCarriagewayOrLaneManagementType>closedPermanentlyForTheWinter</ns2:roadOrCarriagewayOrLaneManagementType>", now - 900 * 86400) +
      fr_record("over", "Accident", "", now - 7200, now - 3600) +
      fr_record("later", "Accident", "", now + 86400) +
      fr_record("paused", "Accident", "", now - 600, status="suspended") +
      fr_record("speed", "SpeedManagement", "", now - 600) +
      fr_record("divert", "ReroutingManagement", "", now - 600) +
      fr_record("jam", "AbnormalTraffic", "<ns2:abnormalTrafficType>queuingTraffic</ns2:abnormalTrafficType>", now - 60) +
      '</ns2:situation></d>').encode()
got = {a["id"]: a for a in alerts._parse_fr(io.BytesIO(fr))}
check("France kinds", {k: v["type"] for k, v in got.items()},
      {"bisonfute:acc": "accident", "bisonfute:works": "roadworks", "bisonfute:shut": "closed",
       "bisonfute:lane": "roadworks", "bisonfute:pass": "closed", "bisonfute:jam": "jam"})
check("France agency and road", (got["bisonfute:works"]["agency"], got["bisonfute:works"]["road"]), ("Bison Futé", "A7"))
check("France position", (got["bisonfute:acc"]["lat"], got["bisonfute:acc"]["lon"]), (45.0, 4.8))

# ---- Spain keeps working through the shared parser, with its agency
dgt = ('<?xml version="1.0"?><d xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><situationRecord '
       'xsi:type="sit:Accident" id="1"><validity><validityStatus>active</validityStatus><validityTimeSpecification>'
       '<overallStartTime>%s</overallStartTime></validityTimeSpecification></validity><cause><causeType>accident'
       '</causeType></cause><roadName>A-6</roadName><kilometerPoint>12</kilometerPoint><pointByCoordinates>'
       '<latitude>40.45</latitude><longitude>-3.79</longitude></pointByCoordinates></situationRecord></d>' % iso(now - 300)).encode()
es = alerts._parse_dgt(io.BytesIO(dgt))
check("Spain still parses", [(a["id"], a["type"], a["agency"], a["road"], a["km"]) for a in es],
      [("dgt:1", "accident", "DGT", "A-6", "12")])

# ---- Germany: which motorways are asked about
munich_to_nuremberg = [[11.58, 48.14], [11.50, 48.60], [11.45, 48.90], [11.30, 49.20], [11.10, 49.45]]
roads = alerts._motorways_near(munich_to_nuremberg)
check("A9 is asked about on the Munich-Nuremberg drive", "A9" in roads, True)
check("at most DE_MAX_ROADS motorways", len(roads) <= alerts.DE_MAX_ROADS, True)
check("A1 (Cologne-Hamburg) isn't", "A1" in roads, False)
check("nothing in Madrid", alerts._motorways_near([[-3.70, 40.41]]), [])

# ---- Germany: the API's three services
warning = {"warning": [
    {"identifier": "w1", "coordinate": {"lat": "50.39", "long": "11.76"}, "title": "A9 | Frankenwald - Berg",
     "subtitle": " Halle/Leipzig -> Nürnberg", "startTimestamp": iso(now - 600), "abnormalTrafficType": "QUEUING_TRAFFIC",
     "description": ["Angespannte Verkehrslage"], "future": False},
    {"identifier": "w2", "coordinate": {"lat": 50.0, "long": 11.0}, "title": "A9", "description": ["Unfall, rechter Fahrstreifen blockiert"]},
    {"identifier": "w3", "coordinate": {"lat": 50.1, "long": 11.1}, "title": "A9", "description": ["Falschfahrer!"]},
    {"identifier": "w4", "coordinate": {"lat": 50.2, "long": 11.2}, "title": "A9", "description": ["Pannenfahrzeug auf dem Seitenstreifen"]},
    {"identifier": "w5", "coordinate": {"lat": "x", "long": 11.2}},
    {"identifier": "w6", "coordinate": {"lat": 40.4, "long": -3.7}, "description": ["Unfall"]},
    "not a dict"]}
closure = {"closure": [
    {"identifier": "c1", "coordinate": {"lat": 49.6, "long": 6.95}, "display_type": "CLOSURE", "future": "False"},
    {"identifier": "c2", "coordinate": {"lat": 49.6, "long": 6.95}, "display_type": "CLOSURE_ENTRY_EXIT", "future": False},
    {"identifier": "c3", "coordinate": {"lat": 49.6, "long": 6.95}, "display_type": "CLOSURE", "future": "True"}]}
works = {"roadworks": [
    {"identifier": "r1", "coordinate": {"lat": 48.87, "long": 11.46}, "isBlocked": "false", "future": False},
    {"identifier": "r2", "coordinate": {"lat": 48.87, "long": 11.46}, "isBlocked": "true", "future": False},
    {"identifier": "r3", "coordinate": {"lat": 48.87, "long": 11.46}, "future": True}]}
de = alerts._parse_de("A9", "warning", warning) + alerts._parse_de("A1", "closure", closure) + \
     alerts._parse_de("A9", "roadworks", works)
check("Germany kinds", {a["id"]: a["type"] for a in de},
      {"autobahn:w1": "jam", "autobahn:w2": "accident", "autobahn:w3": "hazard", "autobahn:w4": "stopped",
       "autobahn:c1": "closed", "autobahn:r1": "roadworks", "autobahn:r2": "closed"})
w1 = [a for a in de if a["id"] == "autobahn:w1"][0]
check("Germany labels", (w1["agency"], w1["road"], w1["town"], w1["dest"]),
      ("Autobahn", "A9", "Frankenwald - Berg", "Halle/Leipzig -> Nürnberg"))
check("Germany garbage replies", alerts._parse_de("A9", "warning", ["x"]) + alerts._parse_de("A9", "warning", {"warning": 5}), [])

# ---- Germany: requests go only to the Autobahn API, one road at a time, cached
asked = []
class Reply(io.BytesIO):
    headers = {}
    def __enter__(self): return self
    def __exit__(self, *a): pass
def fake_urlopen(req, timeout=0):
    asked.append(req.full_url)
    service = req.full_url.rsplit("/", 1)[-1]
    return Reply(json.dumps({service: []}).encode())
alerts.urllib.request.urlopen = fake_urlopen
errors = []
alerts._germany(munich_to_nuremberg, errors)
n = len(asked)
check("Germany: three services per motorway", n, 3 * len(roads))
check("Germany: only the Autobahn API", all(u.startswith("https://verkehr.autobahn.de/o/autobahn/A") for u in asked), True)
alerts._germany(munich_to_nuremberg, errors)
check("Germany: cached for the next refresh", len(asked), n)
check("Germany: no errors", errors, [])

print("all passed" if not failures else "%d failed" % failures)
sys.exit(1 if failures else 0)
