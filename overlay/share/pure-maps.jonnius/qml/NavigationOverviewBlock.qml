/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: the trip sheet at the bottom while navigating.
 *
 * Arrival time in big numbers, then time and distance left, and a round
 * End button. The amber bar along the top shows how much of the trip is
 * done. With a stop on the way, it shows the next stop instead.
 * Tapping the sheet opens the list of turns.
 *
 * Based on Pure Maps' NavigationOverviewBlock (GPL-3.0-or-later),
 * Copyright (C) 2014 Osmo Salomaa, 2018 Rinigus.
 */

import QtQuick 2.0
import QtGraphicalEffects 1.0
import "platform"
import "."

Item {
    id: block
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: visible ? sheet.height - sheet.radius : 0
    visible: !app.modalDialog && app.mode === modes.navigate
    z: 400

    // contract with RootPage and others
    property bool showAtBottom: true
    property bool streetNameInOverview: false
    property real marginExtraLeft: 0
    property real marginExtraLeftSide: 0
    property real marginExtraRight: 0
    property real marginExtraRightSide: 0

    property bool   showNextLocation: navigator.hasNextLocation
    property string destDist:  showNextLocation ? navigator.nextLocationDist : app.navigator.destDist
    property string destEta:   showNextLocation ? navigator.nextLocationEta : app.navigator.destEta
    property string destTime:  showNextLocation ? navigator.nextLocationTime : app.navigator.destTime

    property real u: styler.themePaddingMedium

    Rectangle {
        id: sheet
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        color: sheetMouse.pressed ? styler.blockPressed : styler.hudBg
        height: content.height + 4.4 * block.u + radius
        radius: block.u * 1.4
        // only the top corners are round: the sheet runs off the bottom
        anchors.bottomMargin: -radius
        layer.enabled: true
        layer.effect: DropShadow {
            color: "#000000"
            opacity: 0.25
            radius: 16
            samples: 33
            verticalOffset: -2
        }

        MouseArea {
            id: sheetMouse
            anchors.fill: parent
            onClicked: app.showNavigationPages()
        }

        // grab handle, a hint that the sheet opens
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: block.u * 0.55
            color: styler.hudMuted
            height: block.u * 0.22
            opacity: 0.45
            radius: height / 2
            width: block.u * 2.6
        }

        // trip progress
        Rectangle {
            id: track
            anchors.left: parent.left
            anchors.leftMargin: block.u * 1.6
            anchors.right: endButton.left
            anchors.rightMargin: block.u * 1.6
            anchors.top: parent.top
            anchors.topMargin: block.u * 1.7
            color: "transparent"
            height: block.u * 0.4
            radius: height / 2
            Rectangle {
                anchors.fill: parent
                color: styler.hudText
                opacity: 0.12
                radius: parent.radius
            }
            Rectangle {
                id: done
                color: styler.amber
                height: parent.height
                radius: parent.radius
                width: Math.max(height, parent.width * Math.max(0, Math.min(1, app.navigator.progress)))
                Behavior on width { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }
            }
            Rectangle {
                // you are here
                anchors.verticalCenter: parent.verticalCenter
                border.color: styler.amber
                border.width: block.u * 0.18
                color: styler.hudBg
                height: block.u * 1.1
                radius: height / 2
                width: height
                x: done.width - width / 2
            }
        }

        Column {
            id: content
            anchors.left: track.left
            anchors.right: track.right
            anchors.top: track.bottom
            anchors.topMargin: block.u * 0.9
            spacing: block.u * 0.05

            Row {
                spacing: block.u * 0.5
                Text {
                    id: eta
                    color: styler.hudText
                    font.bold: true
                    font.family: styler.themeFontFamilyHeading
                    font.pixelSize: block.u * 3.4
                    text: block.known(block.destEta) ? block.destEta : "--:--"
                }
                Text {
                    anchors.baseline: eta.baseline
                    color: styler.hudMuted
                    font.pixelSize: block.u * 1.45
                    text: block.showNextLocation ?
                              (navigator.nextLocationDestination ? app.tr("arrival") : app.tr("at next stop")) :
                              app.tr("arrival")
                }
            }

            Row {
                spacing: block.u * 0.55
                visible: block.known(block.destTime) || block.known(block.destDist)
                Text {
                    color: styler.accentText
                    font.bold: true
                    font.pixelSize: block.u * 1.75
                    text: block.destTime
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    color: styler.hudMuted
                    height: block.u * 0.38
                    radius: height / 2
                    width: height
                }
                Text {
                    color: styler.hudMuted
                    font.bold: true
                    font.pixelSize: block.u * 1.75
                    text: block.destDist
                }
            }
        }

        // end navigation
        Rectangle {
            id: endButton
            anchors.right: parent.right
            anchors.rightMargin: block.u * 1.6
            anchors.top: parent.top
            anchors.topMargin: (sheet.height - sheet.radius - height) / 2 - block.u * 0.2
            color: endMouse.pressed ? "#c62828" : "#e53935"
            height: block.u * 4.6
            radius: height / 2
            scale: endMouse.pressed ? 0.92 : 1
            width: height
            Behavior on scale { NumberAnimation { duration: 90 } }

            // a white cross
            Repeater {
                model: 2
                Rectangle {
                    anchors.centerIn: parent
                    antialiasing: true
                    color: "white"
                    height: block.u * 0.38
                    radius: height / 2
                    rotation: index === 0 ? 45 : -45
                    width: endButton.width * 0.42
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.bottom
                anchors.topMargin: block.u * 0.2
                color: styler.hudMuted
                font.pixelSize: block.u * 1.15
                text: app.tr("End")
            }

            MouseArea {
                id: endMouse
                anchors.fill: parent
                anchors.margins: -block.u * 0.6
                onClicked: {
                    notification.flash(app.tr("Navigation stopped"), "navigationStartPause");
                    app.navigator.running = false;
                }
            }
        }
    }

    function known(s) {
        // the navigator shows "-" until it has numbers
        return !!s && /[0-9]/.test(s);
    }

    function openNavigation() {
        if (visible) app.showNavigationPages()
    }
}
