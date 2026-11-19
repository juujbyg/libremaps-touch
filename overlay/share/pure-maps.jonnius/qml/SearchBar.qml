/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: one search bar on top of the map, like openstreetmap.org.
 * Left: menu. Middle: search places. Right: directions.
 * Colours come from the app logo: amber pin (#e8a94a) and navy (#0e1a2b).
 */

import QtQuick 2.0
import QtGraphicalEffects 1.0
import "platform"

Item {
    id: bar
    anchors.left: parent.left
    anchors.leftMargin: styler.themePaddingLarge
    anchors.right: parent.right
    anchors.rightMargin: styler.themePaddingLarge
    anchors.top: parent.top
    anchors.topMargin: styler.themePaddingLarge
    height: styler.themeItemSizeSmall * 1.2
    visible: app.mode === modes.explore && !app.modalDialog && !app.infoPanelOpen
    z: 900

    // the bar plus the shortcut chips below it, for things placed under both
    readonly property real fullHeight: height + chipsFlick.anchors.topMargin + chipsFlick.height

    // pressed feedback for the whole bar
    scale: searchMouse.pressed || menuMouse.pressed || dirMouse.pressed ? 0.985 : 1.0
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

    // a command-bar card: white, thin grey border, soft shadow
    Rectangle {
        id: pill
        anchors.fill: parent
        border.color: styler.border
        border.width: 1
        color: styler.surface
        radius: styler.radiusLg
        layer.enabled: true
        layer.effect: DropShadow {
            color: styler.shadowColor
            opacity: styler.shadowOpacity
            radius: styler.shadowRadius
            samples: 1 + radius * 2
            verticalOffset: 2
        }
    }

    // menu
    Item {
        id: menuArea
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: bar.height
        Rectangle {
            anchors.centerIn: parent
            color: menuMouse.pressed ? styler.subtle : "transparent"
            height: bar.height - 2 * styler.themePaddingMedium
            radius: styler.radiusMd
            width: height
        }
        Image {
            anchors.centerIn: parent
            height: bar.height * 0.4
            smooth: true
            source: styler.icon("menu")
            sourceSize.height: height * 2
            sourceSize.width: height * 2
            width: height
        }
        MouseArea {
            id: menuMouse
            anchors.fill: parent
            onClicked: app.showMenu()
        }
    }

    Rectangle {
        anchors.left: menuArea.right
        anchors.verticalCenter: parent.verticalCenter
        color: styler.border
        height: bar.height * 0.45
        width: 1
    }

    // search: magnifier + hint
    Item {
        anchors.left: menuArea.right
        anchors.right: dirArea.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        opacity: searchMouse.pressed ? 0.6 : 1.0
        Image {
            id: glass
            anchors.left: parent.left
            anchors.leftMargin: styler.themePaddingLarge
            anchors.verticalCenter: parent.verticalCenter
            height: bar.height * 0.38
            smooth: true
            source: styler.icon("search", "muted")
            sourceSize.height: height * 2
            sourceSize.width: height * 2
            width: height
        }
        LabelPL {
            anchors.left: glass.right
            anchors.leftMargin: styler.themePaddingMedium
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: styler.muted
            elide: Text.ElideRight
            font.pixelSize: styler.themeFontSizeMedium
            text: app.tr("Search places")
        }
        MouseArea {
            id: searchMouse
            anchors.fill: parent
            onClicked: app.pushMain(Qt.resolvedUrl("GeocodePage.qml"))
        }
    }

    // quick place shortcuts under the bar
    Flickable {
        id: chipsFlick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.bottom
        anchors.topMargin: styler.themePaddingMedium
        clip: false
        contentHeight: chips.height + styler.themePaddingLarge
        contentWidth: chips.width + styler.themePaddingLarge
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        height: styler.themeItemSizeSmall * 0.72 + styler.themePaddingLarge

    Row {
        id: chips
        x: styler.themePaddingMedium
        spacing: styler.themePaddingMedium

        Repeater {
            model: [
                { "label": app.tr("Food"),     "type": "Restaurant",   "icon": "utensils" },
                { "label": app.tr("Coffee"),   "type": "Café",         "icon": "coffee" },
                { "label": app.tr("Fuel"),     "type": "Fuel station", "icon": "fuel" },
                { "label": app.tr("Pharmacy"), "type": "Pharmacy",     "icon": "pill" },
                { "label": app.tr("Parking"),  "type": "Parking",      "icon": "circle-parking" }
            ]
            // outline badges with an icon
            delegate: Rectangle {
                color: chipMouse.pressed ? styler.subtle : styler.surface
                border.color: styler.border
                border.width: 1
                height: styler.themeItemSizeSmall * 0.72
                radius: height / 2
                width: chipRow.width + 2 * styler.themePaddingLarge
                layer.enabled: true
                layer.effect: DropShadow {
                    color: styler.shadowColor
                    opacity: styler.shadowOpacity * 0.7
                    radius: styler.shadowRadius * 0.5
                    samples: 1 + radius * 2
                    verticalOffset: 1
                }
                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: styler.themePaddingSmall
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        height: chipLabel.font.pixelSize * 1.15
                        smooth: true
                        source: styler.icon(modelData.icon)
                        sourceSize.height: height * 2
                        sourceSize.width: height * 2
                        width: height
                    }
                    LabelPL {
                        id: chipLabel
                        anchors.verticalCenter: parent.verticalCenter
                        color: styler.ink
                        font.pixelSize: styler.themeFontSizeSmall
                        font.weight: Font.Medium
                        text: modelData.label
                    }
                }
                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    onClicked: bar.searchNearby(modelData.type)
                }
            }
        }
    }

    }

    function searchNearby(type) {
        // Set these at creation, so the radius menu shows the same value. The
        // radius must be one of NearbyPage's radiusValues (about 2 km).
        var pg = app.pushMain(Qt.resolvedUrl("NearbyPage.qml"), {
            "queryType": type,
            "radius": app.conf.units === "metric" ? 2000 : 1609
        });
        if (!pg) return;
        pendingNearby.page = pg;
        pendingNearby.tries = 0;
        pendingNearby.restart();
    }

    // Run the search for the user once the Nearby page is open. Its results
    // page is attached only when the page becomes active, which takes longer
    // on a busy phone, so keep checking for up to 5 s.
    Timer {
        id: pendingNearby
        interval: 250
        repeat: true
        property var page: null
        property int tries: 0
        onTriggered: {
            tries++;
            if (!page || app.pages.ps.currentItem !== page || tries > 20) {
                stop();
            } else if (app.pages.nextPage() && page.canNavigateForward) {
                stop();
                app.pages.navigateForward();
            }
        }
    }

    // directions: a dark primary button with the route icon
    Item {
        id: dirArea
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: bar.height
        Rectangle {
            anchors.centerIn: parent
            color: dirMouse.pressed ? styler.primaryPressed : styler.primary
            height: bar.height - 2 * styler.themePaddingMedium
            radius: styler.radiusMd
            width: height
            Image {
                anchors.centerIn: parent
                height: parent.height * 0.5
                smooth: true
                source: styler.icon("route", styler.dark ? "ink" : "white")
                sourceSize.height: height * 2
                sourceSize.width: height * 2
                width: height
            }
        }
        MouseArea {
            id: dirMouse
            anchors.fill: parent
            onClicked: app.pushMain(Qt.resolvedUrl("RoutePage.qml"))
        }
    }
}
