import QtQuick
import Quickshell.Services.Mpris
import qs.components
import qs.config

// Track progress; click or drag to seek (when the player allows it). Hovering
// thickens the bar and grows a knob at the playhead; dragging shows the time
// you'd land on in a bubble over it. The right label counts down.
Column {
    id: root
    property var player   // an MprisPlayer, or demo mode's made-up one
    property real barHeight: 4
    spacing: 4
    readonly property real len: player?.length ?? 0
    readonly property real frac: len > 0 ? Math.min(1, (player?.position ?? 0) / len) : 0
    readonly property bool hot: seek.containsMouse || seek.pressed
    readonly property real shown: seek.pressed ? seek.drag : frac

    function fmt(s: real): string {
        s = Math.max(0, Math.floor(s));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    Item {
        width: parent.width
        height: 16
        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: root.hot ? root.barHeight + 3 : root.barHeight
            radius: height / 2
            color: Qt.alpha(Theme.text, 0.1)
            Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Rectangle {
                id: fill
                height: parent.height
                radius: height / 2
                color: Theme.tone("action")
                width: Math.max(height, parent.width * root.shown)
                Behavior on width { enabled: !seek.pressed; NumberAnimation { duration: 900; easing.type: Easing.Linear } }
            }
        }
        // the knob: grows at the playhead while you're over the bar
        Rectangle {
            anchors.verticalCenter: track.verticalCenter
            x: fill.width - width / 2
            width: root.hot ? (seek.pressed ? 16 : 12) : 0
            height: width
            radius: width / 2
            color: Theme.text
            visible: width > 0.5
            Behavior on width { SpringAnimation { spring: 6; damping: 0.3; epsilon: 0.2 } }
        }
        // dragging: the time under your finger
        Rectangle {
            visible: opacity > 0.01
            opacity: seek.pressed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
            x: Math.max(0, Math.min(parent.width - width, fill.width - width / 2))
            y: -height - 6
            width: bubble.implicitWidth + 14
            height: 20
            radius: 10
            color: Theme.text
            Text {
                id: bubble
                anchors.centerIn: parent
                font.family: Theme.font
                font.pixelSize: Theme.caption
                font.weight: Font.Medium
                font.features: { "tnum": 1 }
                color: Theme.frame
                text: root.fmt(seek.drag * root.len)
            }
        }
        MouseArea {
            id: seek
            anchors.fill: parent
            anchors.topMargin: -4
            anchors.bottomMargin: -4
            hoverEnabled: true
            enabled: root.player?.canSeek ?? false
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            property real drag: 0
            onPressed: e => drag = Math.max(0, Math.min(1, e.x / width))
            onPositionChanged: e => { if (pressed) drag = Math.max(0, Math.min(1, e.x / width)); }
            onReleased: if (root.player) { root.player.position = drag * root.len; root.player.positionChanged(); }
        }
    }
    Item {
        width: parent.width
        height: 12
        Label { font.pixelSize: Theme.tiny; font.features: { "tnum": 1 }; text: root.fmt(root.shown * root.len) }
        Label { anchors.right: parent.right; font.pixelSize: Theme.tiny; font.features: { "tnum": 1 }; text: "-" + root.fmt(root.len - root.shown * root.len) }
    }
}
