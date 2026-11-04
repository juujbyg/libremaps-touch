/* -*- coding: utf-8-unix -*-
 *
 * Copyright (C) 2014 Osmo Salomaa
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
import QtPositioning 5.4
import "."
import "platform"

MenuDrawerPL {
    id: page

    banner: "icons/banner.jpg"
    title: "LibreMaps"
    titleIcon: "pure-maps"
    pageMenu: PageMenuPL {
        PageMenuItemPL {
            iconName: styler.iconAbout
            text: app.tr("About LibreMaps")
            onClicked: app.pushMain(Qt.resolvedUrl("AboutPage.qml"))
        }
    }

    // To make TextSwitch text line up with IconListItem's text label.
    property real switchLeftMargin: styler.themeHorizontalPageMargin + styler.themePaddingLarge + styler.themePaddingSmall

    MenuDrawerItemPL {
        iconName: styler.iconStop
        text: app.tr("Stop following the movement")
        visible: app.mode === modes.followMe
        onClicked: {
            if (app.mode !== modes.followMe) return;
            app.navigator.followMe = false;
            app.showMap();
        }
    }

    MenuDrawerItemPL {
        iconName: styler.iconSearch
        text: app.tr("Search")
        visible: false  // the search bar does this
        onClicked: app.pushMain(Qt.resolvedUrl("GeocodePage.qml"))
    }

    MenuDrawerItemPL {
        iconName: styler.iconNavigate
        text: app.tr("Navigation")
        visible: false  // the arrow in the search bar does this
        onClicked: app.pushMain(Qt.resolvedUrl("RoutePage.qml"))
    }

    MenuDrawerItemPL {
        iconName: styler.iconNearby
        text: app.tr("Nearby venues")
        onClicked: app.pushMain(Qt.resolvedUrl("NearbyPage.qml"))
    }

    MenuDrawerItemPL {
        iconName: styler.iconFavorite
        text: app.tr("Bookmarks")
        onClicked: app.pushMain(Qt.resolvedUrl("PoiPage.qml"))
    }

    MenuDrawerItemPL {
        enabled: gps.coordinateValid
        iconName: styler.iconShare
        text: gps.coordinateValid ? app.tr("Share current position") : app.tr("Share current position (not ready)")
        onClicked: {
            if (!gps.coordinateValid) return;
            var y = gps.coordinate.latitude;
            var x = gps.coordinate.longitude;
            app.pushMain(Qt.resolvedUrl("SharePage.qml"), {
                             "coordinate": QtPositioning.coordinate(y, x),
                             "title": app.tr("Share Current Position"),
                             "poi": { "address": app.tr("Current position") }
                         });
        }
    }

    MenuDrawerItemPL {
        iconName: styler.iconMaps
        text: app.conf.basemapLight === "night" ? app.tr("Switch to day map") : app.tr("Switch to night map")
        onClicked: {
            app.conf.set("basemap_auto_light", "none");
            app.conf.set("basemap_light", app.conf.basemapLight === "night" ? "day" : "night");
            py.call_sync("poor.app.basemap._find_map", []);
            app.showMap();
        }
    }

    MenuDrawerItemPL {
        iconName: styler.iconMaps
        text: app.tr("Maps")
        onClicked: app.pushMain(Qt.resolvedUrl("BasemapPage.qml"))
    }

    MenuDrawerItemPL {
        iconName: styler.iconPreferences
        text: app.tr("Customize")
        onClicked: app.pushMain(Qt.resolvedUrl("CustomizePage.qml"))
    }

    MenuDrawerItemPL {
        iconName: styler.iconMaps
        text: app.tr("Offline maps")
        onClicked: app.pushMain(Qt.resolvedUrl("OfflinePage.qml"))
    }

    MenuDrawerItemPL {
        iconName: styler.iconAbout
        text: app.tr("Map credits")
        onClicked: app.pushMain(Qt.resolvedUrl("AttributionPage.qml"))
    }

    MenuDrawerItemPL {
        iconName: styler.iconPreferences
        text: app.tr("Preferences")
        onClicked: app.pushMain(Qt.resolvedUrl("PreferencesPage.qml"), {}, true)
    }

    MenuDrawerSubmenuPL {
        id: profiles
        visible: false  // offline maps have their own page
        iconName: {
            if (app.conf.profile === "online" || app.conf.profile === "HERE")
                return styler.iconProfileOnline;
            if (app.conf.profile === "offline") return styler.iconProfileOffline;
            return styler.iconProfileMixed;
        }
        text: app.tr("Profile")

        MenuDrawerSubmenuItemPL {
            checked: app.conf.profile === "online"
            text: app.tr("Online")
            onClicked: profiles.set("online")
        }

        MenuDrawerSubmenuItemPL {
            checked: app.conf.profile === "offline"
            text: app.tr("Offline")
            onClicked: profiles.set("offline")
        }

        MenuDrawerSubmenuItemPL {
            checked: app.conf.profile === "HERE"
            enabled: available
            text: available ? app.tr("HERE - Online") : app.tr("HERE (disabled, API key missing)")
            onClicked: if (available) profiles.set("HERE")
            property bool available: py.evaluate("poor.key.has_here")
        }

        MenuDrawerSubmenuItemPL {
            checked: app.conf.profile === "mixed"
            text: app.tr("Mixed")
            onClicked: profiles.set("mixed")
        }

        function set(p) {
            py.call_sync("poor.app.set_profile", [p]);
        }
    }
}
