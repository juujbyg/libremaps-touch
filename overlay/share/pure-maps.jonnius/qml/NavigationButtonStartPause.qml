/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: one clean pill while navigating. "Stop" ends guidance and
 * returns to the route panel (which has Start); "Done" after arriving;
 * "Stop following" in follow-me mode.
 */

import QtQuick 2.0
import "platform"

Rectangle {
    id: button
    anchors.right: parent.right
    anchors.rightMargin: styler.themePaddingLarge
    color: app.mode === modes.navigatePost ? styler.accent : "#e5484d"
    height: styler.themeItemSizeSmall * 0.85
    radius: height / 2
    visible: !hidden && (app.mode === modes.navigate || app.mode === modes.navigatePost ||
                         app.mode === modes.followMe)
    width: label.implicitWidth + 2 * styler.themePaddingLarge * 1.5
    y: parent.height - referenceBlockBottom.height - height - styler.themePaddingLarge * 1.5
    z: 900

    property bool hidden: app.infoPanelOpen || app.modalDialog

    // keep the old size contract for anything that asks
    property real iconHeight: styler.themeIconSizeSmall

    layer.enabled: true

    LabelPL {
        id: label
        anchors.centerIn: parent
        color: "white"
        font.bold: true
        font.pixelSize: styler.themeFontSizeMedium
        text: {
            if (app.mode === modes.followMe) return app.tr("Stop");
            if (app.mode === modes.navigatePost) return app.tr("Done");
            return app.tr("Stop");
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -styler.themePaddingMedium
        onClicked: {
            var notifyId = "navigationStartPause";
            if (app.mode === modes.followMe) {
                notification.flash(app.tr("Stopped to follow the movement"), notifyId);
                app.navigator.followMe = false;
                app.resetMenu();
            } else if (app.mode === modes.navigatePost) {
                navigator.clearRoute();
            } else {
                notification.flash(app.tr("Navigation stopped"), notifyId);
                app.navigator.running = false;
            }
        }
    }
}
