/* -*- coding: utf-8-unix -*-
 *
 * Copyright (C) 2018 Rinigus
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import QtQuick 2.9
import Lomiri.Components 1.3

// LibreMaps: system theme icons (image://theme/...) are drawn by Lomiri's Icon and tinted
// with the theme. Our own SVGs (icons/ui/<name>-<tone>.svg) already come in the right
// colour for each theme, so they are drawn by a plain Image, untinted.
Item {
    id: image
    height: iconHeight ? iconHeight : (themed ? icon.implicitHeight : styler.themeIconSizeSmall)
    width: iconWidth ? iconWidth : (themed ? icon.width : picture.width)

    property var    fillMode // unused, kept for compatibility
    property bool   iconColorize: true
    property int    iconHeight: 0
    property string iconName
    property string iconSource
    property int    iconWidth: 0

    readonly property string src: iconName ? iconName : iconSource
    readonly property bool   themed: src.indexOf("image://theme/") === 0

    Icon {
        id: icon
        color: image.iconColorize ? styler.themeHighlightColor : "transparent"
        height: image.height
        source: image.themed ? image.src : ""
        visible: image.themed
        width: image.iconWidth ? image.iconWidth : undefined
    }

    Image {
        id: picture
        fillMode: Image.PreserveAspectFit
        height: image.height
        smooth: true
        source: image.themed ? "" : image.src
        sourceSize.height: image.height > 0 ? image.height * 2 : undefined
        visible: !image.themed
        // implicit size follows sourceSize (twice the height), so keep the aspect by hand
        width: image.iconWidth ? image.iconWidth :
               (implicitHeight > 0 ? height * implicitWidth / implicitHeight : height)
    }
}
