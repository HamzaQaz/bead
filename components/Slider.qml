import QtQuick
import qs.config

// A horizontal slider: drag or click to set, scroll to nudge. Thickens on
// hover; the fill springs to the value.
Item {
    id: s
    property real value: 0          // 0-1 (higher values are clipped)
    property bool dim: false
    property color tone: dim ? Theme.neutral : Theme.tone("action")
    signal moved(real v)
    signal nudged(int dir)
    readonly property bool focusStop: true   // a stop for the dashboard's keyboard ring: Left/Right nudge it
    function focusAdjust(dir: int): void { nudged(dir); }
    implicitHeight: 20

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: area.containsMouse || area.pressed ? 8 : 6
        radius: height / 2
        color: Qt.alpha(s.tone, 0.16)
        Behavior on height { NumberAnimation { duration: 150 } }
        Rectangle {
            height: parent.height
            radius: height / 2
            width: Math.max(height, parent.width * Math.max(0, Math.min(1, s.value)))
            color: s.tone
            Behavior on width { SpringAnimation { spring: area.pressed ? 9 : 4.5; damping: area.pressed ? 0.45 : 0.3; epsilon: 0.2 } }
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        function at(x: real): real { return Math.max(0, Math.min(1, x / width)); }
        onPressed: e => s.moved(at(e.x))
        onPositionChanged: e => { if (pressed) s.moved(at(e.x)); }
        onWheel: e => s.nudged(e.angleDelta.y > 0 ? 1 : -1)
    }
}
