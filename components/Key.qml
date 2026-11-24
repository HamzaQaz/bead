import QtQuick
import qs.config

// a keyboard key
Rectangle {
    property string text: ""
    width: Math.max(24, kt.implicitWidth + 12)
    height: 22
    radius: 6
    color: Qt.alpha(Theme.text, 0.08)
    border.width: 1
    border.color: Qt.alpha(Theme.text, 0.1)
    Text { id: kt; anchors.centerIn: parent; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold; color: Theme.text; text: parent.text }
}
