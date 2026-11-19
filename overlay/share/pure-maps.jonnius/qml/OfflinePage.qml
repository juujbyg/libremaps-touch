/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: maps, search and routes without internet, for any area in the
 * world. Tiles, fonts and icons come from OpenFreeMap (tiles.openfreemap.org).
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.9
import "."
import "platform"

PagePL {
    id: page
    title: app.tr("Offline maps")

    readonly property real margin: styler.themeHorizontalPageMargin
    readonly property real u: styler.themePaddingMedium
    readonly property var  st: offlineState
    readonly property bool hasMaps: st.info.regions.length > 0

    Column {
        id: column
        spacing: page.u
        width: page.width - 2 * page.margin
        x: page.margin

        Text {
            color: styler.muted
            font.family: styler.themeFontFamily
            font.pixelSize: styler.themeFontSizeSmall
            text: app.tr("Save areas over Wi-Fi to see the map, search places and find routes " +
                         "without internet, anywhere in the world. Data comes from OpenFreeMap " +
                         "and OpenStreetMap.")
            width: parent.width
            wrapMode: Text.WordWrap
        }

        Item { height: page.u * 0.5; width: 1 }

        // ---- use it
        Rectangle {
            border.color: styler.border
            border.width: 1
            color: styler.surface
            height: useRow.height + page.u * 2.4
            radius: styler.radiusLg
            visible: page.hasMaps
            width: parent.width

            Column {
                id: useRow
                anchors.left: parent.left
                anchors.leftMargin: page.u * 1.4
                anchors.right: toggle.left
                anchors.rightMargin: page.u
                anchors.verticalCenter: parent.verticalCenter
                spacing: page.u * 0.3
                Text {
                    color: styler.ink
                    font.family: styler.themeFontFamily
                    font.pixelSize: styler.themeFontSizeMedium
                    font.weight: Font.Medium
                    text: app.tr("Use offline map")
                    width: parent.width
                }
                Text {
                    color: styler.muted
                    font.family: styler.themeFontFamily
                    font.pixelSize: styler.themeFontSizeExtraSmall
                    text: page.st.inUse ?
                              app.tr("The map is drawn from your saved areas. Elsewhere it shows only a world overview.") :
                              app.tr("The map comes from the internet.")
                    width: parent.width
                    wrapMode: Text.WordWrap
                }
            }

            // switch
            Rectangle {
                id: toggle
                anchors.right: parent.right
                anchors.rightMargin: page.u * 1.4
                anchors.verticalCenter: parent.verticalCenter
                color: page.st.inUse ? styler.primary : styler.borderStrong
                height: styler.themeItemSizeSmall * 0.42
                radius: height / 2
                width: height * 1.8
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    color: styler.surface
                    height: parent.height - 4
                    radius: height / 2
                    width: height
                    x: page.st.inUse ? parent.width - width - 2 : 2
                    Behavior on x { NumberAnimation { duration: 120 } }
                }
            }
            MouseArea {
                anchors.fill: parent
                onClicked: page.st.use(!page.st.inUse)
            }
        }

        Item { height: page.u * 0.5; width: 1; visible: page.hasMaps }

        // ---- saved areas
        Text {
            color: styler.muted
            font.family: styler.themeFontFamily
            font.pixelSize: styler.themeFontSizeSmall
            font.weight: Font.Medium
            text: page.hasMaps ? app.tr("Saved areas · %1").arg(page.st.mb(page.st.info.size))
                               : app.tr("No saved areas yet")
        }

        Repeater {
            model: page.st.info.regions
            delegate: Rectangle {
                readonly property bool busyHere: page.st.busyId === modelData.id ||
                                                 (page.st.busyId === "new" && index === page.st.info.regions.length - 1 && !modelData.done)
                border.color: styler.border
                border.width: 1
                color: styler.surface
                height: areaCol.height + page.u * 2.4
                radius: styler.radiusLg
                width: column.width

                Rectangle {
                    id: areaIcon
                    anchors.left: parent.left
                    anchors.leftMargin: page.u * 1.2
                    anchors.top: parent.top
                    anchors.topMargin: page.u * 1.2
                    color: styler.subtle
                    height: styler.themeItemSizeSmall * 0.62
                    radius: styler.radiusMd
                    width: height
                    Image {
                        anchors.centerIn: parent
                        height: parent.height * 0.5
                        smooth: true
                        source: styler.icon("map-pin")
                        sourceSize.height: height * 2
                        sourceSize.width: width * 2
                        width: height
                    }
                }

                Column {
                    id: areaCol
                    anchors.left: areaIcon.right
                    anchors.leftMargin: page.u * 1.2
                    anchors.right: action.left
                    anchors.rightMargin: page.u
                    anchors.top: parent.top
                    anchors.topMargin: page.u * 1.2
                    spacing: page.u * 0.4
                    Text {
                        color: styler.ink
                        elide: Text.ElideRight
                        font.family: styler.themeFontFamily
                        font.pixelSize: styler.themeFontSizeMedium
                        font.weight: Font.Medium
                        text: modelData.name
                        width: parent.width
                    }
                    Text {
                        color: styler.muted
                        font.family: styler.themeFontFamily
                        font.pixelSize: styler.themeFontSizeExtraSmall
                        text: busyHere ? (page.st.removing ? app.tr("Removing…") :
                                          page.st.phase === "fonts" ? app.tr("Fonts and icons…") :
                                          page.st.phase === "index" ? app.tr("Preparing search and routes…") :
                                          app.tr("%1%").arg(Math.round(page.st.fraction * 100)))
                                       : modelData.done ? app.tr("Ready") : app.tr("Not finished")
                        width: parent.width
                    }
                    Rectangle {
                        color: styler.subtle
                        height: page.u * 0.5
                        radius: height / 2
                        visible: busyHere && !page.st.removing
                        width: parent.width
                        Rectangle {
                            color: styler.primary
                            height: parent.height
                            radius: height / 2
                            width: parent.width * page.st.fraction
                        }
                    }
                }

                // Cancel while downloading, Resume when unfinished, otherwise Remove
                Rectangle {
                    id: action
                    anchors.right: parent.right
                    anchors.rightMargin: page.u * 1.2
                    anchors.verticalCenter: parent.verticalCenter
                    border.color: styler.border
                    border.width: 1
                    color: actionMouse.pressed ? styler.subtle : styler.surface
                    height: styler.themeItemSizeSmall * 0.7
                    radius: styler.radiusMd
                    visible: !(busyHere && page.st.removing)
                    width: actionText.implicitWidth + page.u * 2.4
                    Text {
                        id: actionText
                        anchors.centerIn: parent
                        color: busyHere || modelData.done ? styler.ink : styler.ink
                        font.family: styler.themeFontFamily
                        font.pixelSize: styler.themeFontSizeSmall
                        font.weight: Font.Medium
                        text: busyHere ? app.tr("Cancel") : modelData.done ? app.tr("Remove") : app.tr("Resume")
                    }
                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        enabled: busyHere || !page.st.busy
                        onClicked: {
                            if (busyHere) page.st.cancel();
                            else if (modelData.done) page.st.remove(modelData.id);
                            else page.st.resume(modelData.id);
                        }
                    }
                }
            }
        }

        // the world overview, for areas saved before it existed
        Rectangle {
            border.color: styler.border
            border.width: 1
            color: ovMouse.pressed ? styler.subtle : styler.surface
            height: ovCol.height + page.u * 2.2
            radius: styler.radiusLg
            visible: page.hasMaps && !page.st.info.overview
            width: parent.width
            Column {
                id: ovCol
                anchors.left: parent.left
                anchors.leftMargin: page.u * 1.4
                anchors.right: parent.right
                anchors.rightMargin: page.u * 1.4
                anchors.verticalCenter: parent.verticalCenter
                spacing: page.u * 0.3
                Text {
                    color: styler.ink
                    font.family: styler.themeFontFamily
                    font.pixelSize: styler.themeFontSizeMedium
                    font.weight: Font.Medium
                    text: page.st.busyId === "overview" ?
                              app.tr("World overview: %1%").arg(Math.round(page.st.fraction * 100)) :
                              app.tr("Add a world overview")
                }
                Text {
                    color: styler.muted
                    font.family: styler.themeFontFamily
                    font.pixelSize: styler.themeFontSizeExtraSmall
                    text: app.tr("About 25 MB, so the offline map isn't blank outside your areas.")
                    width: parent.width
                    wrapMode: Text.WordWrap
                }
            }
            MouseArea {
                id: ovMouse
                anchors.fill: parent
                enabled: !page.st.busy
                onClicked: page.st.downloadOverview()
            }
        }

        // building offline search and routes for areas saved earlier
        Rectangle {
            border.color: styler.border
            border.width: 1
            color: styler.surface
            height: idxCol.height + page.u * 2.2
            radius: styler.radiusLg
            visible: page.st.busyId === "index"
            width: parent.width
            Column {
                id: idxCol
                anchors.left: parent.left
                anchors.leftMargin: page.u * 1.4
                anchors.right: parent.right
                anchors.rightMargin: page.u * 1.4
                anchors.verticalCenter: parent.verticalCenter
                spacing: page.u * 0.5
                Text {
                    color: styler.ink
                    font.family: styler.themeFontFamily
                    font.pixelSize: styler.themeFontSizeMedium
                    font.weight: Font.Medium
                    text: app.tr("Preparing search and routes… %1%").arg(Math.round(page.st.fraction * 100))
                    width: parent.width
                    wrapMode: Text.WordWrap
                }
                Rectangle {
                    color: styler.subtle
                    height: page.u * 0.5
                    radius: height / 2
                    width: parent.width
                    Rectangle {
                        color: styler.primary
                        height: parent.height
                        radius: height / 2
                        width: parent.width * page.st.fraction
                    }
                }
            }
        }

        Text {
            color: styler.danger
            font.family: styler.themeFontFamily
            font.pixelSize: styler.themeFontSizeSmall
            text: page.st.error
            visible: page.st.error !== ""
            width: parent.width
            wrapMode: Text.WordWrap
        }

        Item { height: page.u; width: 1 }

        ButtonPL {
            enabled: !page.st.busy
            text: app.tr("Save a new area")
            width: parent.width
            onClicked: {
                offlineState.picking = true;
                app.showMap();
            }
        }

        Item { height: page.u * 2; width: 1 }
    }

    Component.onCompleted: offlineState.refresh()
}
