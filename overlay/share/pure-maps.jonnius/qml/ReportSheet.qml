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
        opacity: sheet.open ? 0.4 * (1 - panel.pull / Math.max(1, panel.height)) : 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        MouseArea {
            anchors.fill: parent
            enabled: sheet.open
            onClicked: sheet.open = false
        }
    }

    Rectangle {
        id: panel
        border.color: styler.border
        border.width: 1
        color: styler.surface
        height: content.height + 4.4 * sheet.u + radius
        radius: sheet.u * 2
        width: parent.width
        y: (sheet.open ? parent.height - height + radius : parent.height) + pull
        Behavior on y {
            enabled: !drag.active
            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
        }

        // how far the finger has pulled the drawer down
        property real pull: 0

        // taps on the panel don't close it; a pull down past a quarter of it does
        MouseArea {
            id: drag
            anchors.fill: parent
            property real startY: 0
            property bool active: false
            onPressed: { startY = mouse.y + panel.y; active = true; }
            onPositionChanged: panel.pull = Math.max(0, mouse.y + panel.y - startY)
            onReleased: {
                active = false;
                if (panel.pull > panel.height / 4) sheet.open = false;
                panel.pull = 0;
            }
            onCanceled: { active = false; panel.pull = 0; }
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: sheet.u * 0.8
            color: styler.borderStrong
            height: sheet.u * 0.45
            radius: height / 2
            width: sheet.u * 4.5
        }

        Column {
            id: content
            anchors.left: parent.left
            anchors.leftMargin: sheet.u * 1.4
            anchors.right: parent.right
            anchors.rightMargin: sheet.u * 1.4
            anchors.top: parent.top
            anchors.topMargin: sheet.u * 2.6
            spacing: sheet.u

            Text {
                color: styler.ink
                font.family: styler.themeFontFamily
                font.pixelSize: sheet.u * 2
                font.weight: Font.DemiBold
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
                        color: tileMouse.pressed ? styler.subtle : styler.surface
                        border.color: styler.border
                        border.width: 1
                        height: width * 0.92
                        radius: styler.radiusLg
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
                            color: styler.ink
                            font.family: styler.themeFontFamily
                            font.pixelSize: sheet.u * 1.15
                            font.weight: Font.Medium
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
                color: styler.muted
                font.family: styler.themeFontFamily
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
