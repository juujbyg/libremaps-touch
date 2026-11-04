/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: traffic alerts.
 *
 * Gathers alerts for the area being watched (the route ahead while
 * navigating, otherwise the visible map):
 *  - official incidents from Spain's DGT and reports by other drivers
 *    through Nostr relays (poor/alerts.py), if "Traffic alerts" is on
 *  - fixed speed cameras from OpenStreetMap (RoadWatch.qml), if "Road
 *    alerts" is on
 * It draws them on the map, finds the next one ahead on the route, warns by
 * voice once, and after passing a driver's report asks if it was still
 * there. AlertBanner.qml shows the warning, ReportSheet.qml sends reports.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.0

Item {
    id: alerts

    property bool watching: app.conf.communityAlerts
    property var  items: []          // everything in the watched area
    property var  next: null         // the alert ahead to warn about
    property real nextDist: -1       // metres to it along the route
    property var  passed: null       // a driver's report just passed

    readonly property var reportTypes: ["police", "accident", "hazard", "closed", "jam", "camera"]
    readonly property var types: ["police", "accident", "hazard", "closed", "jam", "camera",
                                  "camera_fixed", "roadworks", "stopped", "fire", "weather"]
    readonly property string sourceId: "libremaps-alerts"
    readonly property string layerId: "libremaps-alerts-layer"

    property bool _navigating: app.mode === modes.navigate && navigator.route.length > 1
    property bool _moving: app.mode === modes.navigate || app.mode === modes.followMe
    property var  _official: []       // last list from Python
    property var  _cum: []            // distance along the route at each point
    property int  _idx: 0             // route point closest to us
    property var  _spoken: ({})
    property var  _askedFor: ({})
    property var  _lastAhead: null
    property real _lastLat: 0
    property real _lastLon: 0
    property real _lastTime: 0

    Component.onCompleted: {
        py.setHandler("alerts.updated", function(list, err) {
            if (err) console.log("Alerts: " + err);
            alerts._official = list || [];
            alerts.rebuild();
        });
        py.setHandler("alerts.reported", function(kind, ok, total) {
            if (ok > 0)
                notification.flash(app.tr("Reported. Thanks for helping other drivers!"), "alerts", 4);
            else
                notification.flash(app.tr("Couldn't send the report: no relay answered"), "alerts", 6);
        });
    }

    // ---------------------------------------------------------- refreshing

    Timer {
        // while driving, every 3 minutes
        interval: 180000
        repeat: true
        running: alerts.watching && alerts._moving && gps.coordinateValid
        triggeredOnStart: true
        onTriggered: alerts.refresh()
    }

    Timer {
        // browsing: once the map stops moving
        id: settle
        interval: 2500
        onTriggered: alerts.refreshBrowsing()
    }

    Connections {
        target: map
        onCenterChanged: if (!alerts._moving) settle.restart()
    }

    Connections {
        target: navigator
        onRouteChanged: routeDelay.restart()
    }
    Timer { id: routeDelay; interval: 2000; onTriggered: { alerts.indexRoute(); alerts.refresh(); } }

    Connections {
        target: roadWatch
        onCamerasChanged: alerts.rebuild()
    }

    onWatchingChanged: {
        if (watching) refresh();
        else { _official = []; rebuild(); }
    }

    function refresh() {
        if (!watching) return;
        var pts = [];
        var r = navigator.route;
        if (_navigating && _cum.length === r.length) {
            // the route ahead, a point about every kilometre, up to 80 km
            var start = _cum[_idx], last = -1e9;
            for (var i = _idx; i < r.length; i++) {
                if (_cum[i] - start > 80000) break;
                if (_cum[i] - last >= 1000 || i === r.length - 1) {
                    pts.push([r[i].longitude, r[i].latitude]);
                    last = _cum[i];
                }
            }
        } else if (gps.coordinateValid && _moving) {
            var c = gps.coordinate;
            pts = around(c.latitude, c.longitude, 0.03);
        } else {
            pts = around(map.center.latitude, map.center.longitude, 0.04);
        }
        if (pts.length === 0) return;
        _lastLat = pts[0][1]; _lastLon = pts[0][0]; _lastTime = Date.now();
        py.call("poor.alerts.refresh", [pts], null);
    }

    function refreshBrowsing() {
        if (!watching || _moving || map.zoomLevel < 10) return;
        var c = map.center;
        var moved = dist(c.latitude, c.longitude, _lastLat, _lastLon);
        if (moved < 3000 && Date.now() - _lastTime < 300000) return;
        refresh();
    }

    function around(lat, lon, d) {
        return [[lon, lat], [lon - d, lat - d], [lon + d, lat - d], [lon - d, lat + d], [lon + d, lat + d]];
    }

    // ---------------------------------------------------------- the list

    function rebuild() {
        var list = watching ? _official.slice() : [];
        if (app.conf.roadAlerts) {
            var cams = roadWatch.cameras || [];
            for (var i = 0; i < cams.length; i++)
                list.push({"id": "osm-camera:" + i, "source": "osm", "type": "camera_fixed",
                           "lat": cams[i].lat, "lon": cams[i].lon, "maxspeed": cams[i].maxspeed || 0,
                           "created": 0, "expires": 0, "road": "", "km": "", "town": "",
                           "up": 0, "down": 0, "heading": -1});
        }
        projectAll(list);
        items = list;
        updateMap();
        track();
    }

    // ------------------------------------------------- route bookkeeping

    function indexRoute() {
        var r = navigator.route, cum = [], total = 0;
        for (var i = 0; i < r.length; i++) {
            if (i > 0) total += dist(r[i-1].latitude, r[i-1].longitude, r[i].latitude, r[i].longitude);
            cum.push(total);
        }
        _cum = cum;
        _idx = 0;
        _spoken = {};
        _askedFor = {};
        projectAll(items);
        updateMap();
    }

    function projectAll(list) {
        var r = navigator.route;
        var ok = _navigating && _cum.length === r.length;
        for (var i = 0; i < list.length; i++) {
            var a = list[i];
            a.onRoute = false;
            a.along = -1;
            if (!ok) continue;
            var best = 1e12, bi = -1;
            for (var j = 0; j < r.length; j++) {
                var d = dist(a.lat, a.lon, r[j].latitude, r[j].longitude);
                if (d < best) { best = d; bi = j; }
            }
            var near = (a.source === "dgt") ? 120 : 70;
            if (bi < 0 || best > near) continue;
            if (a.heading >= 0 && bi < r.length - 1) {
                // a report made going the other way is for the other side
                var b = bearing(r[bi].latitude, r[bi].longitude, r[bi+1].latitude, r[bi+1].longitude);
                var diff = Math.abs(((a.heading - b) % 360 + 540) % 360 - 180);
                if (diff > 70) continue;
            }
            a.onRoute = true;
            a.along = _cum[bi];
        }
    }

    // ------------------------------------------------------- what's ahead

    Connections {
        target: gps
        onPositionUpdated: alerts.track()
    }

    function track() {
        if (!gps.coordinateValid || !_moving) { setNext(null, -1); return; }
        var lat = gps.coordinate.latitude, lon = gps.coordinate.longitude;
        var speed = gps.speedValid ? gps.speed : 0;
        var warn = Math.max(500, Math.min(2000, speed * 35));
        var best = null, bestD = 1e12;
        if (_navigating && _cum.length === navigator.route.length) {
            var r = navigator.route;
            // where we are on the route: look near the last match first
            var bi = _idx, bd = 1e12;
            var from = Math.max(0, _idx - 10), to = Math.min(r.length - 1, _idx + 120);
            for (var j = from; j <= to; j++) {
                var d = dist(lat, lon, r[j].latitude, r[j].longitude);
                if (d < bd) { bd = d; bi = j; }
            }
            if (bd > 200) {
                for (j = 0; j < r.length; j++) {
                    d = dist(lat, lon, r[j].latitude, r[j].longitude);
                    if (d < bd) { bd = d; bi = j; }
                }
            }
            _idx = bi;
            var here = _cum[bi];
            for (var i = 0; i < items.length; i++) {
                var a = items[i];
                if (!a.onRoute) continue;
                var ahead = a.along - here;
                if (ahead < -15) {
                    checkPassed(a, -ahead);
                    continue;
                }
                if (ahead < bestD) { bestD = ahead; best = a; }
            }
        } else {
            // following without a route: the closest one in front of us
            var dir = gps.directionValid ? gps.direction : -1;
            for (i = 0; i < items.length; i++) {
                a = items[i];
                d = dist(lat, lon, a.lat, a.lon);
                if (d > warn) continue;
                if (dir >= 0) {
                    var b2 = bearing(lat, lon, a.lat, a.lon);
                    if (Math.abs(((b2 - dir) % 360 + 540) % 360 - 180) > 35) {
                        if (_lastAhead && _lastAhead.id === a.id && d < 80) checkPassed(a, d);
                        continue;
                    }
                }
                if (d < bestD) { bestD = d; best = a; }
            }
        }
        if (best && bestD <= warn) {
            setNext(best, Math.max(0, bestD));
            if (!_spoken[best.id]) {
                _spoken[best.id] = true;
                navigator.say(spoken(best));
            }
        } else {
            setNext(null, -1);
        }
    }

    function setNext(a, d) {
        if (a) _lastAhead = a;
        next = a;
        nextDist = d;
    }

    function checkPassed(a, behind) {
        // ask once about a driver's report we were warned about, right after passing it
        if (a.source !== "community" || !_spoken[a.id] || _askedFor[a.id] || behind > 400) return;
        _askedFor[a.id] = true;
        passed = a;
        passedTimer.restart();
    }

    Timer {
        id: passedTimer
        interval: 25000
        onTriggered: alerts.passed = null
    }

    // ------------------------------------------------------ reporting

    function report(kind) {
        if (!gps.coordinateValid) {
            notification.flash(app.tr("Your position isn't known yet"), "alerts", 4);
            return;
        }
        var c = gps.coordinate;
        py.call("poor.alerts.report",
                [kind, c.latitude, c.longitude, gps.directionValid ? gps.direction : -1],
                function() { alerts.refreshSoon(); });
    }

    function vote(a, up) {
        if (!a) return;
        py.call("poor.alerts.vote", [a.id, up], null);
        passed = null;
        notification.flash(up ? app.tr("Thanks, confirmed") : app.tr("Thanks, it will be removed for others too"), "alerts", 3);
        refreshSoon();
    }

    function refreshSoon() { soon.restart(); }
    Timer { id: soon; interval: 1500; onTriggered: py.call("poor.alerts.current", [], function(list) {
        alerts._official = list || []; alerts.rebuild(); }) }

    // ----------------------------------------------------------- text

    function title(a) {
        if (!a) return "";
        switch (a.type) {
        case "police": return app.tr("Police");
        case "accident": return app.tr("Accident");
        case "hazard": return app.tr("Hazard on the road");
        case "closed": return app.tr("Road closed");
        case "jam": return app.tr("Traffic jam");
        case "camera": return app.tr("Mobile speed camera");
        case "camera_fixed": return a.maxspeed ? app.tr("Speed camera · %1").arg(a.maxspeed) : app.tr("Speed camera");
        case "roadworks": return app.tr("Roadworks");
        case "stopped": return app.tr("Stopped vehicle");
        case "fire": return app.tr("Vehicle on fire");
        case "weather": return app.tr("Bad weather");
        }
        return app.tr("Alert");
    }

    function subtitle(a) {
        if (!a) return "";
        if (a.source === "dgt") {
            var where = a.road ? a.road + (a.km ? " km " + a.km : "") : (a.town || "");
            return where ? "DGT · " + where : "DGT";
        }
        if (a.source === "osm") return app.tr("Fixed camera");
        var mins = Math.max(1, Math.round((Date.now() / 1000 - a.created) / 60));
        var s = app.tr("Reported %1 min ago").arg(mins);
        if (a.up > 0) s += " · " + app.tr("confirmed %1×").arg(a.up);
        return s;
    }

    function spoken(a) {
        switch (a.type) {
        case "police": return app.tr("Police reported ahead");
        case "accident": return app.tr("Accident ahead");
        case "hazard": return app.tr("Hazard on the road ahead");
        case "closed": return app.tr("Road closed ahead");
        case "jam": return app.tr("Traffic jam ahead");
        case "camera": return app.tr("Mobile speed camera reported ahead");
        case "camera_fixed": return app.tr("Speed camera ahead");
        case "roadworks": return app.tr("Roadworks ahead");
        case "stopped": return app.tr("Stopped vehicle ahead");
        case "fire": return app.tr("Vehicle on fire ahead");
        case "weather": return app.tr("Bad weather ahead");
        }
        return app.tr("Alert ahead");
    }

    function iconUrl(type) {
        return Qt.resolvedUrl("icons/alerts/%1.svg".arg(type));
    }

    // ------------------------------------------------------------ map

    function initMap() {
        // called by Map.setStyleAdditions, again after each style change
        var size = 40 * styler.themePixelRatio;
        for (var i = 0; i < types.length; i++)
            map.addImagePath("alert-" + types[i], iconUrl(types[i]), size);
        map.updateSource(sourceId, {"type": "geojson", "data": collection()});
        map.addLayer(layerId, {"type": "symbol", "source": sourceId});
        map.setLayoutProperty(layerId, "icon-image", "{icon}");
        map.setLayoutProperty(layerId, "icon-allow-overlap", true);
        map.setLayoutProperty(layerId, "icon-ignore-placement", true);
        map.setLayoutProperty(layerId, "icon-size", 1.0 * map.mapToQtPixelRatio / map.devicePixelRatio);
    }

    function collection() {
        var f = [];
        for (var i = 0; i < items.length; i++) {
            var a = items[i];
            // while navigating, only what's on the route
            if (_navigating && !a.onRoute) continue;
            f.push({"type": "Feature",
                    "geometry": {"type": "Point", "coordinates": [a.lon, a.lat]},
                    "properties": {"icon": "alert-" + a.type}});
        }
        return {"type": "FeatureCollection", "features": f};
    }

    function updateMap() {
        map.updateSource(sourceId, {"type": "geojson", "data": collection()});
    }

    // ---------------------------------------------------------- geometry

    function dist(lat1, lon1, lat2, lon2) {
        var p = Math.PI / 180;
        var x = (lon2 - lon1) * p * Math.cos((lat1 + lat2) / 2 * p);
        var y = (lat2 - lat1) * p;
        return 6371000 * Math.sqrt(x * x + y * y);
    }

    function bearing(lat1, lon1, lat2, lon2) {
        var p = Math.PI / 180;
        var y = Math.sin((lon2 - lon1) * p) * Math.cos(lat2 * p);
        var x = Math.cos(lat1 * p) * Math.sin(lat2 * p) -
                Math.sin(lat1 * p) * Math.cos(lat2 * p) * Math.cos((lon2 - lon1) * p);
        return (Math.atan2(y, x) / p + 360) % 360;
    }
}
