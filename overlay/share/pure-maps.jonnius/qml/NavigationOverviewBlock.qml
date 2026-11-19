/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: the trip bar at the bottom while navigating, Waze style.
 *
 * A round × on the left ends navigation. Next to it, the time left in big
 * numbers and, under it, the arrival time and the distance left. With a stop
 * on the way, it shows the next stop instead. Tapping the bar opens the list
 * of turns.
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
        // only the top corners are round: the sheet runs off the bottom
        anchors.bottomMargin: -radius
        border.color: styler.border
        border.width: 1
        color: sheetMouse.pressed ? styler.subtle : styler.surface
        height: Math.max(endButton.height, content.height) + 3.6 * block.u + radius
        radius: block.u * 1.6
        layer.enabled: true
        layer.effect: DropShadow {
            color: "#000000"
            opacity: 0.14
            radius: 16
            samples: 33
            verticalOffset: -2
        }

        MouseArea {
            id: sheetMouse
            anchors.fill: parent
            onClicked: app.showNavigationPages()
        }

        // grab handle, a hint that the bar opens
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: block.u * 0.55
            color: styler.borderStrong
            height: block.u * 0.3
            radius: height / 2
            width: block.u * 2.6
        }

        // end navigation: a round ×
        Rectangle {
            id: endButton
            anchors.left: parent.left
            anchors.leftMargin: block.u * 1.4
            anchors.top: parent.top
            anchors.topMargin: (sheet.height - sheet.radius - height) / 2 + block.u * 0.2
            color: endMouse.pressed ? styler.borderStrong : styler.subtle
            height: block.u * 4.4
            radius: height / 2
            scale: endMouse.pressed ? 0.92 : 1
            width: height
            Behavior on scale { NumberAnimation { duration: 90 } }

            Image {
                anchors.centerIn: parent
                height: parent.height * 0.44
                smooth: true
                source: styler.icon("x")
                sourceSize.height: height * 2
                sourceSize.width: height * 2
                width: height
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

        Column {
            id: content
            anchors.left: endButton.right
            anchors.leftMargin: block.u * 1.4
            anchors.right: parent.right
            anchors.rightMargin: block.u * 1.4
            anchors.verticalCenter: endButton.verticalCenter
            spacing: block.u * 0.15

            Row {
                spacing: block.u * 0.6
                RollingNumber {
                    id: timeLeft
                    color: styler.ink
                    pixelSize: block.u * 2.7
                    text: block.known(block.destTime) ? block.destTime : "--"
                    weight: Font.Bold
                }
                Text {
                    anchors.bottom: timeLeft.bottom
                    anchors.bottomMargin: block.u * 0.4
                    color: styler.muted
                    font.family: styler.themeFontFamily
                    font.pixelSize: block.u * 1.3
                    font.weight: Font.Medium
                    text: navigator.nextLocationDestination ? "" : app.tr("to next stop")
                    visible: block.showNextLocation && text.length > 0
                }
            }

            Row {
                spacing: block.u * 0.55
                visible: block.known(block.destEta) || block.known(block.destDist)
                RollingNumber {
                    color: styler.muted
                    pixelSize: block.u * 1.6
                    text: block.destEta
                    visible: block.known(block.destEta)
                    weight: Font.Medium
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    color: styler.borderStrong
                    height: block.u * 0.36
                    radius: height / 2
                    visible: block.known(block.destEta) && block.known(block.destDist)
                    width: height
                }
                RollingNumber {
                    color: styler.muted
                    pixelSize: block.u * 1.6
                    text: block.destDist
                    visible: block.known(block.destDist)
                    weight: Font.Medium
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
