import QtQuick
import qs.components
import qs.config

// A panel's title line with room for controls on the right.
Item {
    id: head
    property string icon: ""
    property string title: ""
    default property alias trailing: trail.data
    width: parent?.width ?? 0
    height: 28
    Row {
        anchors.verticalCenter: parent.verticalCenter
        x: 4
        spacing: 8
        Icon { anchors.verticalCenter: parent.verticalCenter; name: head.icon; size: 18; fill: 1; color: Theme.tone("action") }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.font
            font.pixelSize: Theme.title
            font.weight: Font.Medium
            color: Theme.text
            text: head.title
        }
    }
    Row {
        id: trail
        anchors.right: parent.right
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
    }
}
