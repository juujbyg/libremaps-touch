/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: the route as a panel over the top of the map, like
 * openstreetmap.org/directions: title, distance and time, numbered turns.
 * The map underneath is re-fitted to the lower part of the screen.
 */

import QtQuick 2.0
import "."
import "platform"

Rectangle {
    id: panel
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    color: styler.hudBg
    height: visible ? Math.round(parent.height * 0.46) : 0
    visible: app.mode === modes.exploreRoute && !app.modalDialog && !app.infoPanelOpen
    z: 600

    // soft bottom edge
    Rectangle {
        anchors.top: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: styler.themePaddingSmall
        gradient: Gradient {
            GradientStop { position: 0; color: "#55000000" }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    MouseArea { anchors.fill: parent }  // do not let touches reach the map

    // ---- header: title, close
    Item {
        id: head
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: styler.themeItemSizeSmall * 1.1

        LabelPL {
            anchors.left: parent.left
            anchors.leftMargin: styler.themeHorizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            color: styler.hudText
            font.bold: true
            font.pixelSize: styler.themeFontSizeLarge
            text: app.tr("Directions")
        }
        Item {
            id: closeBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: head.height; width: head.height
            LabelPL {
                anchors.centerIn: parent
                color: styler.hudMuted
                font.pixelSize: styler.themeFontSizeLarge * 1.4
                text: "×"
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    notification.flash(app.tr("Route removed"), "navigationClear");
                    navigator.clearRoute();
                }
            }
        }
    }

    // ---- summary: distance, time | edit | start
    Item {
        id: summary
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: head.bottom
        height: styler.themeItemSizeSmall

        LabelPL {
            anchors.left: parent.left
            anchors.leftMargin: styler.themeHorizontalPageMargin
            anchors.right: editBtn.left
            anchors.verticalCenter: parent.verticalCenter
            color: styler.hudMuted
            elide: Text.ElideRight
            text: app.tr("Distance: %1  ·  Time: %2").arg(app.navigator.totalDist).arg(app.navigator.totalTime)
        }
        Item {
            id: editBtn
            anchors.right: startBtn.left
            anchors.verticalCenter: parent.verticalCenter
            height: summary.height; width: editLabel.implicitWidth + 2 * styler.themePaddingLarge
            LabelPL {
                id: editLabel
                anchors.centerIn: parent
                color: styler.accentText
                font.bold: true
                text: app.tr("Edit")
            }
            MouseArea {
                anchors.fill: parent
                onClicked: app.push(Qt.resolvedUrl("RoutePage.qml"))
            }
        }
        Rectangle {
            id: startBtn
            anchors.right: parent.right
            anchors.rightMargin: styler.themeHorizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            color: styler.accent
            height: summary.height * 0.78
            radius: height / 2
            width: startLabel.implicitWidth + 2 * styler.themePaddingLarge
            LabelPL {
                id: startLabel
                anchors.centerIn: parent
                color: styler.textOnAccent
                font.bold: true
                text: app.tr("Start")
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    notification.flash(app.tr("Navigation started"), "navigationStartPause");
                    app.navigator.running = true;
                }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: summary.bottom
        color: styler.hudMuted
        height: 1
        opacity: 0.4
    }

    // ---- numbered turns
    ListView {
        id: turns
        anchors.top: summary.bottom
        anchors.topMargin: 1
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        model: app.navigator.maneuvers
        boundsBehavior: Flickable.StopAtBounds

        property int active: -1

        delegate: Item {
            id: row
            height: Math.max(styler.themeItemSizeSmall * 0.95, label.implicitHeight + 2 * styler.themePaddingMedium)
            width: turns.width

            Rectangle {
                anchors.fill: parent
                color: styler.accent
                opacity: turns.active === model.index ? 0.15 : 0
            }
            Image {
                id: ico
                anchors.left: parent.left
                anchors.leftMargin: styler.themeHorizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                opacity: 0.95
                smooth: true
                source: "icons/navigation/%1-%2.svg".arg(model.icon).arg(styler.hudBg.hslLightness > 0.5 ? "black" : "white")
                sourceSize.height: styler.themeIconSizeSmall
                sourceSize.width: styler.themeIconSizeSmall
            }
            LabelPL {
                id: label
                anchors.left: ico.right
                anchors.leftMargin: styler.themePaddingLarge
                anchors.right: dist.left
                anchors.rightMargin: styler.themePaddingMedium
                anchors.verticalCenter: parent.verticalCenter
                color: styler.hudText
                font.pixelSize: styler.themeFontSizeSmall
                text: "<b>" + (model.index + 1) + ".</b> " + model.narrative
                textFormat: Text.StyledText
                wrapMode: Text.WordWrap
            }
            LabelPL {
                id: dist
                anchors.right: parent.right
                anchors.rightMargin: styler.themeHorizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                color: styler.hudMuted
                font.pixelSize: styler.themeFontSizeExtraSmall
                text: model.index < turns.count - 1 ? model.length : ""
            }
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                color: styler.hudMuted
                height: 1
                opacity: 0.2
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    turns.active = model.index;
                    map.center = model.coordinate;
                    map.zoomLevel < 15 && map.setZoomLevel(15);
                }
            }
        }
    }
}
