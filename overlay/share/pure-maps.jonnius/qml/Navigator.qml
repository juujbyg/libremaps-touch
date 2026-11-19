/* -*- coding: utf-8-unix -*-
 *
 * Copyright (C) 2014-2017 Osmo Salomaa, 2018-2020 Rinigus
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.0
import QtPositioning 5.4
import org.puremaps 1.0

import "js/util.js" as Util

Item {
    id: navigator

    property alias  destDist:  navigatorBase.destDist
    property alias  destEta:   navigatorBase.destEta
    property alias  destTime:  navigatorBase.destTime
    property bool   destReached: false
    property alias  direction: navigatorBase.direction
    property alias  directionValid: navigatorBase.directionValid
    property bool   followMe:  false
    property bool   hasBeenAlongRoute: false
    property bool   hasDestination: locationsModel.hasDestination
    property bool   hasNextLocation: nextLocationDist
    property bool   hasOrigin: locationsModel.hasOrigin
    property bool   hasRoute:  navigatorBase.route.length > 0
    property bool   hasTraffic: navigatorBase.hasTraffic
    property alias  icon:      navigatorBase.icon
    property alias  locations: navigatorBase.locations
    property alias  locationsModel: navigatorBase.locationsModel
    property alias  maneuvers: navigatorBase.maneuvers
    property alias  manDist:   navigatorBase.manDist
    property alias  manTime:   navigatorBase.manTime
    property alias  narrative: navigatorBase.narrative
    property alias  nextIcon:  navigatorBase.nextIcon
    property bool   nextLocationDestination: locationsModel.nextLocationDestination
    property string nextLocationDist: locationsModel.nextLocationDist
    property string nextLocationEta: locationsModel.nextLocationEta
    property string nextLocationTime: locationsModel.nextLocationTime
    property alias  nextManDist: navigatorBase.nextManDist
    property bool   notify:    app.conf.showNarrative && app.mode === modes.navigate && (icon || narrative)
    property alias  optimized: navigatorBase.optimized
    property real   progress:  navigatorBase.progress / 100.0
    property string provider
    property int    rerouteConsecutiveErrors: 0
    property int    rerouteConsecutiveIgnored: 0
    property real   reroutePreviousTime: -1
    property bool   routing: false
    property alias  roundaboutExit: navigatorBase.roundaboutExit
    property alias  route:     navigatorBase.route
    property alias  running:   navigatorBase.running
    property alias  sign:      navigatorBase.sign
    property alias  street:    navigatorBase.street
    property alias  totalDist: navigatorBase.totalDist
    property alias  totalTime: navigatorBase.totalTime
    property alias  totalTimeInTraffic: navigatorBase.totalTimeInTraffic
    property alias  transportMode: navigatorBase.mode
    // the streets the route turns onto: [{x, y, name}], for the purple tags on the map
    property var    streetTags: []
    // other routes to the same place (Valhalla alternates), while choosing one:
    // each is a full route from the router; the chosen one is also the current route
    property var    alternatives: []
    property int    alternativeIndex: 0

    NavigatorBase {
        id: navigatorBase
        horizontalAccuracy: app.conf.navigationHorizontalAccuracy
        trafficRerouteTime: app.conf.trafficRerouteTime
        units: app.conf.units

        property bool voicePrepared: false

        onLocationArrived: {
            if (app.mode === modes.navigate) {
                notification.flash(destination ? app.tr("Destination %1 reached", name) :
                                                 app.tr("Waypoint %1 reached", name),
                                   "navigatorStop");
            }
        }

        onNavigationEnded: {
            if (app.mode === modes.navigate) {
                notification.flash(app.tr("Destination reached"),
                                   "navigatorStop");
                destReached = true;
            }
        }

        onPromptPlay: {
            if (!app.conf.voiceNavigation) return;
            voice.play(text);
        }

        onPromptPrepare: {
            if (!app.conf.voiceNavigation) return;
            voice.prepare(text, preserve)
        }

        onRerouteRequest: {
            // Find a new route if conditions are met.
            if (!app.conf.reroute) return;
            if (app.mode !== modes.navigate) return;
            if (!gps.horizontalAccuracyValid || !gps.ready) return;
            if (gps.horizontalAccuracy > 100) return;
            if (!py.evaluate("poor.app.router.can_reroute")) return;
            if (hasBeenAlongRoute) rerouteConsecutiveIgnored = 0;
            var interval = 5000*Math.pow(2, Math.min(4, rerouteConsecutiveErrors + rerouteConsecutiveIgnored));
            if (py.evaluate("poor.app.router.offline")) {
                if (Date.now() - reroutePreviousTime < interval) return;
                return reroute();
            } else {
                // Limit the total amount and frequency of rerouting for online routers
                // to avoid an excessive amount of API calls (causing data traffic and
                // costs) in some special case where the router returns bogus results
                // and the user is not able to manually intervene.
                if (Date.now() - reroutePreviousTime < interval) return;
                return reroute(traffic);
            }
        }

        onAlongRouteChanged: {
            if (!hasBeenAlongRoute && alongRoute) hasBeenAlongRoute = true;
        }

        onRunningChanged: {
            if (running && followMe)
                followMe = false;

            if (destReached)
                destReached = false;

            if (running) {
                // the trip uses the chosen route: the other ones leave the map
                alternatives = [];
                alternativeIndex = 0;
                rerouteConsecutiveErrors = 0;
                rerouteConsecutiveIgnored = 0;
                reroutePreviousTime = -1;
                hasBeenAlongRoute = alongRoute;
                updatePosition();
            }

            if (running && app.conf.voiceNavigation) {
                // check if the call was caused by rerouting, for example
                if (voicePrepared) return;

                if (voice.active) {
                    notification.flash(app.tr("Voice navigation on"), "navVoice");
                    navigatorBase.prepareStandardPrompts();
                    navigatorBase.prompt("std:starting navigation");
                    voicePrepared = true;
                } else {
                    notification.flash(app.tr("Voice navigation unavailable: missing Text-to-Speech (TTS) engine for selected language"),
                                       "navVoice");
                }
            } else {
                voicePrepared = false;
            }
        }

        function updatePosition() {
            if (destReached) return; // no more updates
            var dir = gps.directionDeviceValid ? gps.directionDevice : gps.direction;
            var dirValid = gps.directionValid;
            if (!dirValid) {
                // Standing still there is no course, and the navigator then
                // calls a perfectly good position "unknown". Use the way the
                // route runs where we are, so it can start from a standstill.
                var b = routeBearingAt(gps.coordinate);
                if (b >= 0) {
                    dir = b;
                    dirValid = true;
                }
            }
            navigatorBase.setPosition(gps.coordinate, dir,
                                      gps.horizontalAccuracy,
                                      gps.horizontalAccuracyValid &&
                                      gps.ready && dirValid);
        }

        // bearing of the route at the point nearest to c, or -1
        property int bearingHint: 0
        function routeBearingAt(c) {
            var r = navigatorBase.route;
            if (!r || r.length < 2 || !c || !c.isValid) return -1;
            // search near the last match first; fall back to the whole route
            var n = r.length, best = -1, bd = 1e12;
            var from = Math.max(0, bearingHint - 50), to = Math.min(n - 1, bearingHint + 400);
            for (var pass = 0; pass < 2 && best < 0; pass++) {
                for (var i = from; i < to; i++) {
                    var d = c.distanceTo(r[i]);
                    if (d < bd) { bd = d; best = i; }
                }
                if (bd > 150 + gps.horizontalAccuracy) { best = -1; bd = 1e12; from = 0; to = n - 1; }
            }
            if (best < 0 || bd > 150 + gps.horizontalAccuracy) return -1;
            bearingHint = best;
            // a few points ahead, so a tiny kink doesn't set the direction
            var j = best + 1;
            while (j < n - 1 && r[best].distanceTo(r[j]) < 15) j++;
            return Math.round(r[best].azimuthTo(r[j]));
        }
    }

    Voice {
        id: voice
        enabled: app.conf.voiceNavigation
        engine: "navigator"
        gender: app.conf.voiceGender
        language: navigatorBase.language
    }

    Connections {
        target: gps
        onPositionUpdated: navigatorBase.updatePosition()
    }

    Component.onCompleted: {
        loadRoute();
    }

    function chooseAlternative(index) {
        // switch the route shown to one of the alternatives
        if (index < 0 || index >= alternatives.length || index === alternativeIndex) return;
        setRoute(alternatives[index]);
        alternativeIndex = index;
    }

    function clearRoute() {
        alternatives = [];
        alternativeIndex = 0;
        navigatorBase.clearRoute();
        streetTags = [];
        provider = "";
        saveRoute({});
    }

    function findRoute(locations, options, traffic) {
        if (routing) return;
        if (!options) options = {};
        options.optimized = navigatorBase.optimized;
        // alternatives only while choosing a route, never when rerouting a trip
        options.alternatives = !navigatorBase.running;
        var notifyId = "route";
        var loc = locations || navigatorBase.locations;
        // note that GPX trace does not use locations
        if (loc.length >= 1 && !loc[0].origin) {
            if (!gps.coordinateValid) {
                app.notification.flash(app.tr("Routing failed: current position not known"), notifyId);
                return;
            }
            var p = app.getPosition();
            var here = {"text": navigatorBase.running ?
                                    app.tr("Rerouting position") :
                                    app.tr("Current position"),
                        "x": p[0], "y": p[1]};
            // which way we face, when moving, so the route doesn't start
            // with a U-turn; and how rough the position is, so the router
            // may start from any road within it instead of only the nearest
            if (gps.directionValid) here.heading = Math.round(gps.direction);
            if (gps.horizontalAccuracyValid) here.accuracy = Math.round(gps.horizontalAccuracy);
            loc.splice(0, 0, here);
        }
        // filter out arrived locations
        loc = loc.filter(function (l) {
           return !l.arrived;
        });
        var notification  = options.notification || app.tr("Routing")
        app.notification.hold(notification, notifyId);
        routing = true;
        var args = [loc,
                    options];
        py.call("poor.app.router.route", args, function(route) {
            var alts = [];
            if (Array.isArray(route) && route.length > 0) {
                // several routes: the first (fastest) is used, the others are
                // offered in the route panel
                alts = route;
                route = route[0];
            }
            if (route && route.error && route.message) {
                app.notification.flash(app.tr("Routing failed: %1").arg(route.message), notifyId);
                if (options.voicePrompt) navigatorBase.prompt("std:routing failed");
                rerouteConsecutiveErrors++;
            } else if (route && route.x && route.x.length > 0) {
                if (route.offline)
                    app.notification.flash(app.tr("No connection: route from your offline maps, times are estimates"),
                                           notifyId);
                else
                    app.notification.flash(navigatorBase.running ?
                                               (traffic ? app.tr("Traffic and route updated") : app.tr("New route found")) :
                                               app.tr("Route found"), notifyId);
                if (options.voicePrompt) navigatorBase.prompt(traffic ? "std:traffic updated" :
                                                                        "std:new route found");
                setRoute(route);
                alternativeIndex = 0;
                alternatives = alts.length > 1 ? alts : [];
                rerouteConsecutiveErrors = 0;
                if (options.fitToView) map.fitViewToRoute();
                if (options.save) {
                    saveDestination();
                    saveLocations();
                }
            } else {
                app.notification.flash(app.tr("Routing failed"), notifyId);
                if (options.voicePrompt) navigatorBase.prompt("std:routing failed");
                rerouteConsecutiveErrors++;
            }
            routing = false;
        });
    }

    function say(text) {
        // speak a custom phrase (hazard alerts); respects the voice setting
        if (!app.conf.voiceNavigation || !text) return;
        voice.prepare(text, true);
        voice.play(text);
    }

    function loadRoute() {
        // Restore route polyline from JSON file.
        py.call("poor.storage.read_route", [], function(data) {
            if (data.x && data.x.length > 0) setRoute(data);
        });
    }

    function locationRemove(index) {
        if (!navigatorBase.locationRemove(index)) {
            console.log("Failed to remove location " + index);
            return false;
        }
        return true;
    }

    function reroute(traffic) {
        // Find a new route from the current position to the existing destination.
        if (routing) return;
        if (!traffic) navigatorBase.prompt("std:rerouting");
        if (!hasBeenAlongRoute) rerouteConsecutiveIgnored++;
        hasBeenAlongRoute = false;
        var loc = navigatorBase.locations.slice(1);
        var options = {
            "heading": gps.directionValid ? gps.direction : null,
            "notification": traffic ? app.tr("Updating traffic"): app.tr("Rerouting"),
            "voicePrompt": true
        }
        findRoute(loc, options, traffic);
        reroutePreviousTime = Date.now();
    }

    function saveDestination() {
        // Save destinations if not POIs
        var _destinationsNotForSave = [];
        var pois = app.pois.pois.filter(function (p) {
            return (p.bookmarked && p.shortlisted);
        });
        pois.sort(function (a, b){
            if (a.title < b.title) return -1;
            if (a.title > b.title) return 1;
            return 0;
        })
        pois.forEach(function (p) {
            var t = {
                "text": (p.title ? p.title : app.tr("Unnamed point")) +
                        (p.shortlisted ? " ☰" : ""),
                "toText": p.title ? p.title : app.tr("Unnamed point"),
                "type": "poi",
                "visible": true,
                "x": p.coordinate.longitude,
                "y": p.coordinate.latitude
            };
            _destinationsNotForSave.push(t);
        });

        var loc = navigatorBase.locations;
        var dest = loc[ loc.length - 1 ];

        for (var i=0; i < _destinationsNotForSave.length; i++)
            if (dest.text === _destinationsNotForSave[i].toText &&
                    Math.abs(dest.x -_destinationsNotForSave[i].x) < 1e-8 &&
                    Math.abs(dest.y -_destinationsNotForSave[i].y) < 1e-8)
                return false;

        if (!dest.text)
            return false;

        py.call_sync("poor.app.history.add_destination", [dest]);
        return true;
    }

    function saveLocations() {
        py.call_sync("poor.app.history.add_route",
                     [{  "locations": navigatorBase.locations,
                         "optimized": navigatorBase.optimized }]);
    }

    function makeStreetTags(maneuvers) {
        // one tag per street the route turns onto; the start has no turn
        var tags = [], seen = {};
        for (var i = 1; i < maneuvers.length; i++) {
            var m = maneuvers[i];
            var s = m.street;
            if (Array.isArray(s)) s = s.length > 0 ? s[0] : "";
            s = s ? String(s).split(";")[0].trim() : "";
            if (!s || s.charAt(0) === "\u21e8" || seen[s] || m.x === undefined) continue;
            seen[s] = true;
            tags.push({"x": m.x, "y": m.y, "name": s});
        }
        return tags;
    }

    function saveRoute(route_in) {
        // Save route polyline to JSON file.
        var data = Util.polylineToJson(route_in);
        py.call_sync("poor.storage.write_route", [data]);
    }

    function setRoute(route) {
        // Set new route
        navigatorBase.setRoute(route);
        streetTags = makeStreetTags(route.maneuvers || []);
        provider = route.provider;
        saveRoute(route);
    }

}
