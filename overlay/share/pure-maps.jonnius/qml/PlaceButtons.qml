/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: round Back and Close buttons over the map while a place is open, Waze style.
 * Back returns to the list the place came from; Close clears the place (and the list).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.0
import QtGraphicalEffects 1.0
import "."

Item {
    id: buttons
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: styler.themePaddingLarge
    height: size
    visible: app.poiActive && !app.modalDialog &&
             (app.mode === modes.explore || app.mode === modes.exploreRoute)
    z: 600

    property real size: Math.round(styler.themePaddingMedium * 5.2)

    Repeater {
        model: [{"id": "back", "icon": "chevron-left", "label": app.tr("Back")},
                {"id": "close", "icon": "x", "label": app.tr("Close")}]
        delegate: Item {
            height: buttons.size
            width: buttons.size
            x: modelData.id === "back" ? styler.themeHorizontalPageMargin
                                       : buttons.width - width - styler.themeHorizontalPageMargin

            Accessible.name: modelData.label
            Accessible.role: Accessible.Button

            Rectangle {
                anchors.fill: parent
                border.color: styler.border
                border.width: 1
                color: mouse.pressed ? styler.subtle : styler.surface
                radius: width / 2
                layer.enabled: true
                layer.effect: DropShadow {
                    color: "#000000"
                    opacity: 0.18
                    radius: 10
                    samples: 21
                    verticalOffset: 2
                }
                Image {
                    anchors.centerIn: parent
                    height: parent.height * 0.46
                    smooth: true
                    source: styler.icon(modelData.icon)
                    sourceSize.height: height * 2
                    sourceSize.width: height * 2
                    width: height
                }
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                anchors.margins: -styler.themePaddingSmall
                onClicked: modelData.id === "back" ? infoPanel.back() : infoPanel.close()
            }
        }
    }
}
