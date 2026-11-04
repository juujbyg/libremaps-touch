/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: choose how you travel. Four big choices (Walk, Bike, Car,
 * Transit); extra options show up only when they matter. The choice is
 * remembered.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.0
import "../qml/platform"
import "../qml"

Column {
    id: settingsBlock
    spacing: styler.themePaddingMedium

    property bool   full: true
    property string router: "libremaps"

    property string currentMode: app.conf.get("routers.libremaps.mode")
    property string currentTransit: app.conf.get("routers.libremaps.transit_modes")

    // main choices: label, router mode
    readonly property var mains: [
        { "label": app.tr("Walk"),    "mode": "pedestrian" },
        { "label": app.tr("Bike"),    "mode": "bicycle" },
        { "label": app.tr("Car"),     "mode": "auto" },
        { "label": app.tr("Transit"), "mode": "transit" }
    ]
    // less common car-like modes, shown as small chips under Car
    readonly property var carLike: [
        { "label": app.tr("Scooter"), "mode": "motor_scooter" },
        { "label": app.tr("Taxi"),    "mode": "taxi" }
    ]
    readonly property var transits: [
        { "label": app.tr("Any"),   "transit": "all" },
        { "label": app.tr("Bus"),   "transit": "bus" },
        { "label": app.tr("Metro"), "transit": "subway" },
        { "label": app.tr("Tram"),  "transit": "tram" },
        { "label": app.tr("Train"), "transit": "rail" }
    ]
    readonly property bool isCarLike: currentMode === "auto" || currentMode === "motor_scooter" || currentMode === "taxi"

    function mainSelected(m) {
        if (m.mode === "auto") return isCarLike;
        return m.mode === currentMode;
    }
    function setMode(mode) {
        app.conf.set("routers.libremaps.mode", mode);
        currentMode = mode;
    }
    function setTransit(t) {
        app.conf.set("routers.libremaps.transit_modes", t);
        currentTransit = app.conf.get("routers.libremaps.transit_modes");
    }

    // ---- four big segmented choices
    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: styler.themeHorizontalPageMargin
        anchors.rightMargin: styler.themeHorizontalPageMargin
        spacing: styler.themePaddingMedium

        Repeater {
            model: settingsBlock.mains
            delegate: Rectangle {
                readonly property bool selected: settingsBlock.mainSelected(modelData)
                border.color: selected ? styler.accent : styler.themeSecondaryColor
                border.width: 1
                color: selected ? styler.accent : "transparent"
                height: styler.themeItemSizeLarge * 0.8
                radius: styler.themePaddingLarge
                width: (parent.width - 3 * parent.spacing) / 4

                LabelPL {
                    anchors.centerIn: parent
                    color: parent.selected ? styler.textOnAccent : styler.themePrimaryColor
                    font.bold: parent.selected
                    text: modelData.label
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: settingsBlock.setMode(modelData.mode)
                }
            }
        }
    }

    // ---- small second row: only for Car (variants + tolls) or Transit (which kind)
    Flow {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: styler.themeHorizontalPageMargin
        anchors.rightMargin: styler.themeHorizontalPageMargin
        spacing: styler.themePaddingMedium
        visible: settingsBlock.isCarLike

        Repeater {
            model: settingsBlock.carLike
            delegate: Rectangle {
                readonly property bool selected: modelData.mode === settingsBlock.currentMode
                border.color: selected ? styler.accent : styler.themeSecondaryColor
                border.width: 1
                color: "transparent"
                height: styler.themeItemSizeSmall * 0.8
                radius: height / 2
                width: l1.implicitWidth + 2 * styler.themePaddingLarge
                LabelPL {
                    id: l1
                    anchors.centerIn: parent
                    color: parent.selected ? styler.accentText : styler.themeSecondaryHighlightColor
                    font.bold: parent.selected
                    font.pixelSize: styler.themeFontSizeSmall
                    text: modelData.label
                }
                MouseArea { anchors.fill: parent; onClicked: settingsBlock.setMode(modelData.mode) }
            }
        }
        Rectangle {
            id: tollChip
            property bool avoid: app.conf.get("routers.libremaps.use_tolls") < 0.5
            border.color: avoid ? styler.accent : styler.themeSecondaryColor
            border.width: 1
            color: "transparent"
            height: styler.themeItemSizeSmall * 0.8
            radius: height / 2
            visible: settingsBlock.currentMode === "auto"
            width: l2.implicitWidth + 2 * styler.themePaddingLarge
            LabelPL {
                id: l2
                anchors.centerIn: parent
                color: parent.avoid ? styler.accentText : styler.themeSecondaryHighlightColor
                font.bold: parent.avoid
                font.pixelSize: styler.themeFontSizeSmall
                text: app.tr("No tolls")
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    app.conf.set("routers.libremaps.use_tolls", tollChip.avoid ? 0.5 : 0.0);
                    tollChip.avoid = !tollChip.avoid;
                }
            }
        }
    }

    Flow {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: styler.themeHorizontalPageMargin
        anchors.rightMargin: styler.themeHorizontalPageMargin
        spacing: styler.themePaddingMedium
        visible: settingsBlock.currentMode === "transit"

        Repeater {
            model: settingsBlock.transits
            delegate: Rectangle {
                readonly property bool selected: modelData.transit === settingsBlock.currentTransit
                border.color: selected ? styler.accent : styler.themeSecondaryColor
                border.width: 1
                color: "transparent"
                height: styler.themeItemSizeSmall * 0.8
                radius: height / 2
                width: l3.implicitWidth + 2 * styler.themePaddingLarge
                LabelPL {
                    id: l3
                    anchors.centerIn: parent
                    color: parent.selected ? styler.accentText : styler.themeSecondaryHighlightColor
                    font.bold: parent.selected
                    font.pixelSize: styler.themeFontSizeSmall
                    text: modelData.label
                }
                MouseArea { anchors.fill: parent; onClicked: settingsBlock.setTransit(modelData.transit) }
            }
        }
    }
}
