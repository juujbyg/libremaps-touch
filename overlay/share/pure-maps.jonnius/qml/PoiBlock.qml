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
import QtPositioning 5.4
import "."
import "platform"

// POI information shown in a panel under the map
Column {
    id: item
    anchors.left: parent.left
    anchors.right: parent.right
    height: visible ? implicitHeight : 0
    visible: false

    // properties of the item
    property bool  active: false
    property bool  navigationControls: false

    // poi properties
    property string address
    property bool   bookmarked: false
    property var    coordinate
    property string email
    property string link
    property string phone
    property string poiId
    property string poiType
    property string postcode
    property bool   shortlisted: false
    property string text
    property string title
    property var    poi

    // internal properties
    property bool  _fullMode: true
    property bool  _multipleIntermediatePossible: {
        if (!navigator.hasDestination) return false;
        if (navigator.hasOrigin)
            return navigator.locations.length > 2;
        return navigator.locations.length > 1;
    }
    property alias _optionalHeight: optional.height

    property var    poiAsRoutingDestination: {
        "text": title,
        "x": coordinate ? coordinate.longitude : 0,
        "y": coordinate ? coordinate.latitude : 0,
        "destination": true
    }
    property var    poiAsRoutingOrigin: {
        "text": title,
        "x": coordinate ? coordinate.longitude : 0,
        "y": coordinate ? coordinate.latitude : 0,
        "origin": true
    }

    // LibreMaps: Waze-style place sheet. Name, chips, address, action tiles,
    // fuel prices where the country publishes them, and one big "View routes" button.
    property real   u: styler.themePaddingMedium
    property real   margin: styler.themeHorizontalPageMargin
    property var    extra: null           // from poor.placeinfo.lookup
    property bool   moreOpen: false
    property string _extraFor: ""
    readonly property string phoneNumber: item.phone || (extra && extra.phone) || ""
    readonly property string website: item.link || (extra && extra.website) || ""
    readonly property string distanceText: {
        if (!gps.coordinateValid || !item.coordinate || !item.coordinate.isValid) return "";
        var d = gps.coordinate.distanceTo(item.coordinate);
        if (!(d >= 0)) return "";
        // one decimal between 1 and 10 km ("1.4 km away"), as Waze does
        var t = d >= 1000 && d < 10000 && (!app.conf.units || app.conf.units === "metric") ?
                    app.tr("%1 km").arg((Math.round(d / 100) / 10).toFixed(1).replace(".", Qt.locale().decimalPoint)) :
                    py.call_sync("poor.util.format_distance", [d, 2]);
        return app.tr("%1 away").arg(t);
    }
    readonly property string hoursText: {
        var h = extra ? extra.hours : null;
        if (!h) return "";
        if (h.state === "always") return app.tr("Open 24 hours");
        if (h.state === "open") return h.time ? app.tr("Open until %1").arg(h.time) : app.tr("Open");
        if (h.day === -1) return app.tr("Closed · opens %1").arg(h.time);
        if (h.day === -2) return app.tr("Closed · opens tomorrow %1").arg(h.time);
        return app.tr("Closed · opens %1 %2").arg(Qt.locale().dayName((h.day + 1) % 7, Locale.ShortFormat)).arg(h.time);
    }

    Text {
        // title
        color: styler.ink
        font.family: styler.themeFontFamily
        font.pixelSize: Math.round(item.u * 2.6)
        font.weight: Font.DemiBold
        lineHeight: 1.05
        maximumLineCount: 2
        elide: Text.ElideRight
        text: item.title
        width: parent.width - 2 * item.margin
        wrapMode: Text.WordWrap
        x: item.margin
    }

    Item { height: item.u * 0.8; width: 1 }

    Column {
        id: optional
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: item.u * 0.8
        visible: _fullMode

        Flow {
            // Open 24 hours · Fuel station · 1.0 km away
            spacing: item.u * 0.6
            width: parent.width - 2 * item.margin
            x: item.margin
            // test the texts: a chip's visible is false while this Flow is hidden
            visible: !!(item.hoursText || item.poiType || item.distanceText)

            PlaceChip {
                id: hoursChip
                color: !item.extra || !item.extra.hours ? styler.subtle :
                       item.extra.hours.state === "closed" ? styler.badBg : styler.okBg
                text: item.hoursText
                textColor: item.extra && item.extra.hours && item.extra.hours.state === "closed" ? styler.badText : styler.okText
            }
            PlaceChip {
                id: typeChip
                text: item.poiType
                textColor: styler.inkSoft
            }
            PlaceChip {
                id: distChip
                color: styler.primary
                text: item.distanceText
                textColor: styler.primaryText
            }
        }

        Text {
            color: styler.muted
            font.family: styler.themeFontFamily
            font.pixelSize: Math.round(item.u * 1.45)
            lineHeight: 1.1
            text: [item.address, item.postcode && item.address.indexOf(item.postcode) < 0 ? item.postcode : ""]
                    .filter(function (s) { return s; }).join(", ")
            visible: text.length > 0
            width: parent.width - 2 * item.margin
            wrapMode: Text.WordWrap
            x: item.margin
        }

        Text {
            id: textItem
            color: styler.inkSoft
            elide: Text.ElideRight
            font.family: styler.themeFontFamily
            font.pixelSize: Math.round(item.u * 1.3)
            maximumLineCount: app.portrait ? 3 : 1
            text: item.text
            visible: text.length > 0
            width: parent.width - 2 * item.margin
            wrapMode: Text.WordWrap
            x: item.margin
        }
    }

    Item { height: item.u * 1.6; width: 1 }

    Row {
        id: buttonRow
        spacing: item.u * 0.8
        visible: !navigationControls
        x: item.margin

        property real tileWidth: (item.width - 2 * item.margin - 3 * spacing) / 4

        PlaceTile {
            enabled: item.active
            icon: item.bookmarked ? "bookmark-check" : "bookmark"
            label: item.bookmarked ? app.tr("Saved") : app.tr("Save")
            width: buttonRow.tileWidth
            onClicked: {
                item.bookmarked = !item.bookmarked;
                pois.bookmark(item.poiId, item.bookmarked);
            }
        }

        PlaceTile {
            enabled: !!item.phoneNumber || !!item.website
            icon: item.phoneNumber || !item.website ? "phone" : "globe"
            label: item.phoneNumber || !item.website ? app.tr("Call") : app.tr("Website")
            width: buttonRow.tileWidth
            onClicked: {
                if (item.phoneNumber)
                    Qt.openUrlExternally("tel:" + item.phoneNumber.split(";")[0].replace(/[^0-9+]/g, ""));
                else if (item.website)
                    Qt.openUrlExternally(item.website.indexOf("://") > 0 ? item.website : "https://" + item.website);
            }
        }

        PlaceTile {
            enabled: item.coordinate !== undefined
            icon: "share"
            label: app.tr("Share")
            width: buttonRow.tileWidth
            onClicked: app.push(Qt.resolvedUrl("SharePage.qml"), {
                                    "coordinate": item.coordinate,
                                    "title": item.title,
                                    "poi": item.poi
                                })
        }

        PlaceTile {
            icon: "ellipsis"
            label: app.tr("More")
            width: buttonRow.tileWidth
            onClicked: item.moreOpen = !item.moreOpen
        }
    }

    Column {
        // what More opens: the rarer actions of the old icon row
        id: moreList
        anchors.left: parent.left
        anchors.right: parent.right
        topPadding: item.u * 0.6
        visible: item.moreOpen && !navigationControls

        Repeater {
            model: {
                var m = [{"id": "info", "icon": "info", "label": app.tr("Details")},
                         {"id": "nearby", "icon": "map-pin", "label": app.tr("Search nearby")}];
                if (navigator.hasDestination || navigator.hasOrigin)
                    m.push({"id": "route", "icon": "route", "label": app.tr("Add to the current route")});
                if (item.website && item.phoneNumber)
                    m.push({"id": "web", "icon": "globe", "label": app.tr("Website")});
                if (item.active)
                    m.push({"id": "remove", "icon": "trash", "label": app.tr("Remove from map")});
                return m;
            }
            delegate: Rectangle {
                color: rowMouse.pressed ? styler.subtle : "transparent"
                height: Math.round(item.u * 4.6)
                width: moreList.width

                Image {
                    id: rowIcon
                    anchors.verticalCenter: parent.verticalCenter
                    height: Math.round(item.u * 2.1)
                    smooth: true
                    source: (styler.icon(modelData.icon, modelData.id === "remove" ? "danger" : ""))
                    sourceSize.height: height * 2
                    sourceSize.width: height * 2
                    width: height
                    x: item.margin
                }
                Text {
                    anchors.left: rowIcon.right
                    anchors.leftMargin: item.u * 1.2
                    anchors.verticalCenter: parent.verticalCenter
                    color: modelData.id === "remove" ? styler.danger : styler.ink
                    font.family: styler.themeFontFamily
                    font.pixelSize: Math.round(item.u * 1.5)
                    text: modelData.label
                }
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    onClicked: item.moreAction(modelData.id)
                }
            }
        }
    }

    Column {
        // fuel prices: the country's open data for the station at this place (poor/fuelprices.py)
        anchors.left: parent.left
        anchors.right: parent.right
        topPadding: item.u * 2
        spacing: item.u
        visible: !navigationControls && !!item.extra && item.extra.fuel.length > 0

        Row {
            spacing: item.u * 0.8
            x: item.margin

            Text {
                id: fuelTitle
                anchors.verticalCenter: parent.verticalCenter
                color: styler.ink
                font.family: styler.themeFontFamily
                font.pixelSize: Math.round(item.u * 1.75)
                font.weight: Font.DemiBold
                text: app.tr("Fuel prices (%1)").arg(item.extra && item.extra.fuel_unit ? item.extra.fuel_unit : "€/L")
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: styler.muted
                font.family: styler.themeFontFamily
                font.pixelSize: Math.round(item.u * 1.15)
                elide: Text.ElideRight
                width: Math.max(0, Math.min(implicitWidth, item.width - 2 * item.margin - fuelTitle.width - parent.spacing))
                // the country's open data source, and when the station last updated
                text: !item.extra ? "" : (item.extra.fuel_source || "") +
                      (item.extra.fuel_date ? " · " + item.extra.fuel_date : "")
            }
        }

        Flickable {
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: priceRow.width + 2 * item.margin
            flickableDirection: Flickable.HorizontalFlick
            height: priceRow.height
            width: parent.width

            Row {
                id: priceRow
                spacing: item.u * 0.8
                x: item.margin

                Repeater {
                    model: item.extra ? item.extra.fuel : []
                    delegate: Rectangle {
                        border.color: styler.border
                        border.width: 1
                        color: "transparent"
                        height: Math.round(item.u * 6.6)
                        radius: styler.radiusMd
                        width: Math.max(Math.round(item.u * 9), priceText.implicitWidth + item.u * 2.4)

                        Column {
                            anchors.centerIn: parent
                            spacing: item.u * 0.2
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                color: styler.muted
                                font.family: styler.themeFontFamily
                                font.pixelSize: Math.round(item.u * 1.3)
                                text: modelData.name
                            }
                            Text {
                                id: priceText
                                anchors.horizontalCenter: parent.horizontalCenter
                                color: styler.ink
                                font.family: styler.themeFontFamily
                                font.pixelSize: Math.round(item.u * 2.3)
                                font.weight: Font.DemiBold
                                text: modelData.price
                            }
                        }
                    }
                }
            }
        }
    }

    Item { height: item.u * 2; width: 1; visible: !navigationControls }

    Rectangle {
        // the main action: routes from here to the place
        id: routesButton
        color: routesMouse.pressed ? "#14b8e6" : styler.navSky
        height: Math.round(item.u * 5.6)
        radius: height / 2
        visible: !navigationControls
        width: parent.width - 2 * item.margin
        x: item.margin

        Accessible.name: routesLabel.text
        Accessible.role: Accessible.Button

        Text {
            id: routesLabel
            anchors.centerIn: parent
            color: styler.ink
            font.family: styler.themeFontFamily
            font.pixelSize: Math.round(item.u * 1.8)
            font.weight: Font.DemiBold
            text: app.tr("View routes")
        }
        MouseArea {
            id: routesMouse
            anchors.fill: parent
            onClicked: {
                if (item.coordinate === undefined) return;
                navigator.locations = [item.poiAsRoutingDestination];
                item.finalizeRouting();
            }
        }
    }

    Item { height: item.u * 1.2; width: 1; visible: !navigationControls }

    // Navigation controls
    SectionHeaderPL {
        text: navigator.hasDestination || navigator.hasOrigin ? app.tr("Set as or Replace") : app.tr("Set as")
        visible: navigationControls
    }

    Grid {
        id: gridRepl
        columns: landscape ? 2 : 1
        anchors.left: parent.left
        anchors.right: parent.right
        visible: navigationControls

        property int  availableHalfWidth: width/2
        property bool landscape: gdest.visible && gorig.visible &&
                                 gdest.minWidth < availableHalfWidth &&
                                 gorig.minWidth < availableHalfWidth
        property int  cellTextSpace: width/2 - styler.themeHorizontalPageMargin -
                                     styler.themePaddingLarge

        ListItemLabelActive {
            id: gorig
            contentHeight: styler.themeItemSizeSmall
            label: app.tr("Origin")
            labelX: gridRepl.landscape ? styler.themePaddingLarge +
                                         gridRepl.cellTextSpace/2 - labelImplicitWidth/2 :
                                         styler.themeHorizontalPageMargin
            width: Math.max(minWidth, gridRepl.width / 2)
            property int minWidth: labelImplicitWidth + styler.themeHorizontalPageMargin +
                                   styler.themePaddingLarge

            onClicked: {
                var loc = navigator.locations;
                if (navigator.hasOrigin) loc[0] = poiAsRoutingOrigin;
                else loc.splice(0, 0, poiAsRoutingOrigin);
                navigator.locations = loc;
                finalizeRouting();
            }
        }

        ListItemLabelActive {
            id: gdest
            contentHeight: styler.themeItemSizeSmall
            label: app.tr("Final destination")
            labelX: gridRepl.landscape ? styler.themeHorizontalPageMargin +
                                         gridRepl.cellTextSpace/2 - labelImplicitWidth/2 :
                                         styler.themeHorizontalPageMargin
            width: Math.max(minWidth, gridRepl.width / 2)
            property int minWidth: labelImplicitWidth + styler.themeHorizontalPageMargin +
                                   styler.themePaddingLarge

            onClicked: {
                var loc = navigator.locations;
                if (navigator.hasDestination) loc[loc.length-1] = poiAsRoutingDestination;
                else loc.push(poiAsRoutingDestination);
                navigator.locations = loc;
                finalizeRouting();
            }
        }
    }

    SectionHeaderPL {
        text: app.tr("Insert as")
        visible: navigationControls && (navigator.hasOrigin || navigator.hasDestination)
    }

    ListItemLabelActive {
        label: app.tr("New origin")
        labelX: styler.themeHorizontalPageMargin
        visible: navigationControls && navigator.hasOrigin
        onClicked: {
            var loc = navigator.locations;
            loc[0].destination = true;
            loc.splice(0, 0, poiAsRoutingOrigin);
            navigator.locations = loc;
            finalizeRouting();
        }
    }

    ListItemLabelActive {
        label: app.tr("New final destination")
        labelX: styler.themeHorizontalPageMargin
        visible: navigationControls && navigator.hasDestination
        onClicked: {
            var loc = navigator.locations;
            loc.push(poiAsRoutingDestination);
            navigator.locations = loc;
            finalizeRouting();
        }
    }

    ListItemLabelActive {
        label: app.tr("First intermediate destination")
        labelX: styler.themeHorizontalPageMargin
        visible: navigationControls && _multipleIntermediatePossible
        onClicked: {
            var loc = navigator.locations;
            var i = navigator.hasOrigin ? 1 : 0;
            loc.splice(i, 0, poiAsRoutingDestination);
            navigator.locations = loc;
            finalizeRouting();
        }
    }

    ListItemLabelActive {
        label: _multipleIntermediatePossible ? app.tr("Last intermediate destination") :
                                               app.tr("Intermediate destination")
        labelX: styler.themeHorizontalPageMargin
        visible: navigationControls && navigator.hasDestination
        onClicked: {
            var loc = navigator.locations;
            loc.splice(loc.length-1, 0, poiAsRoutingDestination);
            navigator.locations = loc;
            finalizeRouting();
        }
    }


    Connections {
        target: pois
        onPoiChanged: {
            if (!poiId || item.poiId !== poiId) return;
            item.show(pois.getById(poiId));
        }
    }

    Connections {
        target: map
        onHeightChanged: checkMode()
    }

    onHeightChanged: checkMode()
    on_OptionalHeightChanged: checkMode()

    function checkMode() {
        // check if we have space to show all information
        var h = item.height + 2*styler.themePaddingLarge;
        if (_fullMode && h > map.height)
            _fullMode = false;
        else if (!_fullMode && h + _optionalHeight < map.height)
            _fullMode = true;
    }

    Connections {
        target: py
        Component.onCompleted: py.setHandler("placeinfo.ready", function(key, result) {
            if (key === item._extraFor) item.extra = result;
        })
    }

    function moreAction(id) {
        item.moreOpen = false;
        if (id === "info")
            app.push(Qt.resolvedUrl("PoiInfoPage.qml"), {"active": active, "poi": item.poi});
        else if (id === "nearby" && coordinate !== undefined)
            app.showMenu(Qt.resolvedUrl("NearbyPage.qml"), {
                             "near": [coordinate.longitude, coordinate.latitude],
                             "nearText": title,
                         });
        else if (id === "route")
            navigationControls = true;
        else if (id === "web")
            Qt.openUrlExternally(item.website.indexOf("://") > 0 ? item.website : "https://" + item.website);
        else if (id === "remove" && coordinate !== undefined) {
            pois.remove(poiId, true);
            hide();
        }
    }

    function finalizeRouting() {
        if (navigator.hasDestination)
            navigator.findRoute( false, {"save": true, "fitToView": true} );
        pois.hide();
    }

    function hide() {
        item.visible = false;
        item.active = false;
        item.poiId = "";
        navigationControls = false;
        item.moreOpen = false;
        item.extra = null;
        item._extraFor = "";
        app.poiActive = false;
        map.setSelectedPoi()
    }

    function show(poi) {
        if (!poi) {
            hide();
            return;
        }
        app.poiActive = true;
        // fill poi data
        item.address = poi.address || "";
        item.bookmarked = poi.bookmarked || false;
        item.coordinate = poi.coordinate || QtPositioning.coordinate(poi.y, poi.x);
        item.email = poi.email || "";
        item.link = poi.link || "";
        item.phone = poi.phone || "";
        item.poiId = poi.poiId || "";
        item.poiType = poi.poiType || "";
        item.postcode = poi.postcode || "";
        item.shortlisted = poi.shortlisted || false;
        item.text = poi.text || "";
        item.title = poi.title || app.tr("Unnamed point");
        item.poi = poi;
        // fill item vars
        item.active = (item.poiId.length > 0);
        item.visible = true;
        // opening hours and fuel prices arrive later, for this place only
        var key = [item.coordinate.latitude, item.coordinate.longitude, item.title].join("|");
        if (key !== item._extraFor) {
            item._extraFor = key;
            item.extra = null;
            item.moreOpen = false;
            py.call("poor.placeinfo.request", [key, item.coordinate.longitude, item.coordinate.latitude,
                                               item.title, item.poiType, item.postcode], null);
        }
        map.setSelectedPoi(item.coordinate)
    }
}
