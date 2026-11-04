/* -*- coding: utf-8-unix -*-
 *
 * Drive speed bubble: current speed in a ring, as in popular driving apps.
 * The ring turns red when the known street limit is exceeded.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.0

Rectangle {
    id: bubble
    anchors.left: parent.left
    anchors.leftMargin: styler.themePaddingLarge
    anchors.bottom: referenceBlockBottomLeft.top
    anchors.bottomMargin: styler.themePaddingLarge
    border.color: over ? "#ff3b30" : styler.accent
    border.width: Math.max(3, Math.round(width*0.06))
    color: styler.hudBg
    height: width
    radius: width/2
    visible: !app.modalDialog && gps.speedValid &&
             (app.mode === modes.navigate || app.mode === modes.followMe ||
              app.mode === modes.navigatePost)
    width: Math.round(styler.themeIconSizeLarge*1.1)
    z: 400

    // street limit in m/s, when the map matching source knows it
    property real limit: (gps.streetSpeedLimit != null && gps.streetSpeedLimit > 0) ? gps.streetSpeedLimit : roadWatch.limit
    property bool over: limit > 0 && gps.speed > limit*1.03
    property real factor: (app.conf.units === "american" || app.conf.units === "british") ? 2.23694 : 3.6

    Column {
        anchors.centerIn: parent
        spacing: 0

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: bubble.over ? "#ff3b30" : styler.hudText
            font.bold: true
            font.family: "sans-serif"
            font.pixelSize: Math.round(bubble.width*0.40)
            text: Math.round(gps.speed * bubble.factor)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: styler.hudMuted
            font.family: "sans-serif"
            font.pixelSize: Math.round(bubble.width*0.15)
            text: bubble.factor > 3 ? app.tr("km/h") : app.tr("mph")
        }
    }
}
