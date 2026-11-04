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

    // pressed feedback for the whole bar
    scale: searchMouse.pressed || menuMouse.pressed || dirMouse.pressed ? 0.985 : 1.0
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }

    Rectangle {
        id: pill
        anchors.fill: parent
        color: styler.itemBg
        radius: height / 2
        layer.enabled: true
        layer.effect: DropShadow {
            color: styler.shadowColor
            opacity: styler.shadowOpacity
            radius: styler.shadowRadius
            samples: 1 + radius * 2
        }
    }

    // thin amber rim, so the bar reads as part of the app on any map style
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: styler.amber
        border.width: 1.5
        opacity: 0.6
        radius: height / 2
    }

    // menu: three rounded bars of different length
    Item {
        id: menuArea
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: bar.height
        Column {
            anchors.centerIn: parent
            spacing: styler.themePaddingSmall * 1.1
            Repeater {
                model: [1.0, 0.68, 0.85]
                Rectangle {
                    color: styler.itemFg
                    height: 3; radius: 1.5
                    width: styler.themeIconSizeSmall * 0.75 * modelData
                }
            }
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
        color: styler.itemFg
        height: bar.height * 0.45
        opacity: 0.18
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
            source: Qt.resolvedUrl("icons/search-glass.svg")
            sourceSize.height: height * 2
            sourceSize.width: height * 2
            width: height
        }
        LabelPL {
            anchors.left: glass.right
            anchors.leftMargin: styler.themePaddingMedium
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            color: styler.themeSecondaryHighlightColor
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
                { "label": app.tr("Food"),     "type": "Restaurant" },
                { "label": app.tr("Coffee"),   "type": "Café" },
                { "label": app.tr("Fuel"),     "type": "Fuel station" },
                { "label": app.tr("Pharmacy"), "type": "Pharmacy" },
                { "label": app.tr("Parking"),  "type": "Parking" }
            ]
            delegate: Rectangle {
                color: chipMouse.pressed ? styler.amberSoft : styler.itemBg
                border.color: styler.amber
                border.width: 1
                height: styler.themeItemSizeSmall * 0.72
                radius: height / 2
                width: chipLabel.implicitWidth + 2 * styler.themePaddingLarge
                layer.enabled: true
                layer.effect: DropShadow {
                    color: styler.shadowColor
                    opacity: styler.shadowOpacity * 0.8
                    radius: styler.shadowRadius * 0.6
                    samples: 1 + radius * 2
                }
                LabelPL {
                    id: chipLabel
                    anchors.centerIn: parent
                    color: styler.itemFg
                    font.pixelSize: styler.themeFontSizeSmall
                    text: modelData.label
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
        var pg = app.pushMain(Qt.resolvedUrl("NearbyPage.qml"));
        if (!pg) return;
        pg.queryType = type;
        pg.radius = 3000;
        pendingNearby.page = pg;
        pendingNearby.restart();
    }

    // give the Nearby page a moment to open, then run the search for the user
    Timer {
        id: pendingNearby
        interval: 400
        property var page: null
        onTriggered: if (page && page.canNavigateForward) app.pages.navigateForward()
    }

    // directions: amber circle with a turn arrow
    Item {
        id: dirArea
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: bar.height
        Rectangle {
            anchors.centerIn: parent
            color: dirMouse.pressed ? styler.amberDark : styler.amber
            height: bar.height - 2 * styler.themePaddingMedium
            radius: height / 2
            width: height
            Image {
                anchors.centerIn: parent
                height: parent.height * 0.55
                smooth: true
                source: Qt.resolvedUrl("icons/route-arrow.svg")
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
