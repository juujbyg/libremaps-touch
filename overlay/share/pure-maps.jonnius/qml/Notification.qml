/* -*- coding: utf-8-unix -*-
 *
 * Copyright (C) 2017 Osmo Salomaa, 2019 Rinigus, 2019 Purism SPC
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

import QtQuick 2.2
import QtGraphicalEffects 1.0
import "platform"

// Sonner-style toast: a white card with an icon that drops in under the search bar and fades
// away. Same API as before: flash(text, id, timeout), hold(text, id), clear(id).
Item {
    id: rect
    anchors.top: referenceBlockTop.bottom
    anchors.topMargin: styler.themePaddingLarge + (searchBar.visible ? searchBar.fullHeight + styler.themePaddingLarge : 0)
    anchors.horizontalCenter: parent.horizontalCenter
    height: card.height
    opacity: currentText ? 1 : 0
    visible: !app.modalDialog && label.text
    width: card.width
    z: 400

    property string currentText: {
        if (stack.length)
            return stack.reduce(function (a,b) {
                if (a) return a + '\n' + b.text;
                return b.text;
            }, '');
        return '';
    }
    property string lastText
    // Padding on the edges
    property real   padding: 1.4 * styler.themePaddingMedium
    property var    stack: []
    property real   widthLimit: parent.width - 4 * styler.themePaddingLarge
    // drop-in offset, animated with the opacity
    property real   drop: currentText ? 0 : -styler.themePaddingLarge

    Behavior on opacity {
        OpacityAnimator {
            duration: 220
            easing.type: Easing.OutCubic
            onRunningChanged: if (!currentText && !running) lastText = ''
        }
    }
    Behavior on drop {
        NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
    }

    Rectangle {
        id: card
        border.color: styler.border
        border.width: 1
        color: styler.surface
        height: Math.max(label.height, icon.height) + 2 * rect.padding
        radius: styler.radiusLg
        width: icon.width + styler.themePaddingMedium + label.width + 2 * rect.padding
        y: rect.drop
        layer.enabled: true
        layer.effect: DropShadow {
            color: styler.shadowColor
            opacity: styler.shadowOpacity
            radius: styler.shadowRadius
            samples: 1 + radius * 2
            verticalOffset: 3
        }

        Image {
            id: icon
            anchors.left: parent.left
            anchors.leftMargin: rect.padding
            anchors.verticalCenter: parent.verticalCenter
            height: styler.themeFontSizeMedium * 1.2
            smooth: true
            source: Qt.resolvedUrl("icons/ui/info-muted.svg")
            sourceSize.height: height * 2
            sourceSize.width: height * 2
            width: height
        }

        LabelPL {
            id: label
            anchors.left: icon.right
            anchors.leftMargin: styler.themePaddingMedium
            anchors.verticalCenter: parent.verticalCenter
            color: styler.ink
            font.pixelSize: styler.themeFontSizeSmall
            font.weight: Font.Medium
            lineHeight: 1.1
            text: currentText ? currentText : lastText
            wrapMode: Text.WordWrap
            width: Math.min(implicitWidth, rect.widthLimit - icon.width - styler.themePaddingMedium - 2 * rect.padding)
        }
    }

    Timer {
        id: timer
        interval: 1000
        repeat: stack.length > 0
        running: stack.length > 0
        onTriggered: {
            var t = Date.now();
            stack = stack.filter(function (txt) {
                return txt.timeout < 0 || txt.timeout > t;
            });
        }
    }

    onCurrentTextChanged: if (currentText) lastText = currentText

    function clear(textId) {
        textId = textId || 'none';
        stack = stack.filter(function (txt) {
            return txt.id !== textId;
        });
    }

    function flash(text, textId, timeout) {
        var tout = Date.now();
        if (timeout > 0) tout += timeout*1000;
        else if (timeout < 0) tout = -1;
        else tout += 5000; // default
        var t = { 'text': text,
            'id': textId || 'none',
            'timeout': tout };
        var ns = stack;
        if (ns.length > 0) {
            ns = ns.filter(function (i) {
                return i.id !== t.id;
            });
            ns.push(t);
        } else
            ns = [t];
        stack = ns;
    }

    function hold(text, textId) {
        flash(text, textId, -1);
    }

}
