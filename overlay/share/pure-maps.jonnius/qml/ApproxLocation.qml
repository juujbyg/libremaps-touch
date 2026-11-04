/* -*- coding: utf-8-unix -*-
 *
 * Keeps the app usable while the satellites give no position (indoors, cold
 * start; this phone has no assisted GPS). Without a position, "navigate here"
 * and routing from "Current position" simply fail.
 *
 * Until a real GPS fix arrives, the app is given the last position we ever
 * had, or, failing that, a rough one from the network (city level). A
 * separate watcher on the location service hands control back to the real GPS
 * the moment a fix shows up. Switch it off in Preferences.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.0
import QtPositioning 5.4

Item {
    id: approx

    property bool active: false      // currently feeding an approximate position
    property bool realFix: false     // a satellite fix has been seen this session
    property bool tried: false
    property real _lastSave: 0

    // independent look at the location service, to notice real fixes
    PositionSource {
        id: watcher
        active: app.running
        updateInterval: 3000
        onPositionChanged: {
            var c = position.coordinate;
            if (!c.isValid) return;
            if (position.horizontalAccuracyValid && position.horizontalAccuracy > 500) return;
            approx.realFix = true;
            if (approx.active) approx.stop();
            var now = Date.now();
            if (now - approx._lastSave > 60000) {
                approx._lastSave = now;
                app.conf.set("last_position", [c.longitude, c.latitude]);
            }
        }
    }

    Timer {
        interval: 6000
        repeat: false
        running: app.initialized && app.conf.approxLocation && !approx.realFix && !approx.tried
        onTriggered: approx.start()
    }

    function start() {
        tried = true;
        if (realFix) return;
        var last = py.evaluate("poor.conf.last_position");
        if (last && last.length === 2 && last[0] && last[1]) {
            use(last[0], last[1], app.tr("No GPS fix yet. Using your last known position."));
            return;
        }
        var xhr = new XMLHttpRequest();
        xhr.timeout = 10000;
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || approx.realFix) return;
            try {
                var r = JSON.parse(xhr.responseText);
                if (r.success === false || !r.latitude || !r.longitude) return;
                approx.use(r.longitude, r.latitude,
                           app.tr("No GPS fix yet. Using your approximate position from the network."));
            } catch (e) {
                console.log("Approximate location failed: " + e);
            }
        };
        xhr.open("GET", "https://ipwho.is/?fields=success,latitude,longitude");
        xhr.send();
    }

    function use(x, y, message) {
        if (realFix) return;
        active = true;
        gps.testingMode = true;
        gps.testingCoordinate = QtPositioning.coordinate(y, x);
        if (app.mode === modes.explore) {
            app.map.setCenter(x, y);
            app.map.zoomLevel = 13;
        }
        app.notification.flash(message, "approxloc", 10);
    }

    function stop() {
        active = false;
        gps.testingMode = Qt.binding(function() { return app.conf.developmentCoordinateCenter; });
        gps.testingCoordinate = app.map.center;
        app.notification.flash(app.tr("GPS fix acquired"), "approxloc", 4);
    }
}
