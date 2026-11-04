# LibreMaps for Ubuntu Touch

Private maps and navigation for Ubuntu Touch: walking, cycling, driving, buses and metro.
There's no account, no ads and no analytics, and it needs no API keys.

LibreMaps is a fork of [Pure Maps](https://github.com/rinigus/pure-maps) 3.5.0 by Rinigus,
Osmo Salomaa and contributors, and of its Ubuntu Touch port by Jonatan Hatakeyama
(`pure-maps.jonnius`). Get it from the [OpenStore](https://open-store.io/app/libremaps.juujbyg).

## What it adds

- OpenStreetMap-style day and night maps built from OpenFreeMap (`build_styles.py`)
- One search bar with shortcut chips (food, coffee, fuel, pharmacy, parking)
- One router for every mode: Valhalla for walk, bike, car, scooter and taxi, and
  Transitous for public transport (`routers/libremaps.py`)
- A keyless "nearby" guide that uses Overpass, with Photon as a fallback (`guides/libremaps.py`)
- Offline maps: downloads a region's tiles, fonts and sprites (`poor/offline.py`, `qml/OfflinePage.qml`)
- Speed limits and fixed speed cameras from OpenStreetMap (`qml/RoadWatch.qml`)
- Traffic alerts: official incidents from Spain's DGT, and police, accidents, hazards,
  closed roads, jams and mobile cameras reported by other drivers through Nostr relays
  (`poor/alerts.py`, `poor/nostr.py`, `qml/Alerts.qml`). Reports are anonymous: each one is
  signed with a fresh one-use key and carries only the spot, the direction and the time.
  They expire on their own (30 minutes to 3 hours), and drivers passing by can confirm or
  dismiss them.
- An approximate position until the first GPS fix, so routing works right away (`qml/ApproxLocation.qml`)

## Outside services

These are contacted only when you use the feature that needs them:
OpenFreeMap (map tiles), Photon (search, and places nearby when Overpass fails),
Valhalla at openstreetmap.de (routes and speed limits),
Transitous (public transport), Overpass (speed cameras and places nearby), ipwho.is (rough
position before the first GPS fix), the DGT's open data feed at nap.dgt.es (official traffic
incidents in Spain) and the Nostr relays relay.damus.io, nos.lol, relay.primal.net and
offchain.pub (drivers' reports, read by area and published when you report). The app's About page lists them too.

## API keys

LibreMaps ships no API keys (`poor/apikeys.py` is empty). Providers that need a key, such as
HERE, Mapbox, MapTiler or Foursquare, show "API key missing" until you enter your own key in
Preferences.

## How it's built

LibreMaps changes only QML, Python and data files. It reuses the native parts of the stock
package, which is built from the unmodified Pure Maps 3.5.0 sources:

1. Copy the installed stock package (`/opt/click.ubuntu.com/pure-maps.jonnius/current/`,
   version 3.5.0) to `orig/`.
2. Run `./build.sh <version>`. It copies `orig/` and lays `overlay/` over it. Then it renames the
   data folder, and in the `pure-maps` binary it replaces the string `pure-maps.jonnius` with
   `libremaps.juujbyg`. Both names are the same length, so this works on the compiled file.
3. Package `build/pkg` with `click build build/pkg`. On a phone, `click` is already installed.

`./build.sh --dev <version>` adds `devhook/DevHook.qml`, which runs a script from the app's
config folder so the app can be tested without touching the screen. Don't install dev builds
for normal use.

## License

GNU General Public License, version 3 or later. See `LICENSE`. The native code is Pure Maps
3.5.0 (GPL-3.0) and [MapLibre Native Qt](https://github.com/maplibre/maplibre-native-qt) (BSD-2-Clause).
