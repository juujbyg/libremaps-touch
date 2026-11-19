/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: a small rounded label under a place's name ("Open 24 hours", "1.0 km away").
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.0
import "."

Rectangle {
    id: chip
    color: styler.subtle
    height: Math.round(label.implicitHeight + u * 0.7)
    radius: styler.radiusSm
    visible: text.length > 0
    width: visible ? Math.round(label.implicitWidth + u * 1.4) : 0

    property alias text: label.text
    property color textColor: styler.ink
    property real  u: styler.themePaddingMedium

    Text {
        id: label
        anchors.centerIn: parent
        color: chip.textColor
        font.family: styler.themeFontFamily
        font.pixelSize: Math.round(chip.u * 1.3)
        font.weight: Font.DemiBold
    }
}
