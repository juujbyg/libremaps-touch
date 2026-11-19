/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: offline maps state, shared by the Offline maps page and the area
 * picker over the map. It lives on the map page, so a download keeps reporting
 * after its page is closed.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.9

Item {
    id: state
    visible: false

    property string busyId: ""     // area being downloaded or removed ("overview" for the world map)
    property bool   removing: false
    property string phase: ""      // fonts, tiles, index, done
    property real   done: 0
    property real   total: 1
    property string error: ""
    property var    info: ({"regions": [], "size": 0, "overview": false})
    property bool   inUse: false   // the map is drawn from the offline file
    property bool   picking: false // choosing an area on the map

    readonly property bool busy: busyId !== ""
    readonly property real fraction: Math.min(1, done / Math.max(1, total))

    function refresh() {
        info = py.evaluate("poor.offline.status()");
        inUse = py.evaluate("poor.offline.in_use()");
    }

    // areas saved before offline search and routes existed get them now
    function indexIfNeeded() {
        if (busy || !py.evaluate("poor.offline.index_pending()")) return;
        start("index");
        phase = "index";
        py.call("poor.offline.reindex_async", []);
    }

    function mb(bytes) {
        var m = bytes / 1048576;
        return m >= 1024 ? app.tr("%1 GB").arg((m / 1024).toFixed(1)) : app.tr("%1 MB").arg(Math.round(m));
    }

    function start(rid) {
        error = ""; phase = "fonts"; done = 0; total = 1;
        busyId = rid;
        removing = false;
    }

    function downloadArea(bbox) {
        start("new");
        py.call("poor.offline.add_and_download_async", [bbox], function(rid) {
            if (rid && state.busyId === "new") state.busyId = rid;
            state.refresh();
        });
    }

    function downloadOverview() {
        start("overview");
        py.call("poor.offline.download_async", ["overview"]);
    }

    function resume(rid) {
        start(rid);
        py.call("poor.offline.download_async", [rid]);
    }

    function remove(rid) {
        error = "";
        busyId = rid;
        removing = true;
        py.call("poor.offline.remove_async", [rid]);
    }

    function cancel() {
        py.call("poor.offline.cancel", []);
    }

    function use(on) {
        py.call("poor.offline.use", [on], function(now) { state.inUse = now; });
    }

    // the visible part of the map as [west, south, east, north]
    function viewBbox() {
        var c = map.center;
        var mpp = map.metersPerPixel;
        var halfW = map.width / 2 * mpp, halfH = map.height / 2 * mpp;
        if (Math.abs(map.bearing) > 1) {
            // rotated: take the circle around the screen
            halfW = halfH = Math.sqrt(halfW * halfW + halfH * halfH);
        }
        var dLat = halfH / 111320;
        var dLon = halfW / (111320 * Math.max(0.05, Math.cos(c.latitude * Math.PI / 180)));
        return [c.longitude - dLon, c.latitude - dLat, c.longitude + dLon, c.latitude + dLat];
    }

    // wait for the map to settle after start before the heavy work
    Timer {
        id: indexTimer
        interval: 15000
        onTriggered: state.indexIfNeeded()
    }

    Component.onCompleted: {
        if (py.ready) { refresh(); indexTimer.start(); }
        py.setHandler("offline.progress", function(phase, d, t) {
            state.phase = phase; state.done = d; state.total = t;
        });
        py.setHandler("offline.finished", function(rid, err) {
            var wasRemoving = state.removing;
            state.busyId = "";
            state.removing = false;
            state.error = err === "cancelled" ? "" : err;
            state.refresh();
            if (!err && rid === "index")
                notification.flash(app.tr("Offline search and routes are ready"), "offline");
            else if (!err && !wasRemoving)
                notification.flash(app.tr("Offline map saved"), "offline");
            if (wasRemoving && state.inUse && state.info.regions.length === 0) state.use(false);
        });
    }

    Connections {
        target: py
        onReadyChanged: if (py.ready) { state.refresh(); indexTimer.start(); }
    }
}
