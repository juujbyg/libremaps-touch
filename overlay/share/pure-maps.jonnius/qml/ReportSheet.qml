/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: report something on the road. Six big tiles, one tap each,
 * so it can be used at a glance. The report is public and anonymous: it
 * shares this spot, the direction of travel and the time, nothing else.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.0

Item {
    id: sheet
    anchors.fill: parent
    visible: open || panel.y < height
    z: 1000

    property bool open: false
    property real u: styler.themePaddingMedium

    // close when the app leaves the map
    Connections {
        target: app
        onModeChanged: if (sheet.open && app.mode !== modes.navigate &&
                           app.mode !== modes.followMe && app.mode !== modes.explore) sheet.open = false
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: sheet.open ? 0.4 : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea {
            anchors.fill: parent
            enabled: sheet.open
            onClicked: sheet.open = false
        }
    }

    Rectangle {
        id: panel
        color: styler.hudBg
        height: content.height + 3 * sheet.u + radius
        radius: sheet.u * 1.6
        width: parent.width
        y: sheet.open ? parent.height - height + radius : parent.height
        Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }   // taps on the panel don't close it

        Column {
            id: content
            anchors.left: parent.left
            anchors.leftMargin: sheet.u * 1.4
            anchors.right: parent.right
            anchors.rightMargin: sheet.u * 1.4
            anchors.top: parent.top
            anchors.topMargin: sheet.u * 1.4
            spacing: sheet.u

            Text {
                color: styler.hudText
                font.bold: true
                font.pixelSize: sheet.u * 2
                text: app.tr("Report")
            }

            Grid {
                id: grid
                columns: 3
                spacing: sheet.u * 0.8
                width: parent.width

                Repeater {
                    model: alertWatch.reportTypes
                    Rectangle {
                        color: tileMouse.pressed ? Qt.darker(styler.hudBg, 1.12) : Qt.darker(styler.hudBg, 1.05)
                        border.color: Qt.darker(styler.hudBg, 1.15)
                        border.width: 1
                        height: width * 0.92
                        radius: sheet.u
                        scale: tileMouse.pressed ? 0.95 : 1
                        width: (grid.width - 2 * grid.spacing) / 3
                        Behavior on scale { NumberAnimation { duration: 80 } }

                        Image {
                            id: tileIcon
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            anchors.topMargin: parent.height * 0.12
                            height: parent.height * 0.5
                            smooth: true
                            source: alertWatch.iconUrl(modelData)
                            sourceSize.height: height
                            sourceSize.width: height
                            width: height
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: tileIcon.bottom
                            anchors.topMargin: parent.height * 0.06
                            color: styler.hudText
                            font.bold: true
                            font.pixelSize: sheet.u * 1.15
                            horizontalAlignment: Text.AlignHCenter
                            text: sheet.label(modelData)
                            width: parent.width - sheet.u
                            wrapMode: Text.WordWrap
                        }
                        MouseArea {
                            id: tileMouse
                            anchors.fill: parent
                            onClicked: {
                                alertWatch.report(modelData);
                                sheet.open = false;
                            }
                        }
                    }
                }
            }

            Text {
                color: styler.hudMuted
                font.pixelSize: sheet.u * 1.15
                lineHeight: 1.1
                text: app.tr("Reports are public and anonymous. They share only this spot, your direction and the time, through Nostr relays, and disappear on their own.")
                width: parent.width
                wrapMode: Text.WordWrap
            }
        }
    }

    function label(type) {
        switch (type) {
        case "police": return app.tr("Police");
        case "accident": return app.tr("Accident");
        case "hazard": return app.tr("Hazard");
        case "closed": return app.tr("Road closed");
        case "jam": return app.tr("Traffic jam");
        case "camera": return app.tr("Speed camera");
        }
        return type;
    }
}
