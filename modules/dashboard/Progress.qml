import QtQuick
import Quickshell.Services.Mpris
import qs.components
import qs.config

// Track progress; click or drag to seek (when the player allows it).
Column {
    id: root
    property MprisPlayer player
    property real barHeight: 4
    spacing: 4
    readonly property real len: player?.length ?? 0
    readonly property real frac: len > 0 ? Math.min(1, (player?.position ?? 0) / len) : 0

    function fmt(s: real): string {
        s = Math.max(0, Math.floor(s));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    Item {
        width: parent.width
        height: 14
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: seek.containsMouse || seek.pressed ? root.barHeight + 3 : root.barHeight
            radius: height / 2
            color: Qt.alpha(Theme.text, 0.1)
            Behavior on height { NumberAnimation { duration: 150 } }
            Rectangle {
                height: parent.height
                radius: height / 2
                color: Theme.tone("action")
                width: parent.width * (seek.pressed ? seek.drag : root.frac)
                Behavior on width { enabled: !seek.pressed; NumberAnimation { duration: 900; easing.type: Easing.Linear } }
            }
        }
        MouseArea {
            id: seek
            anchors.fill: parent
            hoverEnabled: true
            enabled: root.player?.canSeek ?? false
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            property real drag: 0
            onPressed: e => drag = Math.max(0, Math.min(1, e.x / width))
            onPositionChanged: e => { if (pressed) drag = Math.max(0, Math.min(1, e.x / width)); }
            onReleased: if (root.player) { root.player.position = drag * root.len; }
        }
    }
    Item {
        width: parent.width
        height: 12
        Label { font.pixelSize: 10; font.features: { "tnum": 1 }; text: root.fmt(root.player?.position ?? 0) }
        Label { anchors.right: parent.right; font.pixelSize: 10; font.features: { "tnum": 1 }; text: root.fmt(root.len) }
    }
}
