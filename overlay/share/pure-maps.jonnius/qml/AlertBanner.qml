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
    anchors.bottom: referenceBlockBottom.top
    anchors.bottomMargin: gap
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

    // rise from the trip bar
    property real slide: shown ? 0 : u * 2
    Behavior on slide { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    transform: Translate { y: banner.slide }

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.leftMargin: banner.gap
        border.color: styler.border
        border.width: 1
        color: styler.surface
        height: Math.max(iconTile.height, textCol.height) + 2.4 * banner.u + (banner.asking ? buttons.height + banner.u : 0)
        radius: styler.radiusLg
        width: app.portrait ? parent.width - 2 * banner.gap : Math.min(parent.width * 0.48, banner.u * 26)
        layer.enabled: true
        layer.effect: DropShadow {
            color: "#000000"
            opacity: 0.22
            radius: 14
            samples: 29
            verticalOffset: 3
        }
        Rectangle {
            id: iconTile
            anchors.left: parent.left
            anchors.leftMargin: banner.u * 1.2
            anchors.top: parent.top
            anchors.topMargin: banner.u * 1.2
            color: styler.subtle
            height: banner.u * 5
            radius: styler.radiusMd
            width: height
        }
        Image {
            id: icon
            anchors.centerIn: iconTile
            height: banner.u * 3.6
            smooth: true
            source: banner.alert ? alertWatch.iconUrl(banner.alert.type) : ""
            sourceSize.height: height
            sourceSize.width: height
            width: height
        }

        Column {
            id: textCol
            anchors.left: iconTile.right
            anchors.leftMargin: banner.u * 1.2
            anchors.right: parent.right
            anchors.rightMargin: banner.u * 1.2
            anchors.verticalCenter: iconTile.verticalCenter
            spacing: banner.u * 0.1
            Text {
                color: styler.ink
                elide: Text.ElideRight
                font.family: styler.themeFontFamily
                font.pixelSize: banner.u * 1.75
                font.weight: Font.DemiBold
                lineHeight: 1.05
                text: {
                    if (banner.asking) return app.tr("%1: still there?").arg(alertWatch.title(banner.alert));
                    var t = alertWatch.title(banner.alert);
                    if (alertWatch.nextDist < 0) return t;
                    // "Speed camera  300 m": the distance in bold ink after the name
                    return t + "&nbsp;&nbsp;<font color='%1'>%2</font>".arg(styler.muted).arg(banner.formatDist(alertWatch.nextDist));
                }
                textFormat: Text.StyledText
                width: parent.width
                wrapMode: Text.WordWrap
                maximumLineCount: 2
            }
            Text {
                color: styler.muted
                elide: Text.ElideRight
                font.family: styler.themeFontFamily
                font.pixelSize: banner.u * 1.15
                text: alertWatch.subtitle(banner.alert)
                textFormat: Text.PlainText   // feed text: markup must never load anything
                width: parent.width
            }
        }

        Row {
            id: buttons
            anchors.bottom: parent.bottom
            anchors.bottomMargin: banner.u * 0.9
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: banner.u
            visible: banner.asking

            Repeater {
                model: [{"up": true, "label": app.tr("Yes, it's there"), "color": String(styler.primary)},
                        {"up": false, "label": app.tr("No, it's gone"), "color": "#71717a"}]
                Rectangle {
                    color: mouse.pressed ? Qt.darker(modelData.color, 1.2) : modelData.color
                    height: banner.u * 3.6
                    radius: styler.radiusMd
                    width: (card.width - 3 * banner.u) / 2
                    Text {
                        anchors.centerIn: parent
                        color: modelData.up ? styler.primaryText : "white"
                        font.family: styler.themeFontFamily
                        font.pixelSize: banner.u * 1.3
                        font.weight: Font.Medium
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
