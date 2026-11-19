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
            color: styler.ink
            font.pixelSize: styler.themeFontSizeLarge
            font.weight: Font.DemiBold
            text: app.tr("Directions")
        }
        Item {
            id: closeBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: head.height; width: head.height
            Rectangle {
                anchors.centerIn: parent
                color: closeMouse.pressed ? styler.subtle : "transparent"
                height: parent.height * 0.7
                radius: styler.radiusMd
                width: height
            }
            Image {
                anchors.centerIn: parent
                height: parent.height * 0.36
                smooth: true
                source: styler.icon("x")
                sourceSize.height: height * 2
                sourceSize.width: height * 2
                width: height
            }
            MouseArea {
                id: closeMouse
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

        Row {
            anchors.left: parent.left
            anchors.leftMargin: styler.themeHorizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            spacing: styler.themePaddingMedium
            RollingNumber {
                anchors.verticalCenter: parent.verticalCenter
                color: styler.ink
                pixelSize: styler.themeFontSizeLarge
                text: app.navigator.totalTime
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                color: styler.borderStrong
                height: styler.themePaddingSmall * 0.6
                radius: height / 2
                width: height
            }
            RollingNumber {
                anchors.verticalCenter: parent.verticalCenter
                color: styler.muted
                pixelSize: styler.themeFontSizeMedium
                text: app.navigator.totalDist
                weight: Font.Medium
            }
        }
        Rectangle {
            id: editBtn
            anchors.right: startBtn.left
            anchors.rightMargin: styler.themePaddingMedium
            anchors.verticalCenter: parent.verticalCenter
            border.color: styler.border
            border.width: 1
            color: editMouse.pressed ? styler.subtle : styler.surface
            height: startBtn.height
            radius: styler.radiusMd
            width: editRow.width + 2 * styler.themePaddingLarge
            Row {
                id: editRow
                anchors.centerIn: parent
                spacing: styler.themePaddingSmall
                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    height: editLabel.font.pixelSize
                    smooth: true
                    source: styler.icon("pencil")
                    sourceSize.height: height * 2
                    sourceSize.width: height * 2
                    width: height
                }
                LabelPL {
                    id: editLabel
                    anchors.verticalCenter: parent.verticalCenter
                    color: styler.ink
                    font.weight: Font.Medium
                    text: app.tr("Edit")
                }
            }
            MouseArea {
                id: editMouse
                anchors.fill: parent
                onClicked: app.push(Qt.resolvedUrl("RoutePage.qml"))
            }
        }
        Rectangle {
            id: startBtn
            anchors.right: parent.right
            anchors.rightMargin: styler.themeHorizontalPageMargin
            anchors.verticalCenter: parent.verticalCenter
            color: startMouse.pressed ? styler.primaryPressed : styler.primary
            height: summary.height * 0.78
            radius: styler.radiusMd
            width: startRow.width + 2 * styler.themePaddingLarge
            Row {
                id: startRow
                anchors.centerIn: parent
                spacing: styler.themePaddingSmall
                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    height: startLabel.font.pixelSize
                    smooth: true
                    source: styler.icon("navigation", styler.dark ? "ink" : "white")
                    sourceSize.height: height * 2
                    sourceSize.width: height * 2
                    width: height
                }
                LabelPL {
                    id: startLabel
                    anchors.verticalCenter: parent.verticalCenter
                    color: styler.primaryText
                    font.weight: Font.Medium
                    text: app.tr("Start")
                }
            }
            MouseArea {
                id: startMouse
                anchors.fill: parent
                onClicked: {
                    notification.flash(app.tr("Navigation started"), "navigationStartPause");
                    app.navigator.running = true;
                }
            }
        }
    }

    // ---- other routes: one card each (time, how much slower, distance and main road)
    Item {
        id: choices
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: summary.bottom
        height: shown ? cardRow.height + styler.themePaddingMedium * 1.4 : 0
        visible: shown

        readonly property var  alts: app.navigator ? app.navigator.alternatives : []
        readonly property bool shown: alts && alts.length > 1

        Row {
            id: cardRow
            anchors.left: parent.left
            anchors.leftMargin: styler.themeHorizontalPageMargin
            anchors.top: parent.top
            spacing: styler.themePaddingMedium

            Repeater {
                model: choices.shown ? choices.alts.length : 0
                delegate: Rectangle {
                    readonly property var  r: choices.alts[index]
                    readonly property var  sum: r && r.summary ? r.summary : {}
                    readonly property bool chosen: app.navigator.alternativeIndex === index
                    readonly property real extra: (sum.seconds || 0) - ((choices.alts[0].summary || {}).seconds || 0)
                    border.color: chosen ? styler.primary : styler.border
                    border.width: chosen ? 2 : 1
                    color: cardMouse.pressed ? styler.subtle : styler.surface
                    height: cardCol.height + styler.themePaddingMedium * 1.6
                    radius: styler.radiusLg
                    width: (choices.width - 2 * styler.themeHorizontalPageMargin
                            - (choices.alts.length - 1) * cardRow.spacing) / choices.alts.length

                    Column {
                        id: cardCol
                        anchors.left: parent.left
                        anchors.leftMargin: styler.themePaddingMedium * 1.2
                        anchors.right: parent.right
                        anchors.rightMargin: styler.themePaddingMedium
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: styler.themePaddingSmall * 0.5
                        Text {
                            color: styler.ink
                            elide: Text.ElideRight
                            font.family: styler.themeFontFamily
                            font.pixelSize: styler.themeFontSizeMedium
                            font.weight: Font.DemiBold
                            text: sum.time || ""
                            width: parent.width
                        }
                        Text {
                            color: index === 0 ? styler.success : styler.muted
                            elide: Text.ElideRight
                            font.family: styler.themeFontFamily
                            font.pixelSize: styler.themeFontSizeExtraSmall
                            font.weight: Font.Medium
                            text: index === 0 ? app.tr("Fastest") :
                                                app.tr("+%1 min").arg(Math.max(1, Math.round(extra / 60)))
                            width: parent.width
                        }
                        Text {
                            color: styler.muted
                            elide: Text.ElideRight
                            font.family: styler.themeFontFamily
                            font.pixelSize: styler.themeFontSizeExtraSmall
                            text: sum.via ? app.tr("%1 · via %2").arg(sum.distance || "").arg(sum.via)
                                          : (sum.distance || "")
                            width: parent.width
                        }
                    }
                    MouseArea {
                        id: cardMouse
                        anchors.fill: parent
                        onClicked: app.navigator.chooseAlternative(index)
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: choices.bottom
        color: styler.border
        height: 1
    }

    // ---- numbered turns
    ListView {
        id: turns
        anchors.top: choices.bottom
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
                color: styler.subtle
                opacity: turns.active === model.index ? 1 : 0
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
                color: styler.ink
                font.pixelSize: styler.themeFontSizeSmall
                text: "<font color='" + styler.muted + "'>" + (model.index + 1) + "</font>&nbsp;&nbsp;" + model.narrative
                textFormat: Text.StyledText
                wrapMode: Text.WordWrap
            }
            LabelPL {
                id: dist
                anchors.right: parent.right
                anchors.rightMargin: styler.themeHorizontalPageMargin
                anchors.verticalCenter: parent.verticalCenter
                color: styler.muted
                font.pixelSize: styler.themeFontSizeExtraSmall
                font.weight: Font.Medium
                text: model.index < turns.count - 1 && model.length ? model.length : ""
            }
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                color: styler.border
                height: 1
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
