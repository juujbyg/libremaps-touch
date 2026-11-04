/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: current speed, bottom left while navigating.
 * A round bubble that turns red and pulses when over the known limit.
 * The limit itself is a sign on the bubble's corner (SpeedLimit.qml).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.0
import QtGraphicalEffects 1.0

Item {
    id: bubble
    anchors.left: parent.left
    anchors.leftMargin: Math.round(styler.themePaddingMedium * 0.9)
    anchors.bottom: referenceBlockBottomLeft.top
    anchors.bottomMargin: styler.themePaddingMedium * 1.2
    height: width
    visible: !app.modalDialog && gps.speedValid &&
             (app.mode === modes.navigate || app.mode === modes.followMe ||
              app.mode === modes.navigatePost)
    width: Math.round(styler.themePaddingMedium * 6.2)
    z: 400

    // street limit in m/s, when the map matching source knows it
    property real limit: (gps.streetSpeedLimit != null && gps.streetSpeedLimit > 0) ? gps.streetSpeedLimit : roadWatch.limit
    property bool over: limit > 0 && gps.speed > limit*1.03
    property real factor: (app.conf.units === "american" || app.conf.units === "british") ? 2.23694 : 3.6

    Rectangle {
        id: disc
        anchors.fill: parent
        color: bubble.over ? "#e53935" : styler.hudBg
        radius: width / 2
        layer.enabled: true
        layer.effect: DropShadow {
            color: "#000000"
            opacity: 0.3
            radius: 10
            samples: 21
            verticalOffset: 2
        }
        Behavior on color { ColorAnimation { duration: 250 } }

        SequentialAnimation on scale {
            loops: Animation.Infinite
            running: bubble.over
            NumberAnimation { to: 1.06; duration: 500; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1.0;  duration: 500; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) disc.scale = 1.0
        }
    }

    Column {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: bubble.width * 0.02
        spacing: -bubble.width * 0.04

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: bubble.over ? "white" : styler.hudText
            font.bold: true
            font.family: styler.themeFontFamilyHeading
            font.pixelSize: Math.round(bubble.width * 0.4)
            text: Math.round(gps.speed * bubble.factor)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            color: bubble.over ? "white" : styler.hudMuted
            font.pixelSize: Math.round(bubble.width * 0.16)
            text: bubble.factor > 3 ? app.tr("km/h") : app.tr("mph")
        }
    }
}
