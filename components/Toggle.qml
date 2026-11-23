import QtQuick
import qs.config

// An on/off switch.
Rectangle {
    id: sw
    property bool checked: false
    signal toggled()
    width: 36
    height: 20
    radius: 10
    color: checked ? Theme.tone("action") : Qt.alpha(Theme.text, 0.15)
    Behavior on color { ColorAnimation { duration: 180 } }
    Rectangle {
        y: 3
        x: sw.checked ? sw.width - width - 3 : 3
        width: 14; height: 14; radius: 7
        color: sw.checked ? Theme.frame : Theme.text
        Behavior on x { SpringAnimation { spring: 5; damping: 0.35; epsilon: 0.2 } }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
}
