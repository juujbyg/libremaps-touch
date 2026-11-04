/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: the alert ahead, under the turn card while driving.
 * Shows the next alert on the route with its distance. Right after passing
 * a report by another driver, it asks whether it was still there.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.0
import QtGraphicalEffects 1.0
import "platform"

Item {
    id: banner
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: navigationCurrent.visible ? navigationCurrent.bottom : parent.top
    anchors.topMargin: navigationCurrent.visible ? 0 : gap
    height: card.height
    visible: opacity > 0
    opacity: shown ? 1 : 0
    z: 399

    property real u: styler.themePaddingMedium
    property real gap: Math.round(u * 0.65)
    property bool asking: alertWatch.passed !== null
    property var  alert: asking ? alertWatch.passed : alertWatch.next
    property bool shown: !app.modalDialog && alert !== null &&
                         (app.mode === modes.navigate || app.mode === modes.followMe)

    Behavior on opacity { NumberAnimation { duration: 220 } }

    // slide in from under the turn card
    property real slide: shown ? 0 : -u * 2
    Behavior on slide { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    transform: Translate { y: banner.slide }

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.leftMargin: banner.gap
        color: "white"
        height: Math.max(icon.height, textCol.height) + 1.6 * banner.u + (banner.asking ? buttons.height + banner.u : 0)
        radius: banner.u * 1.3
        width: app.portrait ? parent.width - 2 * banner.gap : Math.min(parent.width * 0.48, banner.u * 26)
        layer.enabled: true
        layer.effect: DropShadow {
            color: "#000000"
            opacity: 0.3
            radius: 12
            samples: 25
            verticalOffset: 3
        }

        Image {
            id: icon
            anchors.left: parent.left
            anchors.leftMargin: banner.u
            anchors.top: parent.top
            anchors.topMargin: banner.u * 0.8
            height: banner.u * 4
            smooth: true
            source: banner.alert ? alertWatch.iconUrl(banner.alert.type) : ""
            sourceSize.height: height
            sourceSize.width: height
            width: height
        }

        Column {
            id: textCol
            anchors.left: icon.right
            anchors.leftMargin: banner.u
            anchors.right: distLabel.left
            anchors.rightMargin: banner.u * 0.6
            anchors.verticalCenter: icon.verticalCenter
            spacing: banner.u * 0.1
            Text {
                color: "#1f2430"
                elide: Text.ElideRight
                font.bold: true
                font.pixelSize: banner.u * 1.55
                text: banner.asking ? app.tr("%1: still there?").arg(alertWatch.title(banner.alert))
                                    : alertWatch.title(banner.alert)
                width: parent.width
                wrapMode: Text.WordWrap
                maximumLineCount: 2
            }
            Text {
                color: "#5b6270"
                elide: Text.ElideRight
                font.pixelSize: banner.u * 1.1
                text: alertWatch.subtitle(banner.alert)
                width: parent.width
            }
        }

        Text {
            id: distLabel
            anchors.right: parent.right
            anchors.rightMargin: banner.u * 1.1
            anchors.verticalCenter: icon.verticalCenter
            color: "#1f2430"
            font.bold: true
            font.pixelSize: banner.u * 1.9
            text: !banner.asking && alertWatch.nextDist >= 0 ? banner.formatDist(alertWatch.nextDist) : ""
            visible: text.length > 0
        }

        Row {
            id: buttons
            anchors.bottom: parent.bottom
            anchors.bottomMargin: banner.u * 0.9
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: banner.u
            visible: banner.asking

            Repeater {
                model: [{"up": true, "label": app.tr("Yes, it's there"), "color": "#2e7d32"},
                        {"up": false, "label": app.tr("No, it's gone"), "color": "#5b6270"}]
                Rectangle {
                    color: mouse.pressed ? Qt.darker(modelData.color, 1.2) : modelData.color
                    height: banner.u * 3.6
                    radius: height / 2
                    width: (card.width - 3 * banner.u) / 2
                    Text {
                        anchors.centerIn: parent
                        color: "white"
                        font.bold: true
                        font.pixelSize: banner.u * 1.3
                        text: modelData.label
                    }
                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        anchors.margins: -banner.u * 0.3
                        onClicked: alertWatch.vote(banner.alert, modelData.up)
                    }
                }
            }
        }
    }

    function formatDist(m) {
        if (app.conf.units === "american" || app.conf.units === "british") {
            var ft = m * 3.28084;
            if (ft < 1000) return "%1 ft".arg(Math.round(ft / 50) * 50);
            return "%1 mi".arg((m / 1609.344).toFixed(1));
        }
        if (m < 1000) return "%1 m".arg(Math.max(10, Math.round(m / 10) * 10));
        return "%1 km".arg((m / 1000).toFixed(1));
    }
}
