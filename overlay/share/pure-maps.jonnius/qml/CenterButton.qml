/* -*- coding: utf-8-unix -*-
 *
 * Copyright (C) 2018 Osmo Salomaa, 2018 Rinigus
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.0
import "platform"

MapButton {
    id: button
    anchors.top: northArrow.bottom
    anchors.right: parent.right
    // never disabled: with no fix yet a tap says so, instead of doing nothing
    active: map.autoCenter
    iconHeight: styler.themeIconSizeSmall * 1.25
    iconSource: map.autoCenter ? Qt.resolvedUrl("icons/locate-on.svg")
                               : gps.coordinateValid ? Qt.resolvedUrl("icons/locate.svg")
                                                     : Qt.resolvedUrl("icons/locate-off.svg")
    states: [
        State {
            when: !hidden && (app.mode === modes.explore || app.mode === modes.exploreRoute)
            AnchorChanges {
                target: button
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.top: undefined
            }
        },
        State {
            when: hidden && (app.mode === modes.navigate || app.mode === modes.followMe || app.mode === modes.navigatePost) && !app.portrait
            AnchorChanges {
                target: button
                anchors.bottom: navigationSign.bottom
                anchors.left: undefined
                anchors.right: northArrow.left
                anchors.top: undefined
            }
        },
        State {
            when: hidden && (app.mode === modes.navigate || app.mode === modes.followMe || app.mode === modes.navigatePost)
            AnchorChanges {
                target: button
                anchors.bottom: undefined
                anchors.left: parent.right
                anchors.right: undefined
                anchors.top: northArrow.bottom
            }
        },
        State {
            when: hidden
            AnchorChanges {
                target: button
                anchors.bottom: undefined
                anchors.left: parent.right
                anchors.right: undefined
                anchors.top: northArrow.bottom
            }
        },
        State {
            when: (app.mode === modes.navigate || app.mode === modes.followMe || app.mode === modes.navigatePost) && !app.portrait
            AnchorChanges {
                target: button
                anchors.bottom: undefined
                anchors.left: undefined
                anchors.right: northArrow.left
                anchors.top: navigationSign.bottom
            }
        },
        State {
            when: (app.mode === modes.navigate || app.mode === modes.followMe || app.mode === modes.navigatePost)
            AnchorChanges {
                target: button
                anchors.bottom: undefined
                anchors.left: undefined
                anchors.right: parent.right
                anchors.top: northArrow.bottom
            }
        }
    ]
    transitions: Transition {
        AnchorAnimation {
            id: animator
            duration: 0
        }
        onRunningChanged: {
            if (running) button.visible = true;
            else if (hidden) button.visible = false;
            else button.visible = true;
            if (!running) animator.duration = 0;
        }
    }
    z: 500

    // while navigating it shows only after the map was moved away from you
    property bool hidden: app.modalDialog || app.infoPanelOpen ||
                          (app.mode === modes.navigate && map.autoCenter) ||
                          (map.cleanMode && !app.conf.mapModeCleanShowCenter)
    property bool nextClickToAuto: false

    Timer {
        id: timer
        interval: 5000
        repeat: false
        onTriggered: button.nextClickToAuto = false;
    }

    // while the phone is still looking for a fix, the button breathes
    SequentialAnimation on opacity {
        loops: Animation.Infinite
        running: !gps.coordinateValid
        NumberAnimation { to: 0.45; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) button.opacity = 1.0
    }

    onClicked: {
        // same ID is used as in MapGestureArea
        var notifyId = "centerButton";
        if (!gps.coordinateValid) {
            notification.flash(app.tr("Looking for your location\u2026"), notifyId);
            return;
        }
        if (app.map.autoCenter) {
            app.map.autoCenter = false;
            notification.flash(app.tr("Following off"),
                               notifyId);
            return;
        }

        map.centerOnPosition();
        if (nextClickToAuto) {
            map.autoCenter = true;
            notification.flash(app.tr("Following you: the map stays on your position"),
                               notifyId);
        }
        else {
            nextClickToAuto = true;
            timer.restart();
            notification.flash(app.tr("Centered on you. Tap again to keep following"),
                               notifyId,
                               timer.interval / 1000);
        }
    }

    onHiddenChanged: animator.duration = app.conf.animationDuration;
}
