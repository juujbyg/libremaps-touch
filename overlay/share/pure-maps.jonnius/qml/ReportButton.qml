/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: the round button that opens the report sheet.
 * Bottom right: above the trip sheet while navigating, above the locate
 * button while browsing.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.0
import QtGraphicalEffects 1.0

Item {
    id: button
    anchors.right: parent.right
    anchors.rightMargin: Math.round(u * 0.9)
    height: width
    visible: app.conf.communityAlerts && !app.modalDialog && !app.infoPanelOpen &&
             !reportSheet.open && (app.mode === modes.navigate || app.mode === modes.followMe ||
                                   (app.mode === modes.explore && !map.cleanMode))
    width: Math.round(u * 4.6)
    y: {
        if (app.mode === modes.explore)
            return centerButton.y + (centerButton.height - centerButton.width) / 2 - height - u * 0.4;
        return parent.height - referenceBlockBottom.height - height - u * 1.4;
    }
    z: 500

    property real u: styler.themePaddingMedium

    Rectangle {
        anchors.fill: parent
        // navy, so it doesn't look like the amber hazard icons on the map
        color: mouse.pressed ? "#3a4256" : "#1f2430"
        border.color: styler.amber
        border.width: Math.max(2, Math.round(width * 0.04))
        radius: width / 2
        scale: mouse.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        layer.enabled: true
        layer.effect: DropShadow {
            color: "#000000"
            opacity: 0.3
            radius: 10
            samples: 21
            verticalOffset: 2
        }

        // a warning triangle with a plus: "add a report"
        Canvas {
            anchors.centerIn: parent
            height: parent.height * 0.56
            width: height
            onPaint: {
                var c = getContext("2d"), w = width, h = height;
                c.reset();
                c.fillStyle = styler.amber;
                c.lineJoin = "round";
                c.beginPath();
                c.moveTo(w * 0.5, h * 0.06);
                c.lineTo(w * 0.97, h * 0.9);
                c.lineTo(w * 0.03, h * 0.9);
                c.closePath();
                c.fill();
                c.fillStyle = "#1f2430";
                var t = w * 0.1;
                c.fillRect(w * 0.5 - t / 2, h * 0.4, t, h * 0.38);
                c.fillRect(w * 0.31, h * 0.59 - t / 2, w * 0.38, t);
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -u * 0.4
        onClicked: reportSheet.open = true
    }
}
