/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: download a region of the map to use without internet.
 * Tiles, fonts and icons come from OpenFreeMap (tiles.openfreemap.org).
 */

import QtQuick 2.0
import "."
import "platform"

PagePL {
    id: page
    title: app.tr("Offline maps")

    property string busyId: ""
    property string phase: ""
    property real   done: 0
    property real   total: 1
    property string error: ""
    property var    regions: []

    function mb(b) { return (b / 1048576).toFixed(0) + " MB"; }

    function refresh() { regions = py.evaluate("poor.offline.status()"); }

    Column {
        id: column
        width: page.width
        spacing: styler.themePaddingLarge

        LabelPL {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: styler.themeHorizontalPageMargin
            anchors.rightMargin: styler.themeHorizontalPageMargin
            color: styler.themeSecondaryHighlightColor
            font.pixelSize: styler.themeFontSizeSmall
            text: app.tr("Download a region over Wi-Fi to see the map without internet. " +
                         "Map drawing works offline; searching and routing still need a connection. " +
                         "Data comes from OpenFreeMap (tiles.openfreemap.org). " +
                         "Afterwards choose the map \"Drive Offline\" in Maps. " +
                         "Outside the downloaded region it shows nothing, so switch back to \"Drive\" when you travel.")
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: page.regions
            delegate: Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: styler.themeHorizontalPageMargin
                anchors.rightMargin: styler.themeHorizontalPageMargin
                color: styler.blockBg
                border.color: styler.themeSecondaryColor
                height: card.height + 2 * styler.themePaddingLarge
                radius: styler.themePaddingLarge

                readonly property bool busy: page.busyId === modelData.id

                Column {
                    id: card
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: styler.themePaddingLarge
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: styler.themePaddingMedium

                    LabelPL {
                        color: styler.themePrimaryColor
                        font.bold: true
                        text: modelData.label
                    }
                    LabelPL {
                        color: styler.themeSecondaryHighlightColor
                        font.pixelSize: styler.themeFontSizeSmall
                        text: modelData.installed ?
                                  app.tr("Downloaded, %1").arg(page.mb(modelData.size)) :
                                  app.tr("About %1 tiles").arg(modelData.tiles_est)
                    }
                    Rectangle {
                        color: styler.themeSecondaryColor
                        height: 6; radius: 3
                        visible: parent.parent.busy
                        width: parent.width
                        Rectangle {
                            color: styler.accent
                            height: parent.height; radius: 3
                            width: parent.width * Math.min(1, page.done / Math.max(1, page.total))
                        }
                    }
                    LabelPL {
                        color: styler.themeSecondaryHighlightColor
                        font.pixelSize: styler.themeFontSizeSmall
                        text: page.phase === "fonts" ? app.tr("Fonts and icons...") :
                              app.tr("%1 of %2 tiles").arg(Math.round(page.done)).arg(Math.round(page.total))
                        visible: parent.parent.busy
                    }
                    Rectangle {
                        color: modelData.installed ? "transparent" : styler.accent
                        border.color: modelData.installed ? styler.themeSecondaryColor : styler.accent
                        border.width: 2
                        height: styler.themeItemSizeSmall
                        radius: height / 2
                        width: parent.width
                        LabelPL {
                            anchors.centerIn: parent
                            color: modelData.installed ? styler.themePrimaryColor : styler.textOnAccent
                            font.bold: true
                            text: parent.parent.parent.busy ? app.tr("Cancel") :
                                  modelData.installed ? app.tr("Remove") : app.tr("Download")
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: page.busyId === "" || parent.parent.parent.busy
                            onClicked: {
                                if (page.busyId === modelData.id) {
                                    py.call("poor.offline.cancel", []);
                                } else if (modelData.installed) {
                                    py.call("poor.offline.remove", [modelData.id], page.refresh);
                                } else {
                                    page.error = "";
                                    page.busyId = modelData.id;
                                    page.phase = "fonts"; page.done = 0; page.total = 1;
                                    py.call("poor.offline.download_async", [modelData.id]);
                                }
                            }
                        }
                    }
                }
            }
        }

        LabelPL {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: styler.themeHorizontalPageMargin
            anchors.rightMargin: styler.themeHorizontalPageMargin
            color: "#ff6b6b"
            text: page.error
            visible: page.error !== "" && page.error !== "cancelled"
            wrapMode: Text.WordWrap
        }
    }

    Component.onCompleted: {
        py.setHandler("offline.progress", function(phase, d, t) {
            page.phase = phase; page.done = d; page.total = t;
        });
        py.setHandler("offline.finished", function(rid, err) {
            page.busyId = "";
            page.error = err;
            page.refresh();
        });
        refresh();
    }
}
