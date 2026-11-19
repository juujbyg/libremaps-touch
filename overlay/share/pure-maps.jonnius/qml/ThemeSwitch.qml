/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: Theme row in the menu. Light / Dark pick the day or night map and the
 * matching interface; Auto switches at sunrise and sunset where you are.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.0
import "."

Item {
    id: row
    height: Math.round(u * 7)
    width: parent ? parent.width : 0

    property real   u: styler.themePaddingMedium
    readonly property string current: app.conf.basemapAutoLight === "sunrise/sunset" ? "auto" :
                                      app.conf.basemapLight === "night" ? "dark" : "light"

    Text {
        anchors.left: parent.left
        anchors.leftMargin: styler.themeHorizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        color: styler.ink
        font.family: styler.themeFontFamily
        font.pixelSize: styler.themeFontSizeMedium
        text: app.tr("Theme")
    }

    Rectangle {
        // segmented control, shadcn "tabs" style
        id: track
        anchors.right: parent.right
        anchors.rightMargin: styler.themeHorizontalPageMargin
        anchors.verticalCenter: parent.verticalCenter
        color: styler.subtle
        height: Math.round(row.u * 4.6)
        radius: styler.radiusMd
        width: segments.width + row.u * 0.8

        Row {
            id: segments
            anchors.centerIn: parent

            Repeater {
                model: [{"id": "light", "label": app.tr("Light")},
                        {"id": "dark", "label": app.tr("Dark")},
                        {"id": "auto", "label": app.tr("Auto")}]
                delegate: Rectangle {
                    color: on ? styler.surface : "transparent"
                    border.color: on ? styler.border : "transparent"
                    border.width: 1
                    height: track.height - row.u * 0.8
                    radius: styler.radiusSm
                    width: Math.max(Math.round(row.u * 7.5), label.implicitWidth + row.u * 2)

                    property bool on: row.current === modelData.id

                    Accessible.name: modelData.label
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: on

                    Text {
                        id: label
                        anchors.centerIn: parent
                        color: parent.on ? styler.ink : styler.muted
                        font.family: styler.themeFontFamily
                        font.pixelSize: Math.round(row.u * 1.45)
                        font.weight: parent.on ? Font.DemiBold : Font.Normal
                        text: modelData.label
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: row.choose(modelData.id)
                    }
                }
            }
        }
    }

    function choose(id) {
        if (id === current) return;
        if (id === "auto") {
            // the map's sunrise/sunset timer takes over (it needs a position); its day/night
            // bias only counts while the manual choice is empty ("any")
            app.conf.set("basemap_auto_light", "sunrise/sunset");
            app.conf.set("basemap_light", "");
            py.call_sync("poor.app.basemap._find_map", []);
        } else {
            app.conf.set("basemap_auto_light", "none");
            app.conf.set("basemap_light", id === "dark" ? "night" : "day");
            py.call_sync("poor.app.basemap._find_map", []);
        }
        // the config is otherwise saved only when the app quits cleanly
        py.call("poor.conf.write", []);
    }
}
