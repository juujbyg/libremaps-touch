"""Checks for the fuel price readers of every country, with no network.

Run from the maps folder:  python3 -I tests/fuelprices_check.py
Each country's download is answered with a small sample in the real format (seen in 2026),
including broken rows that must be skipped, and the URL is checked for what it gives away.
"""
import json, os, sys, tempfile, types

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.join(os.path.dirname(HERE), "overlay", "share", "pure-maps.jonnius")
sys.path.insert(0, PKG)
poor = types.ModuleType("poor"); poor.__path__ = [os.path.join(PKG, "poor")]
poor.CACHE_HOME_DIR = tempfile.mkdtemp()
sys.modules["poor"] = poor
from poor import fuelprices as fp  # noqa: E402

failures = 0
asked = []


def check(name, got, want):
    global failures
    ok = got == want
    failures += not ok
    print("ok  " if ok else "FAIL", name, "" if ok else "-> got %r, want %r" % (got, want))


IT_STATIONS = ("Estrazione del 2026-11-24\n"
               "idImpianto|Gestore|Bandiera|Tipo Impianto|Nome Impianto|Indirizzo|Comune|Provincia|Latitudine|Longitudine\n"
               "100|ENI SPA|Agip Eni|Stradale|ROMA 1|VIA X|ROMA|RM|41.9000|12.5000\n"
               "101|BROKEN|Q8|Stradale|NO COORDS|VIA Y|ROMA|RM|abc|\n").encode()
IT_PRICES = ("Estrazione del 2026-11-24\n"
             "idImpianto|descCarburante|prezzo|isSelf|dtComu\n"
             "100|Benzina|1.899|0|23/11/2026 08:00:00\n"
             "100|Benzina|1.799|1|24/11/2026 07:31:12\n"
             "100|Gasolio|1.699|1|24/11/2026 07:31:12\n"
             "100|Blue Diesel|1.899|1|24/11/2026 07:31:12\n"
             "100|GPL|0.759|1|24/11/2026 07:31:12\n"
             "100|Mystery fuel|1.0|1|24/11/2026 07:31:12\n"
             "100|Gasolio|NaN|1|24/11/2026 07:31:12\n").encode()
MX_PLACES = b"""<?xml version="1.0" encoding="utf-8"?><places>
<place place_id="2039"><name>ESTACION HIPODROMO</name><location><x>-99.1332</x><y>19.4326</y></location></place>
<place place_id="2040"><name>NO LOCATION</name></place></places>"""
MX_PRICES = b"""<?xml version="1.0" encoding="utf-8"?><places>
<place place_id="2039"><gas_price type="regular">22.95</gas_price><gas_price type="premium">27.9</gas_price>
<gas_price type="diesel">26</gas_price><gas_price type="mystery">1</gas_price></place>
<place place_id="9999"><gas_price type="regular">22</gas_price></place></places>"""


def fake_get(url, timeout=30, accept=""):
    asked.append(url)
    if "data.economie.gouv.fr" in url:
        return json.dumps([
            {"id": 1, "geom": {"lat": 48.8566, "lon": 2.3522}, "adresse": "1 rue X",
             "gazole_prix": 1.759, "gazole_maj": "2026-11-24T06:00:00+00:00",
             "e10_prix": 1.699, "e10_maj": "2026-11-24T07:15:00+00:00", "sp98_prix": None},
            {"id": 2, "geom": None, "gazole_prix": 1.5}]).encode()
    if "anagrafica" in url:
        return IT_STATIONS
    if "prezzo_alle_8" in url:
        return IT_PRICES
    if "dgeg.gov.pt" in url:
        code = int(url.split("idsTiposComb=")[1].split("&")[0])
        price = {2101: "1,859 €", 3201: "1,999 €"}.get(code)
        res = [{"Id": 7, "Marca": "GALP", "Preco": price, "Latitude": 38.7223, "Longitude": -9.1393,
                "DataAtualizacao": "2026-11-23 22:00"}] if price else []
        return json.dumps({"status": True, "resultado": res}).encode()
    if "e-control.at" in url:
        ft = url.split("fuelType=")[1].split("&")[0]
        return json.dumps([
            {"id": 5, "name": "OMV Wien", "location": {"latitude": 48.2082, "longitude": 16.3738},
             "prices": [{"fuelType": ft, "amount": {"DIE": 1.909, "SUP": 1.589}.get(ft, 0)}]},
            {"id": 6, "name": "No price", "location": {"latitude": 48.21, "longitude": 16.38}, "prices": []}]).encode()
    if "goriva.si" in url:
        if "page=2" in url:
            return json.dumps({"next": "https://evil.example/steal", "results": [
                {"name": "PETROL 2", "lat": 46.0511, "lng": 14.5051, "prices": {"95": 1.413, "dizel": None}}]}).encode()
        return json.dumps({"next": "https://goriva.si/api/v1/search/?page=2", "results": [
            {"name": "PETROL 1", "lat": 46.0600, "lng": 14.5100, "prices": {"95": 1.42, "dizel": 1.738, "avtoplin-lpg": 1.153}}]}).encode()
    if url.endswith("/places"):
        return MX_PLACES
    if url.endswith("/prices"):
        return MX_PRICES
    if "minetur" in url:
        return json.dumps({"Fecha": "24/11/2026 10:00:00", "ListaEESSPrecio": [
            {"Latitud": "40,4170", "Longitud (WGS84)": "-3,7036", "Rótulo": "REPSOL", "Horario": "L-D: 24H",
             "Precio Gasoleo A": "1,935", "Precio Gasolina 95 E5": "", "Precio Adblue": "abc"}]}).encode()
    raise AssertionError("unexpected URL " + url)


