import QtQuick 2.9

// NumberFlow-style text: each digit rolls to its new value; other characters are plain text.
Row {
    id: roll

    property string text
    property real   pixelSize: styler.themeFontSizeMedium
    property color  color: styler.themePrimaryColor
    property int    weight: Font.DemiBold
    property string family: styler.themeFontFamilyHeading

    Repeater {
        model: roll.text.length

        delegate: Item {
            id: cell

            readonly property string ch: roll.text.charAt(index)
            readonly property bool digit: ch >= "0" && ch <= "9"

            clip: digit
            height: measure.height
            width: digit ? measure.width : plain.width

            Text {
                id: measure
                font.family: roll.family
                font.pixelSize: roll.pixelSize
                font.weight: roll.weight
                text: "0"
                visible: false
            }

            Text {
                id: plain
                color: roll.color
                font: measure.font
                text: cell.ch
                visible: !cell.digit
            }

            Column {
                visible: cell.digit
                y: cell.digit ? -Number(cell.ch) * measure.height : 0

                Behavior on y {
                    NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
                }

                Repeater {
                    model: 10
                    Text {
                        color: roll.color
                        font: measure.font
                        height: measure.height
                        text: index
                    }
                }
            }
        }
    }
}
