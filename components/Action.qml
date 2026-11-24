import QtQuick
import qs.config

// a small round-cornered button with words
Rectangle {
    id: act
    property string text: ""
    property string glyph: ""
    property bool accent: false
    signal hit()
    width: actRow.implicitWidth + 22
    height: 28
    radius: 14
    color: accent ? Theme.tone("action") : Qt.alpha(Theme.text, aMa.pressed ? 0.16 : aMa.containsMouse ? 0.11 : 0.06)
    scale: aMa.pressed ? 0.94 : 1
    Behavior on scale { SpringAnimation { spring: 6; damping: 0.3; epsilon: 0.002 } }
    Row {
        id: actRow
        anchors.centerIn: parent
        spacing: 5
        Icon { visible: act.glyph !== ""; anchors.verticalCenter: parent.verticalCenter; name: act.glyph; size: 15; color: act.accent ? Theme.frame : Theme.text }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
            color: act.accent ? Theme.frame : Theme.text
            text: act.text
        }
    }
    MouseArea { id: aMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: act.hit() }
}
