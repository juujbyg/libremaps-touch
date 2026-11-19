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

    // ---- LibreMaps in the shadcn/ui style: zinc greys, thin borders, one amber accent and the
    // Inter typeface. Light by day; dark when the map's style says "dark" (the night map),
    // so the theme follows Light / Dark / Auto (sunset) in the menu.
    property bool dark: false
    // Lomiri's own parts (page headers, text fields, system icons) follow the same theme
    onDarkChanged: theme.name = dark ? "Lomiri.Components.Themes.SuruDark" : "Lomiri.Components.Themes.Ambiance"
    blockBg: surface
    themeHighlightColor: ink
    themePrimaryColor: ink
    themeSecondaryColor: muted
    themeSecondaryHighlightColor: inkSoft
    themeFontFamily: inter.status === FontLoader.Ready ? inter.name : Qt.application.font.family
    themeFontFamilyHeading: themeFontFamily

    property FontLoader inter: FontLoader { source: "fonts/Inter-Regular.ttf" }
    property FontLoader interMedium: FontLoader { source: "fonts/Inter-Medium.ttf" }
    property FontLoader interSemiBold: FontLoader { source: "fonts/Inter-SemiBold.ttf" }

    // ---- shadcn tokens
    readonly property color surface: dark ? "#18181b" : "#ffffff"      // cards, bars, sheets
    readonly property color subtle: dark ? "#27272a" : "#f4f4f5"       // pressed rows, secondary buttons, tracks
    readonly property color border: dark ? "#323238" : "#e4e4e7"       // 1 px outlines and dividers
    readonly property color borderStrong: dark ? "#52525b" : "#d4d4d8" // grab handles, focused inputs
    readonly property color muted: dark ? "#a1a1aa" : "#71717a"        // secondary text and icons
    readonly property color primary: dark ? "#fafafa" : "#18181b"      // primary buttons
    readonly property color primaryPressed: dark ? "#d4d4d8" : "#3f3f46"
    readonly property color primaryText: dark ? "#09090b" : "#ffffff"  // text on primary
    readonly property color link: dark ? "#38bdf8" : "#0284c7"         // sky labels on tiles
    readonly property string linkTone: dark ? "skylight" : "sky"       // matching icon tone
    readonly property color okBg: dark ? "#14361f" : "#dcfce7"         // "Open" chip
    readonly property color okText: dark ? "#86efac" : "#15803d"
    readonly property color badBg: dark ? "#3f1414" : "#fee2e2"        // "Closed" chip
    readonly property color badText: dark ? "#fca5a5" : "#b91c1c"
    readonly property color danger: "#ef4444"
    readonly property color dangerPressed: "#dc2626"
    readonly property color success: "#16a34a"
    readonly property color hudDark: "#09090b"      // the driving card: dark on any map
    readonly property color hudDarkRaised: "#27272a"
    readonly property color hudDarkMuted: "#a1a1aa"
    // ---- driving screen, Waze-like: dark turn card, sky-blue street names, yellow report button
    readonly property color navStreet: "#7cc8ff"
    readonly property color navSky: "#33ccff"
    readonly property color navYellow: "#ffc72c"
    readonly property color navYellowPressed: "#f0b400"
    readonly property color navDisc: "#1c1c1f"
    readonly property real  radiusSm: themePaddingMedium * 0.8
    readonly property real  radiusMd: themePaddingMedium * 1.2
    readonly property real  radiusLg: themePaddingMedium * 1.6

    // blockPressed should never be specified in style nor defaults
    property color  blockPressed: Qt.rgba(styler.blockBg.r*0.8 + styler.themeHighlightColor.r*0.2,
                                          styler.blockBg.g*0.8 + styler.themeHighlightColor.g*0.2,
                                          styler.blockBg.b*0.8 + styler.themeHighlightColor.b*0.2,
                                          styler.blockBg.a*0.8 + styler.themeHighlightColor.a*0.2)
    // ---- LibreMaps palette: amber, silver-white, ink
    readonly property color amber: "#f4a81d"
    readonly property color amberDark: "#cf8a00"
    readonly property color amberSoft: dark ? "#3a2a0a" : "#fff1d1"
    readonly property color ink: dark ? "#fafafa" : "#09090b"
    readonly property color inkSoft: dark ? "#d4d4d8" : "#52525b"
    readonly property color cream: dark ? "#09090b" : "#fafafa"
    readonly property color textOnAccent: "#09090b"          // text and icons on amber
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
    property string routeCasing          // darker edge along the route line
    property real   routeOpacity         // opacity of route
    property string shadowColor          // shadow color used on map buttons and panels
    property real   shadowOpacity: 0.16  // shadow opacity - do not change in defaults or style
    property int    shadowRadius: 12     // shadow radius - do not change in defaults or style

    // private properties
    property color  _itemColBg: itemBg
    property color  _itemColFg: itemFg

    // a Lucide icon in the theme: ink by day, white at night, or a fixed tone
    function icon(name, tone) {
        return Qt.resolvedUrl("icons/ui/%1-%2.svg".arg(name).arg(tone ? tone : (dark ? "white" : "ink")));
    }

    function apply(guistyle) {
        defaults();
        // set dark once, so a style reload doesn't flip the theme off and back on
        dark = !!(guistyle && guistyle.dark);
        if (guistyle == null) return;
        for (var i in guistyle) {
            if (i !== "dark" && guistyle.hasOwnProperty(i) && styler.hasOwnProperty(i)) {
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
        route = "#7c4dff";
        routeCasing = "#4c1d95";
        routeOpacity = 1.0;
        itemFg = "#09090b";
        itemBg = "white";
        shadowColor = "black";

    }
}
