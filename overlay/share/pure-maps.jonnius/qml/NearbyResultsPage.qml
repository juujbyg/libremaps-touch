/* -*- coding: utf-8-unix -*-
 *
 * Copyright (C) 2014 Osmo Salomaa, 2018 Rinigus
 * LibreMaps: rows with a category icon, distance first, and only the place the
 * user picks gets a pin on the map ("Show all on map" in the menu puts them all).
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
import "."
import "platform"

import "js/util.js" as Util

PageListPL {
    id: page
    background: Rectangle { color: styler.cream }

    delegate: ListItemPL {
        id: listItem
        contentHeight: textCol.height + 2 * page.u * 1.4

        Rectangle {
            id: catTile
            anchors.left: parent.left
            anchors.leftMargin: page.margin
            anchors.verticalCenter: parent.verticalCenter
            color: styler.subtle
            height: styler.themeItemSizeSmall * 0.78
            radius: styler.radiusLg
            width: height
            Image {
                anchors.centerIn: parent
                height: parent.height * 0.48
                smooth: true
                source: styler.icon(page.iconName)
                sourceSize.height: height * 2
                sourceSize.width: width * 2
                width: height
            }
        }

        Column {
            id: textCol
            anchors.left: catTile.right
            anchors.leftMargin: page.u * 1.4
            anchors.right: chevron.left
            anchors.rightMargin: page.u
            anchors.verticalCenter: parent.verticalCenter
            spacing: page.u * 0.3

            Text {
                color: styler.ink
                elide: Text.ElideRight
                font.family: styler.themeFontFamily
                font.pixelSize: styler.themeFontSizeMedium
                font.weight: Font.Medium
                text: model.title
                width: parent.width
            }
            Text {
                color: styler.muted
                elide: Text.ElideRight
                font.family: styler.themeFontFamily
                font.pixelSize: styler.themeFontSizeSmall
                text: [model.distance, model.description].filter(function (s) { return !!s; }).join(" · ")
                width: parent.width
            }
            Text {
                color: styler.muted
                elide: Text.ElideRight
                font.family: styler.themeFontFamily
                font.pixelSize: styler.themeFontSizeExtraSmall
                text: model.address || ""
                visible: text.length > 0
                width: parent.width
            }
        }

        Image {
            id: chevron
            anchors.right: parent.right
            anchors.rightMargin: page.margin
            anchors.verticalCenter: parent.verticalCenter
            height: styler.themeItemSizeSmall * 0.3
            smooth: true
            source: styler.icon("chevron-right", "muted")
            sourceSize.height: height * 2
            sourceSize.width: width * 2
            width: height
        }

        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: textCol.left
            anchors.right: parent.right
            color: styler.border
            height: 1
            visible: index < page.model.count - 1
        }

        onClicked: {
            app.hideMenu(querySummary);
            app.stateId = stateId;
            page.dropPicked();
            var p = pois.convertFromPython(model);
            var available_poi = app.pois.has(p);
            if (available_poi)
                p = available_poi; // a saved place: show it as it is
            else {
                var new_poi = pois.add(p, stateId);
                if (new_poi) p = new_poi;
            }
            pois.show(p, true);
            map.autoCenter = false;
            map.setCenter(model.x, model.y);
        }

    }

    model: ListModel {}

    pageMenu: PageMenuPL {
        visible: page.model.count > 1
        PageMenuItemPL {
            iconName: styler.iconMaps
            text: app.tr("Show all on map")
            onClicked: {
                var all = [];
                for (var i = 0; i < page.model.count; i++) {
                    var item = page.model.get(i);
                    all.push(app.pois.convertFromPython(item));
                }
                app.hideMenu(querySummary);
                app.stateId = stateId;
                app.pois.addList(all, stateId);
                map.fitViewToPois(all);
            }
        }
    }

    placeholderEnabled: populated && model.count < 1
    placeholderText: app.tr("No results")
    title: app.tr("Nearby Venues")

    property bool   loading: true
    property bool   populated: false
    property int    searchCounter: 0
    property string stateId: "Nearby search: " + querySummary + searchCounter
    property string querySummary
    property string iconName: "map-pin"

    readonly property real margin: styler.themeHorizontalPageMargin
    readonly property real u: styler.themePaddingMedium

    headerExtra: Component {
        Item {
            height: busy.running ? page.height : 0
            width: busy.running ? page.width : 0
            BusyModal {
                id: busy
                running: page.loading
                text: app.tr("Searching")
            }
        }
    }

    onPageStatusActivating: {
        if (page.populated) return;
        page.model.clear();
        page.loading = true;
    }

    onPageStatusActive: {
        if (page.populated) return;
        var nearbyPage = app.pages.previousPage();
        page.iconName = page.iconFor(nearbyPage.queryType);
        page.populate(nearbyPage.queryType, nearbyPage.queryName,
                      nearbyPage.near, nearbyPage.radius, nearbyPage.params);
        querySummary = app.tr("Nearby venues: %1 %2",
                              nearbyPage.queryType, nearbyPage.queryName)
    }

    function iconFor(type) {
        var icons = {
            "Restaurant": "utensils", "Fast food": "utensils", "Café": "coffee", "Bakery": "coffee",
            "Bar or pub": "wine", "Supermarket": "shopping-cart", "Pharmacy": "pill",
            "Fuel station": "fuel", "Charging station": "zap", "Parking": "circle-parking",
            "ATM": "banknote", "Bank": "banknote", "Hotel": "bed", "Hospital": "cross"
        };
        return icons[type] || "map-pin";
    }

    function dropPicked() {
        // one pin at a time: remove the place picked before from this list
        // (saved places stay)
        var keep = app.pois._poisKeep;
        if (keep.stateId !== stateId) return;
        var ids = keep.poiIds.slice();
        for (var i = 0; i < ids.length; i++) {
            var q = app.pois.getById(ids[i]);
            if (q && !q.bookmarked) app.pois.remove(ids[i]);
        }
        keep.poiIds = [];
    }

    function populate(queryType, queryName, near, radius, params) {
        // Load nearby results from the Python backend.
        page.model.clear();
        searchCounter += 1;
        py.call("poor.app.guide.nearby", [queryType, queryName,
                                          near, radius, params], function(results) {
            if (results && results.error && results.message) {
                page.placeholderText = results.message;
            } else if (results.length > 0) {
                page.title = results.length === 1 ? app.tr("1 place") :
                                                     app.tr("%1 places", results.length);
                Util.appendAll(page.model, results);
            }
            page.loading = false;
            page.populated = true;
            // no pins yet: a pin appears for the place the user picks
            app.stateId = stateId;
        });
    }

}