fp._get = fake_get

# which country's data is asked first
check("Paris is France", [c[0] for c in fp.country_at(48.8566, 2.3522)], ["fr"])
check("Lisbon is Portugal before Spain", [c[0] for c in fp.country_at(38.72, -9.14)], ["pt", "es"])
check("Vienna is Austria", [c[0] for c in fp.country_at(48.21, 16.37)][0], "at")
check("Ljubljana is Slovenia first", [c[0] for c in fp.country_at(46.05, 14.5)][0], "si")
check("Madrid is Spain", [c[0] for c in fp.country_at(40.4169, -3.7035)], ["es"])
check("nowhere in the Atlantic", fp.country_at(30.0, -40.0), [])

s = fp.station(48.8567, 2.3523)
check("France prices", s and s["prices"], [["Diesel", "1.759"], ["95 E10", "1.699"]])
check("France date, Paris time", s and s["date"], "24/11 08:15")
check("France source", s and (s["source"], s["unit"]), ("prix-carburants.gouv.fr", "€/L"))
fr_url = [u for u in asked if "economie" in u][0]
check("France asks about a rounded area", "POINT%282.4+48.9%29" in fr_url, True)

s = fp.station(41.9001, 12.5001)
check("Italy self-service first, by fuel", s and s["prices"],
      [["Diesel", "1.699"], ["95", "1.799"], ["Diesel+", "1.899"], ["LPG", "0.759"]])
check("Italy brand and date", s and (s["brand"], s["date"]), ("Agip Eni", "24/11 07:31"))

s = fp.station(38.7224, -9.1394)
check("Portugal merges fuel files", s and s["prices"], [["Diesel", "1.859"], ["95", "1.999"]])
check("Portugal date", s and s["date"], "23/11 22:00")

s = fp.station(48.2083, 16.3739)
check("Austria prices from both fuel queries", s and sorted(s["prices"]), [["95", "1.589"], ["Diesel", "1.909"]])
check("Austria never sends a station without prices", fp.station(48.2100, 16.3800), None)
at_urls = [u for u in asked if "e-control" in u][:3]
check("Austria asks about a rounded point", all("latitude=48.21&longitude=16.37" in u for u in at_urls), True)

s = fp.station(46.0601, 14.5101)
check("Slovenia prices", s and s["prices"], [["Diesel", "1.738"], ["95", "1.420"], ["LPG", "1.153"]])
check("Slovenia second page", bool(fp.station(46.0511, 14.5051)), True)
check("Slovenia never follows a link off goriva.si", any("evil" in u for u in asked), False)

s = fp.station(19.4327, -99.1333)
check("Mexico prices and unit", s and (s["prices"], s["unit"]),
      ([["Regular", "22.950"], ["Premium", "27.900"], ["Diesel", "26.000"]], "MX$/L"))

s = fp.station(40.4169, -3.7035, "28013")
check("Spain prices, bad ones skipped", s and s["prices"], [["Diesel", "1.935"]])
check("Spain asks for the province only", [u for u in asked if "minetur" in u][-1].endswith("/FiltroProvincia/28"), True)

check("no station near", fp.station(48.9000, 2.4000), None)

# a second look comes from the cache, with no new download
n = len(asked)
fp.station(48.8567, 2.3523); fp.station(41.9001, 12.5001)
check("cached in memory", len(asked), n)
fp._mem.clear()
fp.station(41.9001, 12.5001)
check("cached on disk", len(asked), n)

# a dead service is just no prices
def broken(url, timeout=30, accept=""):
    raise OSError("network down")
fp._get = broken
fp._mem.clear()
check("offline gives None", fp.station(46.3, 13.6), None)

# hostile prices
check("price sanity", [fp._price(x) for x in ("1,859 €", "0", "-1", "1e9", "", None, "1.2.3", 1.5, True, "nan", "inf")],
      ["1.859", "", "", "", "", "", "", "1.500", "", "", ""])

print("all passed" if not failures else "%d failed" % failures)
sys.exit(1 if failures else 0)
