/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: the maneuver card at the top while navigating.
 *
 * A dark floating card: the next turn in an amber bubble, the distance in
 * big numbers, and the street. A thin amber bar fills as the turn gets
 * closer, the bubble pulses for the last few metres, and each new turn
 * slides in. Below the card, a small chip shows the turn after it.
 * After arriving, the card says so.
 *
 * Based on Pure Maps' NavigationCurrentBlock (GPL-3.0-or-later),
 * Copyright (C) 2014 Osmo Salomaa, 2018 Rinigus.
 */

import QtQuick 2.0
import QtQml 2.2
import QtGraphicalEffects 1.0
import "platform"
import "."

Item {
    id: block
    anchors.left: parent.left
    anchors.top: parent.top
    height: visible ? card.y + card.height + (thenChip.visible ? thenChip.height + gap : 0) + gap : 0
    visible: !app.modalDialog && (app.mode === modes.navigate || app.mode === modes.navigatePost)
    width: parent.width
    z: 400

    // contract with RootPage: nothing sticks out of the block
    property real marginExtraLeft: 0
    property real marginExtraLeftSide: 0
    property real marginExtraRight: 0
    property real marginExtraRightSide: 0

    property bool   arrived:   app.mode === modes.navigatePost
    // Before the navigator has placed us on the route (standing at the start,
    // or the first metres), it says only "Preparing to start navigation".
    // Show the first real turn instead, like other navigation apps do.
    property bool   preparing: app.navigator.icon === "navigation-start" && prep.narrative !== ""
    property var    prep: ({"icon": "", "narrative": "", "dist": ""})
    property string icon:      preparing ? prep.icon : app.navigator.icon
    property string manDist:   preparing ? prep.dist : app.navigator.manDist
    property string narrative: preparing ? prep.narrative : app.navigator.narrative

    Instantiator {
        id: firstTurns
        model: app.navigator.maneuvers
        delegate: QtObject {
            property string ic: model.icon ? model.icon : ""
            property string na: model.narrative ? model.narrative : ""
            property string le: model.length ? model.length : ""
        }
        onObjectAdded: prepTimer.restart()
        onObjectRemoved: prepTimer.restart()
    }
    Timer {
        id: prepTimer
        interval: 50
        onTriggered: {
            if (firstTurns.count < 2) {
                block.prep = {"icon": "", "narrative": "", "dist": ""};
                return;
            }
            var a = firstTurns.objectAt(0), b = firstTurns.objectAt(1);
            block.prep = {"icon": b.ic, "narrative": b.na, "dist": a.le};
        }
    }
    property string nextIcon:  app.navigator.nextIcon
    property string nextManDist: app.navigator.nextManDist
    property bool   notify:    app.navigator.notify
    property int    roundaboutExit: app.navigator.roundaboutExit
    property string street:    app.navigator.street ? app.navigator.street : ""

    // sizes, in grid units (styler.themePaddingMedium is one)
    property real u:   styler.themePaddingMedium
    property real gap: Math.round(u * 0.65)

    // colours: the card stays dark in day and night, for contrast on any map
    readonly property color cardBg:   styler.hudDark
    readonly property color cardText: "#ffffff"
    readonly property color cardMuted: styler.hudDarkMuted

    // distance to the turn in metres, parsed from the formatted string
    property real meters: toMeters(manDist)
    property real startMeters: 0
    property real approach: startMeters > 0 && meters >= 0 ? Math.max(0, Math.min(1, 1 - meters / startMeters)) : 0
    property bool near: notify && !arrived && meters >= 0 && meters <= 40

    property var _dist: splitDistance(arrived ? "" : manDist)

    onIconChanged: newManeuver()
    onNarrativeChanged: newManeuver()
    onMetersChanged: if (meters > startMeters) startMeters = meters
    onArrivedChanged: if (arrived) arriveAnim.restart()

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.leftMargin: block.gap
        anchors.top: parent.top
        anchors.topMargin: block.gap
        border.color: styler.hudDarkRaised
        border.width: 1
        color: cardMouse.pressed ? styler.hudDarkRaised : block.cardBg
        height: Math.max(bubble.height + 2.4 * block.u, textColumn.height + 2.4 * block.u)
        radius: block.u * 1.6
        width: app.portrait ? parent.width - 2 * block.gap : Math.min(parent.width * 0.48, block.u * 26)
        layer.enabled: true
        layer.effect: DropShadow {
            color: "#000000"
            opacity: 0.35
            radius: 14
            samples: 29
            verticalOffset: 4
        }

        Behavior on color { ColorAnimation { duration: 120 } }

        MouseArea {
            id: cardMouse
            anchors.fill: parent
            onClicked: if (!block.arrived) app.showNavigationPages()
        }

        // the turn: a big white arrow
        Rectangle {
            id: bubble
            anchors.left: parent.left
            anchors.leftMargin: block.u * 0.8
            anchors.verticalCenter: parent.verticalCenter
            color: "transparent"
            height: block.u * 6
            radius: block.u * 1.4
            width: height

            Image {
                id: iconImage
                anchors.centerIn: parent
                smooth: true
                source: {
                    var name = block.arrived ? "flag" : (block.notify ? (block.icon || "flag") : "away-from-route");
                    return "icons/navigation/%1-white.svg".arg(name);
                }
                sourceSize.height: parent.height * 0.86
                sourceSize.width: parent.height * 0.86
            }

            Rectangle {
                // roundabout exit number, as a badge on the corner
                anchors.horizontalCenter: parent.right
                anchors.horizontalCenterOffset: -parent.width * 0.08
                anchors.verticalCenter: parent.bottom
                anchors.verticalCenterOffset: -parent.height * 0.08
                border.color: "white"
                border.width: block.u * 0.15
                color: block.cardBg
                height: parent.height * 0.42
                radius: height / 2
                visible: block.notify && !block.arrived && block.roundaboutExit > 0
                width: height
                Text {
                    anchors.centerIn: parent
                    color: "white"
                    font.bold: true
                    font.pixelSize: parent.height * 0.6
                    text: block.roundaboutExit
                }
            }

            // breathe for the last metres before the turn
            SequentialAnimation on scale {
                loops: Animation.Infinite
                running: block.near
                NumberAnimation { to: 1.07; duration: 420; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1.0;  duration: 420; easing.type: Easing.InOutSine }
                onRunningChanged: if (!running) bubble.scale = 1.0
            }
        }

        // ripple when arriving
        Rectangle {
            id: ripple
            anchors.centerIn: bubble
            border.color: styler.navSky
            border.width: block.u * 0.25
            color: "transparent"
            height: bubble.height
            opacity: 0
            radius: bubble.radius * 1.4
            width: height
        }

        Column {
            id: textColumn
            anchors.left: bubble.right
            anchors.leftMargin: block.u * 0.6
            anchors.right: parent.right
            anchors.rightMargin: block.u * 1.2
            anchors.verticalCenter: parent.verticalCenter
            spacing: block.u * 0.1

            property real slide: 0
            transform: Translate { y: textColumn.slide }

            Row {
                // distance: big number, small unit
                spacing: block.u * 0.35
                visible: !block.arrived && block._dist[0].length > 0
                RollingNumber {
                    id: distNumber
                    color: block.near ? styler.navSky : block.cardText
                    pixelSize: block.u * 4.6
                    text: block._dist[0]
                    weight: Font.Bold
                }
                Text {
                    anchors.bottom: distNumber.bottom
                    anchors.bottomMargin: block.u * 0.75
                    color: block.near ? styler.navSky : block.cardMuted
                    font.family: styler.themeFontFamilyHeading
                    font.pixelSize: block.u * 2.1
                    font.weight: Font.DemiBold
                    text: block._dist[1]
                }
            }

            Text {
                // street (sky blue), or the instruction when there is no street name
                color: !block.arrived && block.notify && block.street.length > 0 ? styler.navStreet : block.cardText
                elide: Text.ElideRight
                font.family: styler.themeFontFamily
                font.weight: !block.arrived && block.street.length > 0 ? Font.DemiBold : Font.Normal
                font.pixelSize: block.arrived ? block.u * 2.7 : block.u * 2.15
                maximumLineCount: 2
                text: {
                    if (block.arrived) return app.tr("You have arrived");
                    if (!block.notify) return app.tr("Head to the route");
                    return block.street || block.narrative;
                }
                width: parent.width
                wrapMode: Text.WordWrap
            }
        }

        // how close the turn is: fills from left to right
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            color: "transparent"
            clip: true
            height: block.u * 0.42
            radius: card.radius
            visible: block.notify && !block.arrived
            Rectangle {
                anchors.bottom: parent.bottom
                color: styler.navSky
                height: parent.height
                width: parent.width * block.approach
                Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            }
        }
    }

    // the turn after this one
    Rectangle {
        id: thenChip
        anchors.left: card.left
        anchors.leftMargin: block.u * 0.6
        anchors.top: card.bottom
        anchors.topMargin: -block.u * 0.2
        color: styler.hudDarkRaised
        height: block.u * 3.3
        radius: block.u * 0.7
        visible: block.notify && !block.arrived && block.nextIcon.length > 0
        width: thenRow.width + 2 * block.u * 0.9
        z: -1

        Row {
            id: thenRow
            anchors.centerIn: parent
            anchors.verticalCenterOffset: block.u * 0.1
            spacing: block.u * 0.45
            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: block.cardMuted
                font.family: styler.themeFontFamily
                font.pixelSize: block.u * 1.4
                text: app.tr("Then")
            }
            Image {
                anchors.verticalCenter: parent.verticalCenter
                smooth: true
                source: block.nextIcon ? "icons/navigation/%1-white.svg".arg(block.nextIcon) : ""
                sourceSize.height: block.u * 2.3
                sourceSize.width: block.u * 2.3
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                color: block.cardText
                font.family: styler.themeFontFamily
                font.pixelSize: block.u * 1.4
                font.weight: Font.DemiBold
                text: block.nextManDist
                visible: text.length > 0
            }
        }
    }

    // a new turn slides in
    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: textColumn; property: "slide"; from: block.u * 1.4; to: 0; duration: 320; easing.type: Easing.OutCubic }
        NumberAnimation { target: textColumn; property: "opacity"; from: 0; to: 1; duration: 260 }
        NumberAnimation { target: bubble; property: "scale"; from: 0.7; to: 1; duration: 420; easing.type: Easing.OutBack }
    }

    // arriving: the bubble pops and a ring spreads out from it
    ParallelAnimation {
        id: arriveAnim
        NumberAnimation { target: bubble; property: "scale"; from: 0.5; to: 1; duration: 600; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
        SequentialAnimation {
            PauseAnimation { duration: 150 }
            ParallelAnimation {
                NumberAnimation { target: ripple; property: "scale"; from: 1; to: 2.2; duration: 900; easing.type: Easing.OutCubic }
                NumberAnimation { target: ripple; property: "opacity"; from: 0.9; to: 0; duration: 900 }
            }
        }
    }

    function newManeuver() {
        startMeters = meters > 0 ? meters : 0;
        if (visible && !arrived) enterAnim.restart();
    }

    function splitDistance(s) {
        // "1.2 km" -> ["1.2", "km"]; no number (such as "-") shows nothing
        var m = (s || "").match(/^\s*([0-9]+(?:[.,][0-9]+)?)\s*(.*)$/);
        return m ? [m[1], m[2]] : ["", ""];
    }

    function toMeters(s) {
        var m = (s || "").match(/^\s*([0-9]+(?:[.,][0-9]+)?)\s*([a-zA-Z]+)/);
        if (!m) return -1;
        var v = parseFloat(m[1].replace(",", "."));
        var f = { "m": 1, "km": 1000, "ft": 0.3048, "yd": 0.9144, "mi": 1609.344 }[m[2].toLowerCase()];
        return f ? v * f : -1;
    }
}
