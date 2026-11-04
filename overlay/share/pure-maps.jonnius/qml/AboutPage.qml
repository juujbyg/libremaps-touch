/* -*- coding: utf-8-unix -*-
 *
 * Copyright (C) 2014 Osmo Salomaa, 2018 Rinigus
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
import "."
import "platform"

PagePL {
    id: page
    title: app.tr("About LibreMaps")

    Column {
        id: column
        spacing: styler.themePaddingLarge
        width: parent.width

        Image {
            // Banner
            anchors.horizontalCenter: parent.horizontalCenter
            fillMode: Image.PreserveAspectFit
            smooth: true
            source: "icons/banner.jpg"
            width: column.width

            Image {
                // Logo
                anchors.left: parent.left
                anchors.leftMargin: styler.themeHorizontalPageMargin
                anchors.top: parent.top
                anchors.topMargin: Math.min(parent.height/4, styler.themePaddingMedium)
                height: parent.height / 2
                smooth: true
                source: "icons/pure-maps.svg"
                sourceSize.height: height
                sourceSize.width: height
                width: height
            }
        }

        ListItemLabel {
            height: styler.themeItemSizeExtraSmall
            horizontalAlignment: Text.AlignHCenter
            text: app.tr("version %1", programVersion)
        }

        ListItemLabel {
            height: styler.themeItemSizeExtraSmall
            horizontalAlignment: Text.AlignHCenter
            text: app.tr("This is a limited edition distributed through Jolla Store")
            visible: programVariantJollaStore
            wrapMode: Text.WordWrap
        }

        ListItemLabel {
            horizontalAlignment: Text.AlignHCenter
            text: app.tr('Source code: <a href="https://github.com/juujbyg/libremaps-touch">LibreMaps</a>, based on <a href="https://github.com/rinigus/pure-maps">Pure Maps</a>')
            wrapMode: Text.WordWrap
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: styler.themePaddingSmall
            width: Math.min(page.height,page.width)

            ListItemLabel {
                font.pixelSize: styler.themeFontSizeSmall
                height: implicitHeight
                text: "Copyright ©"
            }

            ListItemLabel {
                font.pixelSize: styler.themeFontSizeSmall
                height: implicitHeight
                horizontalAlignment: Text.AlignRight
                text: "2014–2018 Osmo Salomaa\n2018-2022 Rinigus"
            }

            ListItemLabel {
                font.pixelSize: styler.themeFontSizeSmall
                height: implicitHeight
                horizontalAlignment: Text.AlignRight
                text: app.tr("Artwork by %1 and %2\nBanner photo by %3 (Pexels License)", "Fellfrosch", "Mosen", "Yaroslav Shuraev")
                wrapMode: Text.WordWrap
            }

            ListItemLabel {
                font.pixelSize: styler.themeFontSizeSmall
                height: implicitHeight
                horizontalAlignment: Text.AlignRight
                text: app.tr('Transportation icons made by <a href="https://www.flaticon.com/authors/freepik" title="Freepik">Freepik</a> ' +
                             'from <a href="https://www.flaticon.com/" title="Flaticon">www.flaticon.com</a>')
                wrapMode: Text.WordWrap
            }

        }

        ListItemLabel {
            font.pixelSize: styler.themeFontSizeSmall
            height: implicitHeight
            horizontalAlignment: implicitWidth >
                                 parent.width - anchors.leftMargin - anchors.rightMargin ?
                                     Text.AlignLeft : Text.AlignHCenter
            text: app.tr("LibreMaps is free software released under the GNU General Public License (GPL), version 3 or later. It is a fork of Pure Maps by Rinigus and contributors, and of the Ubuntu Touch port by Jonatan Hatakeyama.")
            wrapMode: Text.WordWrap
        }

        SectionHeaderPL {
            text: app.tr("Privacy: who sees what")
        }

        ListItemLabel {
            font.pixelSize: styler.themeFontSizeSmall
            height: implicitHeight
            horizontalAlignment: Text.AlignLeft
            text: app.tr("LibreMaps has no account, no ads and no analytics. It only talks to these open services, and only when you use the feature:\n\n" +
                         "• Map tiles and fonts: OpenFreeMap (tiles.openfreemap.org) sees the map area you view.\n" +
                         "• Search: Photon by Komoot (photon.komoot.io) sees what you type.\n" +
                         "• Routes for walk, bike and car: FOSSGIS Valhalla (valhalla1.openstreetmap.de) sees your start and end points.\n" +
                         "• Public transport: Transitous (api.transitous.org) sees your start and end points.\n" +
                         "• Places nearby (Food, Coffee, Fuel and the other shortcuts): an Overpass server, or Photon if those fail, sees the area you search.\n" +
                         "• Speed limits: Valhalla sees your position while you drive, if Road alerts is on.\n" +
                         "• Speed cameras: an Overpass server (overpass.kumi.systems, maps.mail.ru or overpass-api.de) sees the outline of your route, if Road alerts is on.\n" +
                         "• Approximate position when GPS has no fix: ipwho.is sees your IP address, if that option is on.\n\n" +
                         "Road alerts and the approximate position can be switched off in Preferences. Your last known position is stored only on the phone.")
            wrapMode: Text.WordWrap
        }

        SectionHeaderPL {
            text: app.tr("Translated by")
        }

        ListItemLabel {
            font.pixelSize: styler.themeFontSizeSmall
            height: visible ? styler.themeItemSizeExtraSmall : 0
            horizontalAlignment: Text.AlignHCenter
            // TRANSLATORS: This is a special message that shouldn't be translated
            // literally. It is used in the about page to give credits to the translators.
            // Thus, you should translate it to your name. You can also include other
            // translators who have contributed to this translation; in that case, please
            // write them on separate lines seperated by newlines (\n).
            text: app.tr("translator-credits")
            visible: text && text !== "translator-credits"
        }

        ListItemLabel {
            font.pixelSize: styler.themeFontSizeSmall
            height: implicitHeight
            horizontalAlignment: implicitWidth >
                                 parent.width - anchors.leftMargin - anchors.rightMargin ?
                                     Text.AlignLeft : Text.AlignHCenter
            text: app.tr("You can add new user interface translations or contribute to existing ones at Transifex.")
            wrapMode: Text.WordWrap
        }

        ListItemLabel {
            horizontalAlignment: Text.AlignHCenter
            text: app.tr('Translations at <a href="https://www.transifex.com/rinigus/pure-maps">Transifex page</a>')
        }
    }
}
