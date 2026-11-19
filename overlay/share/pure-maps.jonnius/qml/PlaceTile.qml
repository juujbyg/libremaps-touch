/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: one action tile on the place sheet (Save, Call, Share, More), Waze style.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.0
import "."

Rectangle {
    id: tile
    border.color: styler.border
    border.width: 1
    color: mouse.pressed && enabled ? styler.border : styler.subtle
    height: Math.round(u * 6.6)
    opacity: enabled ? 1 : 0.45
    radius: styler.radiusLg

    property string icon      // name in icons/ui, without the tone
    property string label
    property real   u: styler.themePaddingMedium

    signal clicked

    Accessible.name: label
    Accessible.role: Accessible.Button

    Column {
        anchors.centerIn: parent
        spacing: tile.u * 0.55
        width: parent.width

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            height: Math.round(tile.u * 2.3)
            smooth: true
            source: styler.icon(tile.icon, styler.linkTone)
            sourceSize.height: height * 2
            sourceSize.width: height * 2
            width: height
        }

        Text {
            color: styler.link
            elide: Text.ElideRight
            font.family: styler.themeFontFamily
            font.pixelSize: Math.round(tile.u * 1.25)
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignHCenter
            text: tile.label
            width: parent.width - tile.u
            x: tile.u / 2
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: tile.enabled
        onClicked: tile.clicked()
    }
}
