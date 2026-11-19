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
        var bottom = alertBanner.shown ? alertBanner.y : parent.height - referenceBlockBottom.height;
        return bottom - height - u * 1.4;
    }
    z: 500

    property real u: styler.themePaddingMedium

    Rectangle {
        anchors.fill: parent
        color: mouse.pressed ? styler.navYellowPressed : styler.navYellow
        radius: styler.radiusLg
        scale: mouse.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: 90 } }
        layer.enabled: true
        layer.effect: DropShadow {
            color: "#000000"
            opacity: 0.22
            radius: 12
            samples: 25
            verticalOffset: 2
        }

        Image {
            anchors.centerIn: parent
            height: parent.height * 0.5
            smooth: true
            source: Qt.resolvedUrl("icons/ui/triangle-alert-ink.svg")
            sourceSize.height: height * 2
            sourceSize.width: height * 2
            width: height
        }
        // "add a report"
        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: -parent.width * 0.08
            border.color: styler.navYellow
            border.width: Math.max(2, Math.round(parent.width * 0.04))
            color: styler.ink
            height: parent.width * 0.36
            radius: height / 2
            width: height
            Image {
                anchors.centerIn: parent
                height: parent.height * 0.62
                smooth: true
                source: Qt.resolvedUrl("icons/ui/plus-white.svg")
                sourceSize.height: height * 2
                sourceSize.width: height * 2
                width: height
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
