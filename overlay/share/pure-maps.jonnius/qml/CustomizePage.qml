/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: make the app yours. Arrow colour, voice style, friendly wording.
 */

import QtQuick 2.0
import "."
import "platform"

PagePL {
    id: page
    title: app.tr("Customize")

    readonly property var arrows: [
        { key: "sky",      label: app.tr("Sky"),      color: "#33ccff" },
        { key: "amber",    label: app.tr("Amber"),    color: "#f4a81d" },
        { key: "ocean",    label: app.tr("Ocean"),    color: "#1f7ae0" },
        { key: "forest",   label: app.tr("Forest"),   color: "#2e9e5b" },
        { key: "berry",    label: app.tr("Berry"),    color: "#d6336c" },
        { key: "graphite", label: app.tr("Graphite"), color: "#2b2f3a" }
    ]
    readonly property var voices: [
        { key: "calm",     label: app.tr("Calm") },
        { key: "standard", label: app.tr("Standard") },
        { key: "bright",   label: app.tr("Bright") }
    ]

    Voice {
        id: voice
        enabled: true
        engine: "tester"
        gender: "female"
        // the phone's language; the engine falls back from es_ES to es
        language: Qt.locale().name
    }

    Column {
            id: column
            width: page.width
            spacing: styler.themePaddingLarge

            Item { width: 1; height: styler.themePaddingMedium }

            // ---- Arrow
            LabelPL {
                x: styler.themeHorizontalPageMargin
                font.bold: true
                color: styler.themePrimaryColor
                text: app.tr("Navigation arrow")
            }
            LabelPL {
                x: styler.themeHorizontalPageMargin
                width: parent.width - 2 * styler.themeHorizontalPageMargin
                wrapMode: Text.WordWrap
                color: styler.themeSecondaryHighlightColor
                font.pixelSize: styler.themeFontSizeSmall
                text: app.tr("Shown on the map while you are moving, pointing the way you head.")
            }
            Flow {
                x: styler.themeHorizontalPageMargin
                width: parent.width - 2 * styler.themeHorizontalPageMargin
                spacing: styler.themePaddingMedium
                Repeater {
                    model: page.arrows
                    delegate: Rectangle {
                        readonly property bool on: app.conf.arrowColor === modelData.key
                        width: styler.themeItemSizeLarge * 1.05
                        height: styler.themeItemSizeLarge * 1.2
                        radius: styler.themePaddingLarge
                        color: on ? styler.amberSoft : styler.surface
                        border.color: on ? styler.amber : styler.themeSecondaryColor
                        border.width: on ? 2 : 1
                        Column {
                            anchors.centerIn: parent
                            spacing: styler.themePaddingSmall
                            Image {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: styler.themeItemSizeSmall * 0.9
                                height: width
                                sourceSize.width: width * 2
                                sourceSize.height: width * 2
                                source: Qt.resolvedUrl("icons/position/position-direction-arrow-" + modelData.key + ".svg")
                            }
                            LabelPL {
                                anchors.horizontalCenter: parent.horizontalCenter
                                font.pixelSize: styler.themeFontSizeSmall
                                color: styler.ink
                                text: modelData.label
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: app.conf.set("arrow_color", modelData.key)
                        }
                    }
                }
            }

            // ---- Voice
            LabelPL {
                x: styler.themeHorizontalPageMargin
                font.bold: true
                color: styler.themePrimaryColor
                text: app.tr("Voice")
            }
            LabelPL {
                x: styler.themeHorizontalPageMargin
                width: parent.width - 2 * styler.themeHorizontalPageMargin
                wrapMode: Text.WordWrap
                color: styler.themeSecondaryHighlightColor
                font.pixelSize: styler.themeFontSizeSmall
                text: voice.active ?
                          app.tr("Spoken directions use the voice engine on this phone (%1).").arg(voice.currentEngine) :
                          app.tr("No voice engine found for this language.")
            }
            Row {
                x: styler.themeHorizontalPageMargin
                spacing: styler.themePaddingMedium
                Repeater {
                    model: page.voices
                    delegate: Rectangle {
                        readonly property bool on: app.conf.voiceStyle === modelData.key
                        width: (page.width - 2 * styler.themeHorizontalPageMargin - 2 * styler.themePaddingMedium) / 3
                        height: styler.themeItemSizeSmall
                        radius: height / 2
                        color: on ? styler.amber : styler.surface
                        border.color: on ? styler.amber : styler.themeSecondaryColor
                        LabelPL {
                            anchors.centerIn: parent
                            font.bold: parent.on
                            color: styler.ink
                            text: modelData.label
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                app.conf.set("voice_style", modelData.key);
                                page.say();
                            }
                        }
                    }
                }
            }
            TextSwitchPL {
                x: styler.themeHorizontalPageMargin
                width: parent.width - 2 * styler.themeHorizontalPageMargin
                checked: app.conf.voiceFriendly
                text: app.tr("Friendly wording")
                description: app.tr("\"Okay, turn left\" and \"You made it\" instead of terse commands.")
                onCheckedChanged: {
                    if (checked === app.conf.voiceFriendly) return;
                    app.conf.set("voice_friendly", checked);
                    page.say();
                }
            }
            Rectangle {
                x: styler.themeHorizontalPageMargin
                width: parent.width - 2 * styler.themeHorizontalPageMargin
                height: styler.themeItemSizeSmall
                radius: height / 2
                color: "#ffffff"
                border.color: styler.amber
                border.width: 2
                LabelPL {
                    anchors.centerIn: parent
                    color: styler.ink
                    text: app.tr("Hear a sample")
                }
                MouseArea { anchors.fill: parent; onClicked: page.say() }
            }
            Item { width: 1; height: styler.themePaddingLarge }
    }

    Component.onCompleted: voice.init()

    function say() {
        if (!voice.active) return;
        var txt = app.tr("Okay, turn left onto Calle Mayor. In 200 meters, you'll arrive at your destination.");
        voice.prepare(txt);
        voice.play(txt);
    }
}
