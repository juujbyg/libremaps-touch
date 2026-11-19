/* -*- coding: utf-8-unix -*-
 *
 * Copyright (C) 2014 Osmo Salomaa, 2018 Rinigus
 * LibreMaps: restyled as a card form (location row, distance pills, category
 * tiles, an inline name field and one big Search button).
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
import QtQuick.Controls 2.5
import "."
import "platform"

PagePL {
    id: page
    title: app.tr("Nearby")

    acceptIconName: styler.iconNearby
    acceptText: app.tr("Search")
    canNavigateForward: page.near &&
                        (page.nearText !== app.tr("Current position") || gps.coordinateValid) &&
                        (page.queryType.length > 0 || page.queryName.length > 0)
    // the big Search button below replaces the header's accept icon
    property bool hideAcceptButton: true

    pageMenu: PageMenuPL {
        PageMenuItemPL {
            iconName: styler.iconPreferences
            text: app.tr("Change provider (%1)").arg(name)
            property string name: py.evaluate("poor.app.guide.name")
            onClicked: {
                var dialog = app.push(Qt.resolvedUrl("GuidePage.qml"));
                dialog.accepted.connect(function() {
                    name = py.evaluate("poor.app.guide.name");
                    column.addSetttings();
                });
            }
        }
    }

    property bool   initialized: false
    property alias  near: nearButton.coordinates
    property alias  nearText: nearButton.text
    property string queryType: ""
    property string queryName: ""
    property var    params: {}
    property real   radius: 1000

    // Offer a different selection of radii depending on the user's
    // preferred length units, but keep values as meters.
    property var radiusLabels: app.conf.units === "metric" ?
                                   ["500 m", "1 km", "2 km", "5 km", "10 km"] :
                                   [ "¼ mi", "½ mi", "1 mi", "2 mi",  "5 mi"]
    property var radiusValues: app.conf.units === "metric" ?
                                   [500, 1000, 2000, 5000, 10000] :
                                   [402,  805, 1609, 3219,  8047]

    // the tiles; "type" is the guide's own (English) place type
    property var categories: [
        { "label": app.tr("Food"),      "type": "Restaurant",       "icon": "utensils" },
        { "label": app.tr("Coffee"),    "type": "Café",             "icon": "coffee" },
        { "label": app.tr("Bars"),      "type": "Bar or pub",       "icon": "wine" },
        { "label": app.tr("Groceries"), "type": "Supermarket",      "icon": "shopping-cart" },
        { "label": app.tr("Pharmacy"),  "type": "Pharmacy",         "icon": "pill" },
        { "label": app.tr("Fuel"),      "type": "Fuel station",     "icon": "fuel" },
        { "label": app.tr("Charging"),  "type": "Charging station", "icon": "zap" },
        { "label": app.tr("Parking"),   "type": "Parking",          "icon": "circle-parking" },
        { "label": app.tr("ATM"),       "type": "ATM",              "icon": "banknote" },
        { "label": app.tr("Hotels"),    "type": "Hotel",            "icon": "bed" },
        { "label": app.tr("Hospital"),  "type": "Hospital",         "icon": "cross" }
    ]
    readonly property bool customType: {
        if (!page.queryType) return false;
        for (var i = 0; i < page.categories.length; i++)
            if (page.categories[i].type === page.queryType) return false;
        return true;
    }

    readonly property real margin: styler.themeHorizontalPageMargin
    readonly property real u: styler.themePaddingMedium

    Column {
        id: column
        spacing: page.u
        width: page.width - 2 * page.margin
        x: page.margin

        property var settings: null

        // kept for its location picker (activate()) and the values it holds
        RoutePoint {
            id: nearButton
            comment: app.tr("Select a reference location next to which you want to perform the search.")
            label: app.tr("Near")
            title: app.tr("Near location")
            height: 0
            visible: false
        }

        // ---- where
        Text {
            color: styler.muted
            font.family: styler.themeFontFamily
            font.pixelSize: styler.themeFontSizeSmall
            font.weight: Font.Medium
            text: app.tr("Near")
        }

        Rectangle {
            id: nearCard
            border.color: styler.border
            border.width: 1
            color: nearMouse.pressed ? styler.subtle : styler.surface
            height: styler.themeItemSizeSmall * 1.1
            radius: styler.radiusLg
            width: parent.width

            readonly property bool here: page.nearText === app.tr("Current position")

            Rectangle {
                id: nearIcon
                anchors.left: parent.left
                anchors.leftMargin: page.u * 1.2
                anchors.verticalCenter: parent.verticalCenter
                color: styler.subtle
                height: parent.height * 0.62
                radius: height / 2
                width: height
                Image {
                    anchors.centerIn: parent
                    height: parent.height * 0.55
                    smooth: true
                    source: styler.icon(nearCard.here ? "locate-fixed" : "map-pin")
                    sourceSize.height: height * 2
                    sourceSize.width: width * 2
                    width: height
                }
            }

            Column {
                anchors.left: nearIcon.right
                anchors.leftMargin: page.u * 1.2
                anchors.right: nearChevron.left
                anchors.rightMargin: page.u
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    color: styler.ink
                    elide: Text.ElideRight
                    font.family: styler.themeFontFamily
                    font.pixelSize: styler.themeFontSizeMedium
                    font.weight: Font.Medium
                    text: page.nearText
                    width: parent.width
                }
                Text {
                    color: styler.muted
                    font.family: styler.themeFontFamily
                    font.pixelSize: styler.themeFontSizeExtraSmall
                    text: nearCard.here && !gps.coordinateValid ?
                              app.tr("Waiting for position…") : app.tr("Tap to change")
                    width: parent.width
                }
            }

            Image {
                id: nearChevron
                anchors.right: parent.right
                anchors.rightMargin: page.u * 1.2
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height * 0.32
                smooth: true
                source: styler.icon("chevron-right", "muted")
                sourceSize.height: height * 2
                sourceSize.width: width * 2
                width: height
            }

            MouseArea {
                id: nearMouse
                anchors.fill: parent
                onClicked: nearButton.activate()
            }
        }

        Item { height: page.u * 0.5; width: 1 }

        // ---- how far
        Text {
            color: styler.muted
            font.family: styler.themeFontFamily
            font.pixelSize: styler.themeFontSizeSmall
            font.weight: Font.Medium
            text: app.tr("Within")
        }

        Flow {
            spacing: page.u * 0.8
            width: parent.width
            Repeater {
                model: page.radiusLabels.length
                delegate: Rectangle {
                    readonly property bool chosen: page.radius === page.radiusValues[index]
                    border.color: chosen ? styler.primary : styler.border
                    border.width: 1
                    color: chosen ? styler.primary : (pillMouse.pressed ? styler.subtle : styler.surface)
                    height: styler.themeItemSizeSmall * 0.68
                    radius: height / 2
                    width: pillText.implicitWidth + 2.6 * page.u
                    Text {
                        id: pillText
                        anchors.centerIn: parent
                        color: parent.chosen ? styler.primaryText : styler.ink
                        font.family: styler.themeFontFamily
                        font.pixelSize: styler.themeFontSizeSmall
                        font.weight: Font.Medium
                        text: page.radiusLabels[index]
                    }
                    MouseArea {
                        id: pillMouse
                        anchors.fill: parent
                        onClicked: page.radius = page.radiusValues[index]
                    }
                }
            }
        }

        Item { height: page.u * 0.5; width: 1 }

        // ---- what
        Text {
            color: styler.muted
            font.family: styler.themeFontFamily
            font.pixelSize: styler.themeFontSizeSmall
            font.weight: Font.Medium
            text: app.tr("Looking for")
        }

        Grid {
            id: tiles
            columns: 4
            columnSpacing: page.u * 0.8
            rowSpacing: page.u * 1.2
            width: parent.width

            readonly property real tileWidth: (width - 3 * columnSpacing) / 4

            Repeater {
                // the categories, then "More" (shows a type picked from the full list)
                model: page.categories.length + 1
                delegate: Item {
                    readonly property bool more: index === page.categories.length
                    readonly property var  cat: more ? null : page.categories[index]
                    readonly property bool chosen: more ? page.customType : page.queryType === cat.type
                    height: tileBox.height + page.u * 0.6 + tileLabel.height
                    width: tiles.tileWidth

                    Rectangle {
                        id: tileBox
                        anchors.horizontalCenter: parent.horizontalCenter
                        border.color: parent.chosen ? styler.primary : styler.border
                        border.width: 1
                        color: parent.chosen ? styler.primary : (tileMouse.pressed ? styler.subtle : styler.surface)
                        height: Math.min(parent.width, styler.themeItemSizeSmall * 1.15)
                        radius: styler.radiusLg
                        width: parent.width
                        Image {
                            anchors.centerIn: parent
                            height: parent.height * 0.42
                            smooth: true
                            source: styler.icon(tileBox.parent.more ? "layout-grid" : tileBox.parent.cat.icon,
                                                tileBox.parent.chosen ? (styler.dark ? "ink" : "white") : "")
                            sourceSize.height: height * 2
                            sourceSize.width: width * 2
                            width: height
                        }
                    }

                    Text {
                        id: tileLabel
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: tileBox.bottom
                        anchors.topMargin: page.u * 0.6
                        color: parent.chosen ? styler.ink : styler.inkSoft
                        elide: Text.ElideRight
                        font.family: styler.themeFontFamily
                        font.pixelSize: styler.themeFontSizeExtraSmall
                        font.weight: parent.chosen ? Font.DemiBold : Font.Normal
                        horizontalAlignment: Text.AlignHCenter
                        text: parent.more ? (page.customType ? page.queryType : app.tr("More")) : parent.cat.label
                        width: parent.width
                    }

                    MouseArea {
                        id: tileMouse
                        anchors.fill: parent
                        onClicked: {
                            if (parent.more) {
                                var dialog = app.push(Qt.resolvedUrl("PlaceTypePage.qml"),
                                                      {"query": page.customType ? page.queryType : ""});
                                dialog.accepted.connect(function() {
                                    page.queryType = dialog.query;
                                });
                            } else {
                                // tap again to clear it and search by name only
                                page.queryType = parent.chosen ? "" : parent.cat.type;
                            }
                        }
                    }
                }
            }
        }

        Item { height: page.u * 0.5; width: 1 }

        // ---- name
        Text {
            color: styler.muted
            font.family: styler.themeFontFamily
            font.pixelSize: styler.themeFontSizeSmall
            font.weight: Font.Medium
            text: app.tr("Name (optional)")
        }

        TextField {
            id: nameField
            color: styler.ink
            font.family: styler.themeFontFamily
            font.pixelSize: styler.themeFontSizeMedium
            inputMethodHints: Qt.ImhNoAutoUppercase
            leftPadding: page.u * 1.4
            placeholderText: app.tr("e.g. Mercadona, pizza")
            placeholderTextColor: styler.muted
            rightPadding: page.u * 1.4
            text: page.queryName
            width: parent.width
            background: Rectangle {
                border.color: nameField.activeFocus ? styler.borderStrong : styler.border
                border.width: nameField.activeFocus ? 2 : 1
                color: styler.surface
                implicitHeight: styler.themeItemSizeSmall * 0.95
                radius: styler.radiusLg
            }
            onTextChanged: page.queryName = text.trim()
            onAccepted: page.search()
        }

        Item { height: page.u; width: 1 }

        ButtonPL {
            enabled: page.canNavigateForward
            text: app.tr("Search")
            width: parent.width
            onClicked: page.search()
        }

        Item { height: page.u * 2; width: 1 }

        Component.onCompleted: column.addSetttings();

        function addSetttings() {
            // Add guide-specific settings from guide's own QML file.
            page.params = {};
            if (column.settings) column.settings.destroy();
            var uri = Qt.resolvedUrl(py.evaluate("poor.app.guide.settings_qml_uri"));
            if (!uri) return;
            var component = Qt.createComponent(uri);
            if (component.status === Component.Error) {
                console.log('Error while creating component');
                console.log(component.errorString());
                return null;
            }
            column.settings = component.createObject(column);
            if (!column.settings) return;
            column.settings.anchors.left = column.left;
            column.settings.anchors.right = column.right;
            column.settings.width = column.width;
        }
    }

    Component.onCompleted: {
        if (!page.near) {
            page.near = app.getPosition();
            page.nearText = app.tr("Current position");
        }
        // a radius from an older version that's no longer offered: use the nearest one
        if (page.radiusValues.indexOf(page.radius) < 0) {
            var best = page.radiusValues[0];
            for (var i = 0; i < page.radiusValues.length; i++)
                if (Math.abs(page.radiusValues[i] - page.radius) < Math.abs(best - page.radius))
                    best = page.radiusValues[i];
            page.radius = best;
        }
    }

    onQueryTypeChanged: if (page.queryType) py.call_sync("poor.app.history.add_place_type", [page.queryType])

    function search() {
        if (!page.canNavigateForward) return;
        if (page.queryName) py.call_sync("poor.app.history.add_place_name", [page.queryName]);
        nameField.focus = false;
        Qt.inputMethod.hide();
        app.pages.navigateForward();
    }

    onPageStatusActive: {
        var resultPage;
        if (!initialized) {
            resultPage = app.pushAttachedMain(Qt.resolvedUrl("NearbyResultsPage.qml"));
            resultPage.populated = false;
            initialized = true;
        }

        if (page.nearText === app.tr("Current position"))
            page.near = app.getPosition();
        resultPage = app.pages.nextPage();
        if (resultPage) resultPage.populated = false;
    }

}
