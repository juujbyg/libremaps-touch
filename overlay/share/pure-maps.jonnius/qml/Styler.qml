/* -*- coding: utf-8-unix -*-
 *
 * Copyright (C) 2018 Rinigus
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

StylerPL {
    id: styler

    // ---- LibreMaps is always light: cream pages, dark ink text (the phone's default is black with white text)
    blockBg: "#ffffff"
    themeHighlightColor: "#1f2430"
    themePrimaryColor: "#1f2430"
    themeSecondaryColor: "#9aa0ac"
    themeSecondaryHighlightColor: "#5b6270"

    // blockPressed should never be specified in style nor defaults
    property color  blockPressed: Qt.rgba(styler.blockBg.r*0.8 + styler.themeHighlightColor.r*0.2,
                                          styler.blockBg.g*0.8 + styler.themeHighlightColor.g*0.2,
                                          styler.blockBg.b*0.8 + styler.themeHighlightColor.b*0.2,
                                          styler.blockBg.a*0.8 + styler.themeHighlightColor.a*0.2)
    // ---- LibreMaps palette: amber, silver-white, ink
    readonly property color amber: "#f4a81d"
    readonly property color amberDark: "#cf8a00"
    readonly property color amberSoft: "#fff1d1"
    readonly property color ink: "#1f2430"
    readonly property color inkSoft: "#5b6270"
    readonly property color cream: "#fbf8f1"
    readonly property color textOnAccent: "#1f2430"          // text and icons on amber
    property color  accent: amber        // accent of the driving HUD: distances, speed ring
    // accent when used as text: darker on light panels so it stays readable
    property color  accentText: hudBg.hslLightness > 0.5 ? "#a86a00" : amber
    property color  hudBg: blockBg       // driving HUD background (maneuver banner, ETA bar, speed bubble)
    property color  hudMuted: themeSecondaryColor // driving HUD secondary text
    property color  hudText: themePrimaryColor    // driving HUD primary text
    property string fg                   // foreground color (scale bar, metrics)
    property string iconVariant          // type of icons, let empty for default version, "white" for white icons
    property real   indicatorSize: styler.themeIconSizeSmall*1.4142*(1 + 0.2) / 4 // indicator height and width - do not change in defaults or style
    property string itemBg               // map item (buttons, street name) outline
    property string itemFg               // map item (buttons, street name) foreground
    // itemHighlight should never be specified in style nor defaults
    property color  itemHighlight: Qt.rgba( (_itemColBg.r*1+_itemColFg.r)/2,
                                            (_itemColBg.g*1+_itemColFg.g)/2,
                                            (_itemColBg.b*1+_itemColFg.b)/2,
                                            (_itemColBg.a*1+_itemColFg.a)/2)
    // itemPressed should never be specified in style nor defaults
    property color  itemPressed: Qt.rgba( (_itemColBg.r*3+_itemColFg.r)/4,
                                          (_itemColBg.g*3+_itemColFg.g)/4,
                                          (_itemColBg.b*3+_itemColFg.b)/4,
                                          (_itemColBg.a*3+_itemColFg.a)/4)
    property string maneuver             // maneuver circle inner color
    property string position             // variant of position marker, set to "" for default
    property string positionUncertainty  // position marker uncertainty
    property int    radius: styler.themePaddingMedium // shields radius - do not change in defaults or style
    property string route                // route color on the map. also used for maneuver markers
    property real   routeOpacity         // opacity of route
    property string shadowColor          // shadow color used on map buttons and panels
    property real   shadowOpacity: 0.35  // shadow opacity - do not change in defaults or style
    property int    shadowRadius: 10     // shadow radius - do not change in defaults or style

    // private properties
    property color  _itemColBg: itemBg
    property color  _itemColFg: itemFg

    function apply(guistyle) {
        defaults();
        if (guistyle == null) return;
        for (var i in guistyle) {
            if (guistyle.hasOwnProperty(i) && styler.hasOwnProperty(i)) {
                styler[i] = guistyle[i];
            }
        }
    }

    // reset the HUD colors to follow the platform theme again
    function resetHud() {
        hudBg = Qt.binding(function() { return blockBg; });
        hudMuted = Qt.binding(function() { return themeSecondaryColor; });
        hudText = Qt.binding(function() { return themePrimaryColor; });
        accent = amber;
    }

    function defaults() {
        resetHud();
        fg = "black";
        iconVariant = "";
        maneuver = "white";
        position = "";
        positionUncertainty = "#e8a94a";
        route = "#0540ff";
        routeOpacity = 0.5;
        itemFg = "black";
        itemBg = "white";
        shadowColor = "black";

    }
}
