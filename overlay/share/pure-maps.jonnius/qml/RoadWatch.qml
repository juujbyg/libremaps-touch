/* -*- coding: utf-8-unix -*-
 *
 * Road watch: open-data helpers for driving, from OpenStreetMap via Overpass.
 *  - the speed limit of the road you are on, from Valhalla (feeds the speed
 *    bubble and sign; only where OpenStreetMap has a maxspeed tag)
 *  - fixed speed cameras along the planned route (Alerts.qml shows them on
 *    the map and warns before each one)
 *
 * The current position (to Valhalla, for the limit) and the route outline
 * (to Overpass, for cameras) are sent to public OpenStreetMap servers, only
 * while navigating or following. Switch off in Preferences ("Road alerts").
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.0

Item {
    id: watch

    // limit of the road under us, m/s; 0 when unknown
    property real limit: 0
    property var  cameras: []          // [{lat, lon, maxspeed}], maxspeed in km/h or 0
    property string valhalla: "https://valhalla1.openstreetmap.de/trace_attributes"
    // public Overpass servers are slow and flaky; try them in turn
    property var servers: ["https://overpass.kumi.systems/api/interpreter",
                           "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
                           "https://overpass-api.de/api/interpreter"]

    property bool _driving: app.conf.roadAlerts && gps.coordinateValid &&
                            (app.mode === modes.navigate || app.mode === modes.followMe)
    property real _lastLat: 0
    property real _lastLon: 0
    property string _routeKey: ""

    // --- speed limit of the current road ---
    Timer {
        interval: 9000
        repeat: true
        running: watch._driving
        triggeredOnStart: true
        onTriggered: watch.fetchLimit()
    }
    on_DrivingChanged: if (!_driving) { limit = 0; _lastLat = 0; }

    function fetchLimit() {
        var lat = gps.coordinate.latitude, lon = gps.coordinate.longitude;
        if (!lat && !lon) return;
        if (!_lastLat) { _lastLat = lat; _lastLon = lon; return; }
        if (dist(lat, lon, _lastLat, _lastLon) < 12) return;
        var body = {
            "shape": [{"lat": _lastLat, "lon": _lastLon}, {"lat": lat, "lon": lon}],
            "costing": "auto",
            "shape_match": "map_snap",
            "filters": {"attributes": ["edge.speed_limit"], "action": "include"}
        };
        _lastLat = lat; _lastLon = lon;
        var x = new XMLHttpRequest();
        x.timeout = 8000;
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            if (x.status !== 200) return;       // keep the previous value on a failed snap
            try {
                var edges = JSON.parse(x.responseText).edges || [];
                var v = edges.length ? edges[edges.length - 1].speed_limit : null;
                watch.limit = (v && v > 0 && v < 200) ? v / 3.6 : 0;
            } catch (e) { console.log("RoadWatch: limit parse: " + e); }
        };
        x.open("POST", valhalla);
        x.setRequestHeader("Content-Type", "application/json");
        x.send(JSON.stringify(body));
    }

    // --- speed cameras along the route ---
    Connections {
        target: app.navigator
        onRouteChanged: routeDelay.restart()
    }
    Timer { id: routeDelay; interval: 1500; onTriggered: watch.fetchCameras() }

    function fetchCameras() {
        var r = app.navigator.route;
        if (!app.conf.roadAlerts || !r || r.length < 2) { cameras = []; return; }
        var s = 90, w = 180, n = -90, e = -180;
        for (var i = 0; i < r.length; ++i) {
            s = Math.min(s, r[i].latitude); n = Math.max(n, r[i].latitude);
            w = Math.min(w, r[i].longitude); e = Math.max(e, r[i].longitude);
        }
        var key = [s, w, n, e].map(function(v) { return v.toFixed(3); }).join(",");
        if (key === _routeKey) return;
        _routeKey = key;
        var pad = 0.002;
        var q = '[out:json][timeout:25];(node["highway"="speed_camera"](%1,%2,%3,%4);' +
                'node["enforcement"="maxspeed"](%1,%2,%3,%4););out;';
        q = q.arg(s - pad).arg(w - pad).arg(n + pad).arg(e + pad);
        request(q, function(res) {
            var found = [];
            for (var i = 0; res.elements && i < res.elements.length; ++i) {
                var c = res.elements[i];
                if (c.lat === undefined) continue;
                if (distanceToRoute(c.lat, c.lon) >= 40) continue;
                var dup = false;
                for (var j = 0; j < found.length; ++j)
                    if (dist(c.lat, c.lon, found[j].lat, found[j].lon) < 25) { dup = true; break; }
                var ms = c.tags && c.tags.maxspeed ? parseInt(c.tags.maxspeed) : 0;
                if (!dup) found.push({lat: c.lat, lon: c.lon, maxspeed: ms > 0 && ms < 200 ? ms : 0});
            }
            watch.cameras = found;
            if (found.length > 0)
                app.notification.flash(app.tr("%1 speed cameras on this route").arg(found.length), "cams", 6);
        }, 45000);
    }

    function distanceToRoute(lat, lon) {
        var r = app.navigator.route, best = 1e9;
        for (var i = 0; i < r.length; ++i) {
            var d = dist(lat, lon, r[i].latitude, r[i].longitude);
            if (d < best) best = d;
        }
        return best;
    }

    function dist(lat1, lon1, lat2, lon2) {
        var R = 6371000, p = Math.PI / 180;
        var dLat = (lat2 - lat1) * p, dLon = (lon2 - lon1) * p;
        var a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(lat1 * p) * Math.cos(lat2 * p) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
        return 2 * R * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }

    function request(query, onDone, timeoutMs, idx) {
        idx = idx || 0;
        if (idx >= servers.length) { console.log("RoadWatch: all Overpass servers failed"); return; }
        var x = new XMLHttpRequest();
        x.timeout = timeoutMs || 40000;
        x.onreadystatechange = function() {
            if (x.readyState !== XMLHttpRequest.DONE) return;
            if (x.status !== 200) { watch.request(query, onDone, timeoutMs, idx + 1); return; }
            try { onDone(JSON.parse(x.responseText)); }
            catch (e) { console.log("RoadWatch: bad reply: " + e); }
        };
        x.open("POST", servers[idx]);
        x.setRequestHeader("Content-Type", "application/x-www-form-urlencoded");
        x.send("data=" + encodeURIComponent(query));
    }
}
