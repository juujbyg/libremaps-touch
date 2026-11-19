/* -*- coding: utf-8-unix -*-
 *
 * Copyright (C) 2014 Osmo Salomaa, 2018 Rinigus
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
import MapboxMap 1.0
import "."

import "js/util.js" as Util

MapboxMap {
    id: map
    anchors.fill: parent
    cacheDatabaseDefaultPath: true
    cacheDatabaseStoreSettings: false
    center: QtPositioning.coordinate(49, 13)
    metersPerPixelTolerance: Math.max(0.001, metersPerPixel*0.01) // 1 percent from the current value
    pitch: {
        if (app.mode === modes.explore || app.mode === modes.exploreRoute ||
                app.mode === modes.navigatePost ||
                format === "raster" || !map.autoRotate || !app.conf.tiltWhenNavigating) return 0;
        if (app.mode === modes.navigate) return 50;
        if (app.mode === modes.followMe) return 50;
        return 0; // should never get here
    }
    pixelRatio: styler.themePixelRatio * 1.5 * scale
    //useFBO: true
    zoomLevel: 4.0

    property int    animationTime: {
        if (!map.ready) return 0;
        if (app.mode === modes.explore || app.mode === modes.exploreRoute)
            return 1000;
        // support smooth animations for position marker
        // and map center only if GPS is accurate and
        // smooth animation is desired
        return (gps.accurate && app.conf.smoothPositionAnimationWhenNavigating ? gps.updateInterval : 0);
    }
    property bool   autoCenter: false
    property bool   autoRotate: false
    property bool   autoZoom: false
    property bool   cleanMode: app.conf.mapModeCleanOnStart
    property int    counter: 0
    property var    direction: {
        // check if we prefer to use compass
        if (app.conf.compassUse && compass.active) {
            if (app.mode === modes.explore || app.mode === modes.exploreRoute)
                return compass.azimuth;
            // navigation would prefer compass at low speed
            // and if it is for bycicle or pedestrian. speed
            // is already checked when activating compass, so
            // only route mode is needed
            if (app.transportMode === "foot" || app.transportMode === "bicycle")
                return compass.azimuth;
        }
        // direction as calculated along the route
        if (app.navigator.directionValid)
            return app.navigator.direction;
        if (gps.directionValid) return gps.direction;
        return undefined;
    }
    property string firstLabelLayer: ""
    property string firstRouteLayer: ""
    property string format: ""
    property string mapType: {
        if (app.mode === modes.exploreRoute) return "preview";
        else if (app.mode === modes.followMe || app.mode === modes.navigate || app.mode === modes.navigatePost)
            return "guidance";
        return "default";
    }
    property bool   ready: false
    property real   scale: {
        if (app.mode === modes.followMe ||
                app.mode === modes.navigate ||
                app.mode === modes.navigatePost) {
            return app.conf.mapScaleNavigation;
        }
        return app.conf.mapScale;
    }

    property bool   showNavButtons: false

    readonly property var images: QtObject {
        readonly property string locationDest:  "pure-image-location-dest"
        readonly property string locationEnd:   "pure-image-location-end"
        readonly property string locationStart: "pure-image-location-start"
        readonly property string locationWay:   "pure-image-location-way"
        readonly property string pixel:         "pure-image-pixel"
        readonly property string poi:           "pure-image-poi"
        readonly property string poiBookmarked: "pure-image-poi-bookmarked"
        readonly property string streetPill:    "libremaps-image-street-pill"
    }

    readonly property var layers: QtObject {
        readonly property string dummies:         "pure-layer-dummies"
        readonly property string locations:       "pure-layer-locations"
        readonly property string maneuvers:       "pure-layer-maneuvers-active"
        readonly property string nodes:           "pure-layer-maneuvers-passive"
        readonly property string pois:            "pure-layer-pois"
        readonly property string poisBookmarked:  "pure-layer-pois-bookmarked"
        readonly property string poisSelected:    "pure-layer-pois-selected"
        readonly property string route:           "pure-layer-route"
        readonly property string routeOutline:    "pure-layer-route-outline"
        readonly property string alternatives:    "libremaps-layer-alternatives"
        readonly property string alternativesCasing: "libremaps-layer-alternatives-casing"
        readonly property string streetLabels:    "libremaps-layer-street-labels"
        readonly property string streetLabelsLeft: "libremaps-layer-street-labels-left"
    }

    readonly property var sources: QtObject {
        readonly property string locations:      "pure-source-locations"
        readonly property string maneuvers:      "pure-source-maneuvers"
        readonly property string pois:           "pure-source-pois"
        readonly property string poisBookmarked: "pure-source-pois-bookmarked"
        readonly property string poisSelected:   "pure-source-pois-selected"
        readonly property string route:          "pure-source-route"
        readonly property string alternatives:   "libremaps-source-alternatives"
        readonly property string streetLabels:   "libremaps-source-street-labels"
        readonly property string streetLabelsLeft: "libremaps-source-street-labels-left"
    }

    Behavior on bearing {
        RotationAnimation {
            direction: RotationAnimation.Shortest
            duration: map.ready ? 500 : 0
            easing.type: Easing.Linear
        }
    }

    Behavior on center {
        CoordinateAnimation {
            duration: animationTime
            easing.type: app.mode === modes.explore || app.mode === modes.exploreRoute ? Easing.InOutQuad : Easing.Linear
        }
    }

    Behavior on margins {
        PropertyAnimation {
            duration: map.ready ? 500 : 0
            easing.type: Easing.InOutQuad
        }
    }

    Behavior on pitch {
        NumberAnimation {
            duration: map.ready ? 1000 : 0
            easing.type: Easing.Linear
        }
    }

    MapGestureArea {
        id: gestureArea
        integerZoomLevels: map.format === "raster"
        map: map
    }

    PositionMarker { id: positionMarker }

    Timer {
        // map view mode switch timer
        interval: app.conf.mapModeAutoSwitchTime > 0 ? app.conf.mapModeAutoSwitchTime*1000 : 1000
        repeat: true
        running: !cleanMode && app.conf.mapModeAutoSwitchTime > 0
        onTriggered: {
            if (!cleanMode && app.conf.mapModeAutoSwitchTime > 0)
                cleanMode = true;
        }
    }

    Timer {
        // navigation buttons switch timer
        id: navButtonsTimer
        interval: app.conf.mapModeAutoSwitchTime > 0 ? app.conf.mapModeAutoSwitchTime*1000 : 1000
        repeat: true
        running: map.showNavButtons && app.conf.mapModeAutoSwitchTime > 0
        onTriggered: {
            if (map.showNavButtons && app.conf.mapModeAutoSwitchTime > 0)
                map.showNavButtons = false;
        }
        property var conn: Connections {
            target: app
            onModeChanged: {
                if (app.mode === modes.navigate || app.mode === modes.exploreRoute)
                    map.showNavButtons = true;
                else
                    map.showNavButtons = false;

            }
        }
    }

    Timer {
        // auto zoom
        interval: 1000
        repeat: true
        running: map.autoZoom

        // keeping reference metersPerPixel and zoomLevel. Map does
        // update metersPerPixel with some tolerance to avoid too many
        // updates. So, for calculations, we have to keep reference zoom
        // level and metersPerPixel
        property real mpp: map.metersPerPixel
        property real zmref: map.zoomLevel

        onMppChanged: zmref = map.zoomLevel

        onTriggered: {
            if (!gps.speedValid) return;
            var dist = mpp * map.height;
            var speed = gps.speed;
            var newZoom = zmref;
            var zstep = 0.1;
            if (speed > 0) newZoom -= Math.log(speed*app.conf.mapZoomAutoTime / dist) / Math.log(2);
            else newZoom = app.conf.mapZoomAutoZeroSpeedZ;
            newZoom = Math.round(newZoom / zstep) * zstep;

            if (newZoom > app.conf.mapZoomAutoZeroSpeedZ) {
                if (map.zoomLevel < app.conf.mapZoomAutoZeroSpeedZ)
                    map.setZoomLevel(app.conf.mapZoomAutoZeroSpeedZ);
            } else if (Math.abs(map.zoomLevel - newZoom) > zstep*0.5)
                map.setZoomLevel(newZoom);
        }
    }

    Timer {
        // daytime bias timer
        interval: 1000*60
        repeat: true
        running: app.conf.basemapAutoLight==="sunrise/sunset" && gps.ready //false

        property bool lastLight: false

        Component.onCompleted: update(true)
        onRunningChanged: update(true)
        onTriggered: update()

        function update(force) {
            if (app.conf.basemapAutoLight!=="sunrise/sunset" || !gps.ready)
                return;
            py.call("poor.app.sun.day", [gps.coordinate.latitude,
                                         gps.coordinate.longitude],
                    function(light) {
                        if (force || lastLight !== light) {
                            py.call("poor.app.basemap.set_bias", [{'light': light ? 'day' : 'night'}]);
                            lastLight = light;
                        }
                    });
        }
    }

    Connections {
        target: app
        onModeChanged: setMode()
        onPortraitChanged: map.updateMargins()
        onTransportModeChanged: setBias()
    }

    Connections {
        target: gps
        onPositionUpdated: {
            map.autoCenter && map.centerOnPosition();
        }
    }

    Connections {
        target: infoPanel
        onHeightChanged: map.updateMargins()
    }

    Connections {
        target: menuButton
        onHeightChanged: map.updateMargins();
    }

    Connections {
        target: app.navigator
        onRouteChanged: {
            updateRoute();
            updateManeuvers();
        }
        onLocationsChanged: updateLocations()
        onStreetTagsChanged: updateStreetLabels()
        onAlternativesChanged: updateAlternatives()
        onAlternativeIndexChanged: updateAlternatives()
    }

    Connections {
        target: referenceBlockTop
        onHeightChanged: map.updateMargins();
    }

    Connections {
        target: directionsPanel
        onHeightChanged: map.updateMargins();
        onVisibleChanged: map.updateMargins();
    }

    Connections {
        target: referenceBlockBottom
        onHeightChanged: map.updateMargins();
    }

    Connections {
        target: pois
        onPoiChanged: map.updatePois()
    }

    Connections {
        target: py
        onBasemapChanged: map.setBasemap();
    }

    Connections {
        target: streetName
        onHeightChanged: map.updateMargins();
    }

    Component.onCompleted: {
        map.initSources();
        map.setStyleAdditions();
        map.initProperties();
        map.updatePois();
        map.updateMargins();
        map.updateRoute();
        map.updateManeuvers();
        map.updateLocations();
        map.updateAlternatives();
        map.setMode();
    }

    onAutoRotateChanged: {
        // Update map rotation to match travel direction.
        map.bearing = map.autoRotate && map.direction ? map.direction : 0;
        map.updateMargins();
    }

    onDirectionChanged: {
        // Update map rotation to match travel direction.
        var direction = map.direction || 0;
        if (map.autoRotate && Math.abs(direction - map.bearing) > 10)
            map.bearing = direction;
    }

    onErrorStringChanged: app.openMapErrorMessage(map.errorString)

    onHeightChanged: map.updateMargins();

    onMapToQtPixelRatioChanged: setStyleAdditions()

    onMapTypeChanged: setBias()

    onStyleJsonChanged: {
        py.call("poor.app.basemap.process_style", [styleJson],
                function (style) {
                    if (style) styleJson = style;
                });
    }

    function centerOnPosition() {
        // Center on the current position
        if (gps.coordinateValid)
            map.setCenter( gps.coordinate.longitude,
                           gps.coordinate.latitude );
    }

    function configureLayers() {
        // Configure layer for selected POI markers.
        // the open place: a soft red glow under the pin's tip
        map.setPaintProperty(map.layers.poisSelected, "circle-color", "#ef4444");
        map.setPaintProperty(map.layers.poisSelected, "circle-opacity", 0.25);
        map.setPaintProperty(map.layers.poisSelected, "circle-radius", 8 * map.mapToQtPixelRatio / map.devicePixelRatio * styler.themePixelRatio);
        map.setPaintProperty(map.layers.poisSelected, "circle-stroke-width", 0);
        // Configure layer for non-bookmarked POI markers.
        map.setLayoutProperty(map.layers.pois, "icon-allow-overlap", true);
        map.setLayoutProperty(map.layers.pois, "icon-anchor", "bottom");
        map.setLayoutProperty(map.layers.pois, "icon-image", map.images.poi);
        map.setLayoutProperty(map.layers.pois, "icon-size", 1.0 * map.mapToQtPixelRatio / map.devicePixelRatio );
        map.setLayoutProperty(map.layers.pois, "text-anchor", "top");
        map.setLayoutProperty(map.layers.pois, "text-field", "{name}");
        map.setLayoutProperty(map.layers.pois, "text-optional", true);
        map.setLayoutProperty(map.layers.pois, "text-font", '["Noto Sans Regular"]');
        map.setLayoutProperty(map.layers.pois, "text-size", 12);
        map.setPaintProperty(map.layers.pois, "text-color", styler.itemFg);
        map.setPaintProperty(map.layers.pois, "text-halo-color", styler.itemBg);
        map.setPaintProperty(map.layers.pois, "text-halo-width", 2);
        // Configure layer for bookmarked POI markers.
        map.setLayoutProperty(map.layers.poisBookmarked, "icon-allow-overlap", true);
        map.setLayoutProperty(map.layers.poisBookmarked, "icon-anchor", "bottom");
        map.setLayoutProperty(map.layers.poisBookmarked, "icon-image", map.images.poiBookmarked);
        map.setLayoutProperty(map.layers.poisBookmarked, "icon-size", 1.0 * map.mapToQtPixelRatio / map.devicePixelRatio );
        map.setLayoutProperty(map.layers.poisBookmarked, "text-anchor", "top");
        map.setLayoutProperty(map.layers.poisBookmarked, "text-field", "{name}");
        map.setLayoutProperty(map.layers.poisBookmarked, "text-optional", true);
        map.setLayoutProperty(map.layers.poisBookmarked, "text-font", '["Noto Sans Regular"]');
        map.setLayoutProperty(map.layers.poisBookmarked, "text-size", 12);
        map.setPaintProperty(map.layers.poisBookmarked, "text-color", styler.itemFg);
        map.setPaintProperty(map.layers.poisBookmarked, "text-halo-color", styler.itemBg);
        map.setPaintProperty(map.layers.poisBookmarked, "text-halo-width", 2);
        // Configure layer for route polyline.
        map.setLayoutProperty(map.layers.route, "line-cap", "round");
        map.setLayoutProperty(map.layers.route, "line-join", "round");
        map.setPaintProperty(map.layers.route, "line-color", styler.route);
        map.setPaintProperty(map.layers.route, "line-opacity", styler.routeOpacity);
        map.setPaintProperty(map.layers.route, "line-width", 20 * map.mapToQtPixelRatio);
        // Other routes while choosing one: grey, under the chosen route
        map.setLayoutProperty(map.layers.alternatives, "line-cap", "round");
        map.setLayoutProperty(map.layers.alternatives, "line-join", "round");
        map.setPaintProperty(map.layers.alternatives, "line-color", styler.dark ? "#71717a" : "#a1a1aa");
        map.setPaintProperty(map.layers.alternatives, "line-width", 12 * map.mapToQtPixelRatio);
        map.setLayoutProperty(map.layers.alternativesCasing, "line-cap", "round");
        map.setLayoutProperty(map.layers.alternativesCasing, "line-join", "round");
        map.setPaintProperty(map.layers.alternativesCasing, "line-color", styler.dark ? "#3f3f46" : "#71717a");
        map.setPaintProperty(map.layers.alternativesCasing, "line-width", 16 * map.mapToQtPixelRatio);
        // Configure layer for route casing.
        map.setLayoutProperty(map.layers.routeOutline, "line-cap", "round");
        map.setLayoutProperty(map.layers.routeOutline, "line-join", "round");
        map.setPaintProperty(map.layers.routeOutline, "line-color", styler.routeCasing || styler.route);
        map.setPaintProperty(map.layers.routeOutline, "line-gap-width", 20 * map.mapToQtPixelRatio);
        map.setPaintProperty(map.layers.routeOutline, "line-opacity", 1 - (1-styler.routeOpacity)/2);
        map.setPaintProperty(map.layers.routeOutline, "line-width", 3 * map.mapToQtPixelRatio);
        // Configure layer for street tags: white names on purple tags at the turns.
        // Two layers: tags to the right of their turn, and tags to the left of it for turns
        // near the right edge of the screen (see updateStreetLabels).
        map.configureStreetTags(map.layers.streetLabels, false);
        map.configureStreetTags(map.layers.streetLabelsLeft, true);
        // Configure layer for active maneuver markers.
        map.setPaintProperty(map.layers.maneuvers, "circle-color", styler.maneuver);
        map.setPaintProperty(map.layers.maneuvers, "circle-pitch-alignment", "map");
        map.setPaintProperty(map.layers.maneuvers, "circle-radius", 11 * map.mapToQtPixelRatio);
        map.setPaintProperty(map.layers.maneuvers, "circle-stroke-color", styler.route);
        map.setPaintProperty(map.layers.maneuvers, "circle-stroke-width", 4 * map.mapToQtPixelRatio);
        // Configure layer for passive maneuver markers.
        map.setPaintProperty(map.layers.nodes, "circle-color", styler.maneuver);
        map.setPaintProperty(map.layers.nodes, "circle-pitch-alignment", "map");
        map.setPaintProperty(map.layers.nodes, "circle-radius", 5 * map.mapToQtPixelRatio);
        map.setPaintProperty(map.layers.nodes, "circle-stroke-color", styler.route);
        map.setPaintProperty(map.layers.nodes, "circle-stroke-width", 3 * map.mapToQtPixelRatio);
        // Configure layer for dummy symbols that knock out road shields etc.
        map.setLayoutProperty(map.layers.dummies, "icon-image", map.images.pixel);
        map.setLayoutProperty(map.layers.dummies, "icon-padding", 15);
        map.setLayoutProperty(map.layers.dummies, "icon-rotation-alignment", "map");
        map.setLayoutProperty(map.layers.dummies, "visibility", "visible");
        // Configure layer for location markers.
        map.setLayoutProperty(map.layers.locations, "icon-allow-overlap", true);
        map.setLayoutProperty(map.layers.locations, "icon-anchor", "bottom");
        map.setLayoutProperty(map.layers.locations, "icon-image", "{symbol}");
        map.setLayoutProperty(map.layers.locations, "icon-size", 1.0 * map.mapToQtPixelRatio / map.devicePixelRatio );
        map.setLayoutProperty(map.layers.locations, "text-anchor", "top");
        map.setLayoutProperty(map.layers.locations, "text-field", "{name}");
        map.setLayoutProperty(map.layers.locations, "text-optional", true);
        map.setLayoutProperty(map.layers.locations, "text-font", '["Noto Sans Regular"]');
        map.setLayoutProperty(map.layers.locations, "text-size", 11);
        map.setPaintProperty(map.layers.locations, "text-color", styler.itemFg);
        map.setPaintProperty(map.layers.locations, "text-halo-color", styler.itemBg);
        map.setPaintProperty(map.layers.locations, "text-halo-width", 2);
    }

    function fitViewToPois(pois) {
        // Set center and zoom so that given POIs are visible.
        map.autoCenter = false;
        map.autoRotate = false;
        map.fitView(pois.map(function(poi) {
            return poi.coordinate || QtPositioning.coordinate(poi.y, poi.x);
        }), true);
    }

    function fitViewToRoute() {
        // Set center and zoom so that the whole route is visible.
        map.autoCenter = false;
        map.autoRotate = false;
        // fitView ignores the side margins and puts the route right on the
        // screen edges, so fit a box padded by 10% on every side instead.
        var route = app.navigator.route;
        if (!route || route.length < 2) {
            map.fitView(route, true);
            return;
        }
        var s = 90, n = -90, w = 180, e = -180;
        for (var i = 0; i < route.length; i++) {
            var c = route[i];
            s = Math.min(s, c.latitude); n = Math.max(n, c.latitude);
            w = Math.min(w, c.longitude); e = Math.max(e, c.longitude);
        }
        var dy = Math.max((n - s) * 0.1, 0.0005), dx = Math.max((e - w) * 0.1, 0.0005);
        map.fitView([QtPositioning.coordinate(s - dy, w - dx),
                      QtPositioning.coordinate(n + dy, e + dx)], true);
    }

    function initIcons() {
        var suffix = "";
        if (styler.position) suffix = "-" + styler.position;
        var iconSize = 35 * styler.themePixelRatio;
        // route ends as pins in the same family as the place pins: white start, dark
        // chequered finish, amber stops
        map.addImagePath(map.images.locationDest, Qt.resolvedUrl("icons/route-stop.svg"), iconSize * 1.1);
        map.addImagePath(map.images.locationEnd, Qt.resolvedUrl("icons/route-end.svg"), iconSize * 1.2);
        map.addImagePath(map.images.locationStart, Qt.resolvedUrl("icons/route-start.svg"), iconSize * 1.0);
        map.addImagePath(map.images.locationWay, Qt.resolvedUrl("icons/route-stop.svg"), iconSize * 0.9);
        // places: Waze-style filled pins, red, and amber once saved
        map.addImagePath(map.images.poi, Qt.resolvedUrl("icons/place-pin.svg"), iconSize * 1.2);
        map.addImagePath(map.images.poiBookmarked, Qt.resolvedUrl("icons/place-pin-saved.svg"), iconSize * 1.2);
        map.addImagePath(map.images.pixel, Qt.resolvedUrl("icons/pixel.png"));
        map.addImagePath(map.images.streetPill, Qt.resolvedUrl("icons/street-pill.svg"));
    }

    function initLayers() {
        // Initialize layers for POI markers, route polyline and maneuver markers.
        map.addLayer(map.layers.poisSelected, {"type": "circle", "source": map.sources.poisSelected});
        map.addLayer(map.layers.pois, {"type": "symbol", "source": map.sources.pois});
        map.addLayer(map.layers.poisBookmarked, {"type": "symbol", "source": map.sources.poisBookmarked});
        map.addLayer(map.layers.route, {"type": "line", "source": map.sources.route}, map.firstRouteLayer);
        // the other routes go under the chosen one
        map.addLayer(map.layers.alternativesCasing, {"type": "line", "source": map.sources.alternatives}, map.layers.route);
        map.addLayer(map.layers.alternatives, {"type": "line", "source": map.sources.alternatives}, map.layers.route);
        map.addLayer(map.layers.routeOutline, {"type": "line", "source": map.sources.route}, map.firstLabelLayer);
        map.addLayer(map.layers.maneuvers, {
                         "type": "circle",
                         "source": map.sources.maneuvers,
                         "filter": ["==", "name", "active"],
                     }, map.firstLabelLayer);
        map.addLayer(map.layers.nodes, {
                         "type": "circle",
                         "source": map.sources.maneuvers,
                         "filter": ["==", "name", "passive"],
                     }, map.firstLabelLayer);
        // Add transparent 1x1 pixels at maneuver points to knock out road shields etc.
        // that would otherwise overlap with the above maneuver and node circles.
        map.addLayer(map.layers.dummies, {"type": "symbol", "source": map.sources.maneuvers});
        // the left-side tags go below, so the map places them last: a flipped tag shows only
        // where it doesn't hide a neighbour (and a tag that won't fit either side isn't cut)
        map.addLayer(map.layers.streetLabelsLeft, {"type": "symbol", "source": map.sources.streetLabelsLeft});
        map.addLayer(map.layers.streetLabels, {"type": "symbol", "source": map.sources.streetLabels});
        map.addLayer(map.layers.locations, {"type": "symbol", "source": map.sources.locations});
    }

    function initProperties() {
        // Initialize map properties and restore saved overlays.
        map.setBasemap();
        map.setModeExplore();
        map.setZoomLevel(app.conf.get("zoom"));
        map.autoCenter = app.conf.get("auto_center");
        map.autoRotate = app.conf.get("auto_rotate");
        var center = app.conf.get("center");
        map.setCenter(center[0], center[1]);
        map.ready = true;
    }

    function initSources() {
        // Initialize sources for map overlays.
        map.addSourcePoints(map.sources.poisSelected, []);
        map.addSourcePoints(map.sources.pois, []);
        map.addSourcePoints(map.sources.poisBookmarked, []);
        map.addSourceLine(map.sources.route, []);
        //map.addSourcePoints(map.sources.locations, []);
        map.addSourcePoints(map.sources.maneuvers, []);
        map.addSourcePoints(map.sources.streetLabels, []);
        map.addSourcePoints(map.sources.streetLabelsLeft, []);
    }

    function setBasemap() {
        // Set the basemap to use and related properties.
        map.firstLabelLayer = py.evaluate("poor.app.basemap.first_label_layer");
        map.firstRouteLayer = py.evaluate("poor.app.basemap.first_route_layer");
        map.format = py.evaluate("poor.app.basemap.format");
        map.urlSuffix = py.evaluate("poor.app.basemap.url_suffix");
        var processed = py.call_sync("poor.app.basemap.process_style", []);
        if (processed) map.styleJson = processed;
        else {
            var url = py.evaluate("poor.app.basemap.style_url");
            if (url) map.styleUrl  = url;
            else map.styleJson = py.evaluate("poor.app.basemap.style_json");
        }
        attributionButton.logo = py.evaluate("poor.app.basemap.logo");
        styler.apply(py.evaluate("poor.app.basemap.style_gui"))
        map.setStyleAdditions();
    }

    function setBias() {
        py.call("poor.app.basemap.set_bias", [{'type': map.mapType,
                                                  'vehicle': app.transportMode}]);
    }

    function setCenter(x, y) {
        // Center on the given coordinates.
        if (!x || !y) return;
        map.center = QtPositioning.coordinate(y, x);
    }

    // Waze-style: dragging or pinching the map while it follows you pauses following,
    // so you can look around; it comes back 8 s after the last touch, or at once
    // with the centre button
    property bool followPaused: false

    onGestureInProgressChanged: {
        if (map.gestureInProgress) {
            resumeFollowTimer.stop();
            if (map.autoCenter && (app.mode === modes.navigate || app.mode === modes.followMe ||
                                   app.mode === modes.navigatePost)) {
                // switch these off first, so their own handlers don't flash a toast
                map.autoZoom = false;
                map.autoRotate = false;
                map.autoCenter = false;
                map.followPaused = true;
            }
        } else if (map.followPaused) {
            resumeFollowTimer.restart();
        }
    }

    Timer {
        id: resumeFollowTimer
        interval: 8000
        repeat: false
        onTriggered: map.resumeFollow()
    }

    function resumeFollow() {
        resumeFollowTimer.stop();
        if (!map.followPaused) return;
        map.followPaused = false;
        setMode();
    }

    function setMode() {
        resumeFollowTimer.stop();
        map.followPaused = false;
        if (app.mode === modes.explore) setModeExplore();
        else if (app.mode === modes.exploreRoute) setModeExploreRoute();
        else if (app.mode === modes.followMe) setModeFollowMe();
        else if (app.mode === modes.navigate) setModeNavigate();
        else if (app.mode === modes.navigatePost) setModeNavigatePost();
        else console.log("Something is terribly wrong - unknown mode in Map.setMode: " + app.mode);
    }

    function setModeExplore() {
        // map used to explore it
        if (app.conf.mapZoomAutoWhenNavigating) map.autoZoom = false;
        map.autoCenter = false;
        map.autoRotate = false;
        if (map.zoomLevel > 14) map.setZoomLevel(14);
    }

    function setModeExploreRoute() {
        // map used to explore it
        if (app.conf.mapZoomAutoWhenNavigating) map.autoZoom = false;
        map.autoCenter = false;
        map.autoRotate = false;
        if (map.zoomLevel > 14) map.setZoomLevel(14);
    }

    function setModeFollowMe() {
        // follow me mode
        var scale = app.conf.mapScaleNavigation;
        var zoom = 15 - (scale > 1 ? Math.log(scale)*Math.LOG2E : 0);
        if (map.zoomLevel < zoom) map.setZoomLevel(zoom);
        map.centerOnPosition();
        map.autoCenter = true;
        map.autoRotate = app.conf.autoRotateWhenNavigating;
        if (app.conf.mapZoomAutoWhenNavigating) map.autoZoom = true;
    }

    function setModeNavigate() {
        // map during navigation
        var scale = app.conf.mapScaleNavigation;
        var zoom = 15 - (scale > 1 ? Math.log(scale)*Math.LOG2E : 0);
        if (map.zoomLevel < zoom) map.setZoomLevel(zoom);
        map.centerOnPosition();
        map.autoCenter = true;
        map.autoRotate = app.conf.autoRotateWhenNavigating;
        if (app.conf.mapZoomAutoWhenNavigating) map.autoZoom = true;
    }

    function setModeNavigatePost() {
        // map after navigation in post mode
        var scale = app.conf.mapScaleNavigation;
        var zoom = 15 - (scale > 1 ? Math.log(scale)*Math.LOG2E : 0);
        if (map.zoomLevel < zoom) map.setZoomLevel(zoom);
        map.centerOnPosition();
        map.autoCenter = true;
        map.autoRotate = app.conf.autoRotateWhenNavigating;
        if (app.conf.mapZoomAutoWhenNavigating) map.autoZoom = true;
    }

    function setSelectedPoi(coordinate) {
        if (coordinate===undefined)
            map.updateSourcePoints(map.sources.poisSelected, []);
        else {
            map.updateSourcePoints(map.sources.poisSelected, [coordinate]);
            map.fitView([coordinate], true);
        }
    }

    function setStyleAdditions() {
        map.initIcons();
        map.initLayers();
        map.configureLayers();
        positionMarker.initIcons();
        positionMarker.configureLayers();
        if (typeof alertWatch !== "undefined" && alertWatch) alertWatch.initMap();
    }

    function _updateLocationsAddPoint(l, name, symbol) {
        // helper function for adding location points
        var p = {};
        p.type = "Feature";
        p.geometry = {"type": "Point", "coordinates": [l.x, l.y]};
        p.properties = {"name": name, "symbol": symbol };
        return p;
    }

    function updateLocations() {
        // Update location markers on the map.
        if (!app.navigator) return;
        var data = {};
        data.type = "FeatureCollection";
        data.features = []
        var locations = app.navigator.locations;
        var counter = 0;
        for (var i=0; i < locations.length; ++i) {
            var l = locations[i];
            // no start pin: the position marker already shows where the route begins
            if (l.origin) continue;
            var symbol;
            if (l.final)
                symbol = map.images.locationEnd;
            else if (l.destination)
                symbol = map.images.locationDest;
            else
                symbol = map.images.locationWay;

            // no "Origin"/"Final destination" captions: the pins say it; the finish shows
            // the place's own name when it has a short one
            var name;
            if (l.origin)
                name = "";
            else if (l.final)
                name = l.text && l.text.length <= 28 && !/^-?\d/.test(l.text) ? l.text : "";
            else if (l.arrived)
                name = app.tr("✓");
            else {
                counter = counter + 1;
                name = app.tr("#%1", counter);
            }

            data.features.push(_updateLocationsAddPoint(l, name, symbol));
        }

        map.updateSource(map.sources.locations,
                         { "type": "geojson", "data": data });
    }

    function updateManeuvers() {
        // Update maneuver marker on the map.
        if (!app.navigator) return;
        var coords = app.navigator.maneuvers.coordinates();
        var names  = app.navigator.maneuvers.names();
        map.updateSourcePoints(map.sources.maneuvers, coords, names);
        map.updateStreetLabels();
    }

    function streetTagSize() {
        // the map draws twice as big while navigating; keep the tags readable but small
        return (map.scale > 1 ? 8.5 : 9) / Math.max(1, map.scale);
    }

    onScaleChanged: {
        map.setLayoutProperty(map.layers.streetLabels, "text-size", map.streetTagSize());
        map.setLayoutProperty(map.layers.streetLabelsLeft, "text-size", map.streetTagSize());
    }

    function configureStreetTags(layer, toLeft) {
        // white street names on purple tags, beside the turn point
        var anchor = toLeft ? "bottom-right" : "bottom-left";
        map.setLayoutProperty(layer, "icon-image", map.images.streetPill);
        map.setLayoutProperty(layer, "icon-text-fit", "both");
        map.setLayoutProperty(layer, "icon-text-fit-padding", "[3, 6, 3, 6]");  // arrays go as JSON text
        map.setLayoutProperty(layer, "icon-anchor", anchor);
        map.setLayoutProperty(layer, "text-anchor", anchor);
        map.setLayoutProperty(layer, "text-offset", toLeft ? "[-0.6, -0.5]" : "[0.6, -0.5]");
        map.setLayoutProperty(layer, "icon-offset", "[0, 0]");
        map.setLayoutProperty(layer, "text-field", "{name}");
        map.setLayoutProperty(layer, "text-font", '["Noto Sans Regular"]');
        map.setLayoutProperty(layer, "text-size", map.streetTagSize());
        map.setLayoutProperty(layer, "text-max-width", 30);
        map.setPaintProperty(layer, "text-color", "#ffffff");
    }

    // the map moved: tags may now fit better on the other side of their turn
    onCenterChanged: if (app.navigator && app.navigator.streetTags.length) tagSides.restart()
    onZoomLevelChanged: if (app.navigator && app.navigator.streetTags.length) tagSides.restart()
    onBearingChanged: if (app.navigator && app.navigator.streetTags.length) tagSides.restart()
    property var _tagSides: Timer {
        id: tagSides
        interval: 300
        onTriggered: map.updateStreetLabels()
    }

    function updateStreetLabels() {
        // Purple tags with the names of the streets the route turns onto (Waze style). A tag
        // goes right of its turn, or left of it when it would run off the right edge. The
        // map can't tell where a coordinate lands on screen, so project it here (flat, from
        // the centre, metres per pixel and bearing; good enough to pick a side).
        var tags = app.navigator ? app.navigator.streetTags : [];
        var right = {"coords": [], "names": []}, left = {"coords": [], "names": []};
        var mpp = map.metersPerPixel > 0 ? map.metersPerPixel : 1;
        var b = map.bearing * Math.PI / 180;
        var lat0 = map.center.latitude, lon0 = map.center.longitude;
        var cx = map.width * (map.margins ? (map.margins.left + map.margins.right) / 2 : 0.5);
        var charPx = map.streetTagSize() / Math.max(0.01, map.mapToQtPixelRatio) * 0.47;
        for (var i = 0; i < tags.length; i++) {
            var dE = (tags[i].x - lon0) * 111320 * Math.cos(lat0 * Math.PI / 180);
            var dN = (tags[i].y - lat0) * 110540;
            var x = cx + (dE * Math.cos(b) - dN * Math.sin(b)) / mpp;
            var w = (String(tags[i].name).length + 2) * charPx;  // measured: ~387 px for 18 letters
            var side = (x + w < map.width - 8 || x - w < 8 && map.width - x > x) ? right : left;
            side.coords.push(QtPositioning.coordinate(tags[i].y, tags[i].x));
            side.names.push(tags[i].name);
        }
        map.updateSourcePoints(map.sources.streetLabels, right.coords, right.names);
        map.updateSourcePoints(map.sources.streetLabelsLeft, left.coords, left.names);
    }

    function updateMargins() {
        // Calculate new margins and set them for the map.
        if (map.height <= 0) return;
        var header = referenceBlockTop.height > 0 ? referenceBlockTop.height : map.height*0.05;
        if (directionsPanel && directionsPanel.visible)
            header = Math.max(header, directionsPanel.height + 6 * styler.themePaddingLarge);
        var footer = !app.infoPanelOpen && (app.mode === modes.explore || app.mode === modes.exploreRoute) && menuButton ? menuButton.height + menuButton.anchors.bottomMargin : 0;
        footer += !app.infoPanelOpen && (app.mode === modes.navigate || app.mode === modes.navigatePost || app.mode === modes.followMe) && referenceBlockBottom ? referenceBlockBottom.height : 0;
        footer += !app.infoPanelOpen && (app.mode === modes.navigate || app.mode === modes.navigatePost || app.mode === modes.followMe) && streetName ? streetName.height : 0
        footer += app.infoPanelOpen && infoPanel ? infoPanel.height : 0
        footer = Math.min(footer, map.height / 2.0);

        // If auto-rotate is on, the user is always heading up
        // on the screen and should see more ahead than behind.
        var marginY = (footer*1.0)/map.height;
        var marginHeight = (map.autoRotate ? 0.2 : 1.0) * (1.0*(map.height - header - footer)) / map.height;
        map.margins = Qt.rect(0.05, marginY, 0.9, marginHeight);
    }

    function updatePois() {
        // Update POI markers on the map.
        var regCoor = [];
        var regName = [];
        var bookmarkedCoor = [];
        var bookmarkedName = [];
        for (var i = 0; i < pois.pois.length; i++) {
            if (pois.pois[i].bookmarked) {
                bookmarkedCoor.push(pois.pois[i].coordinate);
                bookmarkedName.push(pois.pois[i].title);
            } else {
                regCoor.push(pois.pois[i].coordinate);
                regName.push(pois.pois[i].title);
            }
        }
        map.updateSourcePoints(map.sources.pois, regCoor, regName);
        map.updateSourcePoints(map.sources.poisBookmarked, bookmarkedCoor, bookmarkedName);
    }

    function updateAlternatives() {
        // grey lines for the routes not chosen
        var nav = app.navigator;
        var data = {"type": "FeatureCollection", "features": []};
        if (nav && nav.alternatives) {
            for (var i = 0; i < nav.alternatives.length; i++) {
                if (i === nav.alternativeIndex) continue;
                var r = nav.alternatives[i];
                var coords = [];
                // every other point is plenty for a grey preview line
                for (var j = 0; j < r.x.length; j += 2) coords.push([r.x[j], r.y[j]]);
                coords.push([r.x[r.x.length - 1], r.y[r.y.length - 1]]);
                data.features.push({"type": "Feature",
                                    "properties": {"index": i},
                                    "geometry": {"type": "LineString", "coordinates": coords}});
            }
        }
        map.updateSource(map.sources.alternatives, {"type": "geojson", "data": data});
    }

    function updateRoute() {
        // Update route polyline on the map.
        if (app.navigator && app.navigator.route && app.navigator.route.length > 0)
            map.updateSourceLine(map.sources.route, app.navigator.route);
        else
            map.updateSourcePoints(map.sources.route, [], []);
    }

}
