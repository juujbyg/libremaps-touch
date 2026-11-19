/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: choose an area to save for offline use. The map on screen is the
 * area; a sheet at the bottom shows its size and downloads it.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.9
import QtGraphicalEffects 1.0
import "."
import "platform"

Item {
    id: picker
    anchors.fill: parent
    visible: offlineState.picking
    z: 900

    property var  estimate: null
    readonly property real u: styler.themePaddingMedium

    // a frame around the screen: everything inside it is saved
    Rectangle {
        anchors.fill: parent
        anchors.margins: picker.u
        border.color: styler.primary
        border.width: 3
        color: "transparent"
        opacity: 0.55
        radius: styler.radiusLg
    }

    Rectangle {
        id: sheet
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        color: styler.surface
        height: col.height + picker.u * 4
        radius: styler.radiusLg * 1.4
        layer.enabled: true
        layer.effect: DropShadow {
            color: styler.shadowColor
            opacity: styler.shadowOpacity
            radius: styler.shadowRadius
            samples: 1 + radius * 2
            verticalOffset: -2
        }
        // square off the bottom corners
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            color: parent.color
            height: parent.radius
        }
        MouseArea { anchors.fill: parent }  // taps on the sheet don't reach the map

        Column {
            id: col
            anchors.left: parent.left
            anchors.leftMargin: styler.themeHorizontalPageMargin
            anchors.right: parent.right
            anchors.rightMargin: styler.themeHorizontalPageMargin
            anchors.top: parent.top
            anchors.topMargin: picker.u * 2
            spacing: picker.u

            Text {
                color: styler.ink
                font.family: styler.themeFontFamily
                font.pixelSize: styler.themeFontSizeLarge
                font.weight: Font.DemiBold
                text: app.tr("Save this area")
            }
            Text {
                color: styler.muted
                font.family: styler.themeFontFamily
                font.pixelSize: styler.themeFontSizeSmall
                text: app.tr("Move and zoom the map: everything on screen is saved, at full detail.")
                width: parent.width
                wrapMode: Text.WordWrap
            }
            Text {
                color: picker.estimate && picker.estimate.too_big ? styler.danger : styler.ink
                font.family: styler.themeFontFamily
                font.pixelSize: styler.themeFontSizeMedium
                font.weight: Font.Medium
                text: !picker.estimate ? "…" :
                      picker.estimate.too_big ? app.tr("Too big: zoom in a little") :
                      app.tr("About %1").arg(picker.estimate.mb >= 1024 ?
                                                 app.tr("%1 GB").arg((picker.estimate.mb / 1024).toFixed(1)) :
                                                 app.tr("%1 MB").arg(Math.max(1, picker.estimate.mb)))
            }
            Item { height: picker.u * 0.5; width: 1 }
            Row {
                spacing: picker.u
                width: parent.width
                Rectangle {
                    border.color: styler.border
                    border.width: 1
                    color: cancelMouse.pressed ? styler.subtle : styler.surface
                    height: styler.themeItemSizeSmall * 0.9
                    radius: styler.radiusMd
                    width: (parent.width - picker.u) / 2
                    Text {
                        anchors.centerIn: parent
                        color: styler.ink
                        font.family: styler.themeFontFamily
                        font.pixelSize: styler.themeFontSizeMedium
                        font.weight: Font.Medium
                        text: app.tr("Cancel")
                    }
                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        onClicked: picker.close(false)
                    }
                }
                ButtonPL {
                    enabled: !!picker.estimate && !picker.estimate.too_big && !offlineState.busy
                    preferredWidth: (parent.width - picker.u) / 2
                    text: app.tr("Download")
                    onClicked: picker.close(true)
                }
            }
        }
    }

    Timer {
        id: recount
        interval: 350
        onTriggered: py.call("poor.offline.estimate", [offlineState.viewBbox()], function(e) {
            picker.estimate = e;
        })
    }

    Connections {
        target: map
        onCenterChanged: if (picker.visible) recount.restart()
        onZoomLevelChanged: if (picker.visible) recount.restart()
    }

    onVisibleChanged: {
        if (visible) {
            estimate = null;
            recount.restart();
        }
    }

    function close(download) {
        if (download) offlineState.downloadArea(offlineState.viewBbox());
        offlineState.picking = false;
        app.pushMain(Qt.resolvedUrl("OfflinePage.qml"));
    }
}
