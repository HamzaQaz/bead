import QtQuick
import qs.components
import qs.config

// A labelled horizontal level bar.
Column {
    id: gg
    property string label: ""
    property string value: ""
    property real level: 0
    width: parent.width
    spacing: 5
    Item {
        width: parent.width
        height: 14
        Label { text: gg.label; font.pixelSize: Theme.caption }
        Label {
            anchors.right: parent.right
            text: gg.value
            font.pixelSize: Theme.caption
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
            color: Theme.text
        }
    }
    Rectangle {
        width: parent.width
        height: 6
        radius: 3
        color: Qt.alpha(Theme.text, 0.08)
        Rectangle {
            height: parent.height
            radius: 3
            width: Math.max(height, parent.width * Math.max(0, Math.min(1, gg.level)))
            color: gg.level > 0.85 ? Theme.tone("error") : Theme.tone("action")
            Behavior on width { SpringAnimation { spring: 4; damping: 0.3; epsilon: 0.2 } }
            Behavior on color { ColorAnimation { duration: 300 } }
        }
    }
}
