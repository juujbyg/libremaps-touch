/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: a round button over the map while driving that turns spoken
 * directions on and off, Waze style. It sits above the report button.
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
    id: button
    anchors.right: parent.right
    anchors.rightMargin: Math.round(u * 0.9) + (reportButton.width - width) / 2
    height: width
    visible: !app.modalDialog && !app.infoPanelOpen && !reportSheet.open &&
             app.mode === modes.navigate
    width: Math.round(u * 4.2)
    y: {
        if (reportButton.visible) return reportButton.y - height - u * 1.1;
        var bottom = alertBanner.shown ? alertBanner.y : parent.height - referenceBlockBottom.height;
        return bottom - height - u * 1.4;
    }
    z: 500

    property real u: styler.themePaddingMedium
    property bool on: app.conf.voiceNavigation

    Accessible.name: on ? app.tr("Mute voice") : app.tr("Unmute voice")
    Accessible.role: Accessible.Button

    Rectangle {
        anchors.fill: parent
        border.color: styler.border
        border.width: 1
        color: mouse.pressed ? styler.subtle : styler.surface
        radius: width / 2
        scale: mouse.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        layer.enabled: true
        layer.effect: DropShadow {
            color: "#000000"
            opacity: 0.18
            radius: 12
            samples: 25
            verticalOffset: 2
        }

        Image {
            anchors.centerIn: parent
            height: parent.height * 0.46
            smooth: true
            source: button.on ? styler.icon("volume-2") : styler.icon("volume-x", "danger")
            sourceSize.height: height * 2
            sourceSize.width: height * 2
            width: height
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -u * 0.4
        onClicked: {
            app.conf.set("voice_navigation", !button.on);
            notification.flash(button.on ? app.tr("Voice unmuted") : app.tr("Voice muted"), "soundButton");
        }
    }
}
