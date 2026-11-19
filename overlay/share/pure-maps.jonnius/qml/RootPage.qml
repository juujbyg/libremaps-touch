/* -*- coding: utf-8-unix -*-
 *
 * Copyright (C) 2018 Rinigus
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

import QtQuick 2.9
import org.puremaps 1.0
import "."
import "platform"

PageEmptyPL {
    id: page
    title: app.tr("Map")
    clip: true

    ApproxLocation { id: approxLocation }
    RoadWatch { id: roadWatch }
    Alerts { id: alertWatch }
    AlertBanner { id: alertBanner }
    ReportButton { id: reportButton }
    ReportSheet { id: reportSheet }
    AttributionButton { id: attributionButton }
    BasemapButton { id: basemapButton }
    CenterButton { id: centerButton }
    Compass { id: compass }
    DirectionsPanel { id: directionsPanel }
    DriveSpeed { id: driveSpeed }
    GeocodeButton { id: geocodeButton }
    Map {
        id: map
        accessToken: py.evaluate("poor.key.mapbox_key")
    }
    MenuButton { id: menuButton }
    Meters { id: meters }
    NavigateButton { id: navigateButton }
    NavigationButtonClear { id: navigationButtonClear }
    NavigationButtonStartPause { id: navigationButtonStartPause }
    NavigationCurrentBlock { id: navigationCurrent }
    NavigationOverviewBlock { id: navigationOverview }
    NavigationSign { id: navigationSign }
    NavigationSpeedBlock { id: navigationSpeed }
    Navigator { id: navigator }
    NorthArrow { id: northArrow }
    SearchBar { id: searchBar }
    Notification { id: notification }
    InfoPanel { id: infoPanel }
    PlaceButtons { id: placeButtons }

    Connections {
        // once a route is shown or driven, search results leave the map (saved places stay),
        // so old nearby pins don't litter the route like stray markers
        target: app
        onModeChanged: {
            if (app.mode === modes.exploreRoute || app.mode === modes.navigate)
                pois.clear(false);
        }
    }
    // System Back (Alt+Left from Lomiri Gestures, or a Back key) on the map screen:
    // close what's open, one step at a time. Pages pushed over the map have their
    // own Back in the header, so this is off while one shows (two shortcuts with
    // the same keys would both be ambiguous and neither would fire).
    Shortcut {
        enabled: app.pages.ps && app.pages.ps.currentItem === page
        sequences: ["Alt+Left", "Back"]
        onActivated: page.goBack()
    }

    function goBack() {
        if (offlineState.picking) {
            offlinePicker.close(false);
        } else if (reportSheet.open) {
            reportSheet.open = false;
        } else if (app.infoPanelOpen) {
            infoPanel.back();
        } else if (app.mode === modes.exploreRoute) {
            notification.flash(app.tr("Route removed"), "navigationClear");
            navigator.clearRoute();
        } else if (map.followPaused) {
            map.resumeFollow();
        }
        // while navigating or just browsing the map, Back does nothing: it
        // must never end a trip by accident
    }

    OfflineState { id: offlineState }
    OfflinePicker { id: offlinePicker }
    Poi { id: pois }
    RemorsePopupPL { id: remorse; z: 1000 }
    ScaleBar { id: scaleBar }
    SoundButton { id: soundButton }
    SpeedLimit { id: speedLimit }
    StreetName { id: streetName }
    ZoomLevel { id: zoomLevel }

    Item {
        id: referenceBlockBottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        height: page.height - _posBottomCenter
        width: 1
    }
    Item {
        id: referenceBlockBottomLeft
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        height: page.height - _posBottomLeft
        width: _itemBottom ? _itemBottom.marginExtraLeftSide : 1
    }
    Item {
        id: referenceBlockBottomRight
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        height: page.height - _posBottomRight
        width: _itemBottom ? _itemBottom.marginExtraRightSide : 1
    }
    Item {
        id: referenceBlockTop
        anchors.left: parent.left
        anchors.top: parent.top
        height: _posTopCenter
        width: 1
    }
    Item {
        id: referenceBlockTopLeft
        anchors.left: parent.left
        anchors.top: parent.top
        height: _posTopLeft
        width: _itemTop ? _itemTop.marginExtraLeftSide : 1
    }
    Item {
        id: referenceBlockTopRight
        anchors.right: parent.right
        anchors.top: parent.top
        height: navigationSpeed.visible ? navigationSpeed.height : _posTopRight
        width: navigationSpeed.visible ? navigationSpeed.width :
                                         (_itemTop ? _itemTop.marginExtraRightSide : 1)
    }

    // handling of overlays for navigation
    // used internally for positioning items that can be
    // anchored to. as it is for internal use, its defined
    // below all items - an exception for general code formatting
    property var _itemBottom: {
        if (navigationOverview.visible && navigationOverview.showAtBottom)
            return navigationOverview;
        return undefined;
    }
    property var _itemTop: {
        if (navigationCurrent.visible) return navigationCurrent;
        if (navigationOverview.visible && !navigationOverview.showAtBottom)
            return navigationOverview;
        return undefined;
    }
    property double _posBottomCenter: _itemBottom ? _itemBottom.y : page.height
    property double _posBottomLeft: _itemBottom ? _itemBottom.y - _itemBottom.marginExtraLeft : page.height
    property double _posBottomRight: _itemBottom ? _itemBottom.y - _itemBottom.marginExtraRight : page.height
    property double _posTopCenter: _itemTop ? _itemTop.y + _itemTop.height : 0
    property double _posTopLeft: _itemTop ? _itemTop.y + _itemTop.height + _itemTop.marginExtraLeft : 0
    property double _posTopRight: _itemTop ? _itemTop.y + _itemTop.height + _itemTop.marginExtraRight : 0

    Component.onCompleted: {
        app.infoPanel = infoPanel;
        app.map = map;
        app.navigator = navigator;
        app.notification = notification;
        app.pois = pois;
        app.offlineState = offlineState;
        app.remorse = remorse;
        // connect modal dialog properties
        app.modalDialogBasemap = Qt.binding(function () { return basemapButton.openMenu; });
    }

    onPageStatusActive: {
        if (!app.infoActive) app.stateId = "";
        // finish initialization after the root page is shown
        if (!app.initialized) {
            app.initialize();
            if (app.fontKeyMissing) app.showMenu();
        }
    }
}
