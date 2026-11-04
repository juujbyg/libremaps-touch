/* -*- coding: utf-8-unix -*-
 *
 * LibreMaps: the speed limit as a road sign (white disc, red ring),
 * sitting on the top-right corner of the speed bubble. Without the speed
 * bubble it stands alone in the bottom-left corner.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.0
import QtGraphicalEffects 1.0

Item {
    id: sign

    x: driveSpeed.visible ? driveSpeed.x + driveSpeed.width * 0.68 : Math.round(styler.themePaddingMedium * 0.9)
    y: driveSpeed.visible ? driveSpeed.y - height * 0.42 : referenceBlockBottomLeft.y - height - styler.themePaddingMedium * 1.2
    height: width
    width: Math.round(styler.themePaddingMedium * (driveSpeed.visible ? 3.9 : 4.8))
    visible: {
        if (app.modalDialog) return false;
        if (app.conf.showSpeedLimit==="never" || !(app.mode === modes.navigate || app.mode === modes.followMe))
            return false;
        if (app.conf.showSpeedLimit==="exceeding") {
            if (!gps.speedValid || driveSpeed.limit <= 0)
                return false;
            if (gps.speed <= driveSpeed.limit)
                return false;
        }
        return limit.text.length > 0
    }
    z: 401

    Rectangle {
        anchors.fill: parent
        border.color: "#e53935"
        border.width: Math.round(sign.width * 0.13)
        color: "white"
        radius: width / 2
        layer.enabled: true
        layer.effect: DropShadow {
            color: "#000000"
            opacity: 0.3
            radius: 8
            samples: 17
            verticalOffset: 2
        }
    }

    Text {
        id: limit
        anchors.centerIn: parent
        color: "#111111"
        font.bold: true
        font.family: styler.themeFontFamilyHeading
        font.pixelSize: Math.round(sign.width * (text.length > 2 ? 0.34 : 0.42))
        text: {
            // speed limit in m/s, shown in the user's units
            if (driveSpeed.limit <= 0)
                return "";
            if (app.conf.units === "american" || app.conf.units === "british")
                return "%1".arg(Math.round(driveSpeed.limit * 2.23694));
            return "%1".arg(Math.round(driveSpeed.limit * 3.6));
        }
    }
}
