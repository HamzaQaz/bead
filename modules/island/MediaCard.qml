pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import qs.components
import qs.config
import qs.modules.dashboard

// The island's media card: what hovering it shows while something plays. Art,
// title and artist, previous / play-pause / next, and a bar you can click or
// drag to seek. Clicking anywhere else on it opens the full dashboard.
Item {
    id: root
    required property MprisPlayer player
    property bool active: false
    signal expand()

    readonly property real wantW: 460
    readonly property real wantH: 84

    // resting still on the music (art, title, artist) goes on to the
    // dashboard; the controls and the bar never do. Clicking it does at once
    Item {
        id: music
        width: controls.x - 6
        height: bar.y - 6
        HoverHandler {
            id: musicHover
            onHoveredChanged: hovered ? still.restart() : still.stop()
            onPointChanged: if (hovered) still.restart() // moved: start counting again
        }
        TapHandler { onTapped: root.expand() }
    }
    Timer { id: still; interval: 800; onTriggered: if (musicHover.hovered && root.active) root.expand() }

    Art {
        id: art
        x: 16
        y: 14
        width: 48; height: 48; radius: 12
        source: root.player?.trackArtUrl ?? ""
    }
    Column {
        x: art.x + art.width + 12
        y: 16
        width: controls.x - x - 10
        spacing: 1
        Text {
            width: parent.width
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 14
            font.weight: Font.DemiBold
            color: Theme.text
            text: root.player?.trackTitle ?? ""
        }
        Label {
            width: parent.width
            elide: Text.ElideRight
            font.pixelSize: 12
            text: root.player?.trackArtist ?? ""
        }
    }
    Row {
        id: controls
        anchors.right: parent.right
        anchors.rightMargin: 14
        y: 18
        spacing: 4
        Repeater {
            model: [
                { g: "skip_previous", ok: root.player?.canGoPrevious ?? false, go: () => root.player.previous() },
                { g: root.player?.isPlaying ? "pause" : "play_arrow", ok: root.player?.canTogglePlaying ?? false, go: () => root.player.togglePlaying(), main: true },
                { g: "skip_next", ok: root.player?.canGoNext ?? false, go: () => root.player.next() }
            ]
            Rectangle {
                id: cb
                required property var modelData
                width: modelData.main ? 38 : 32
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                opacity: modelData.ok ? 1 : 0.35
                color: modelData.main ? Theme.tone("action") : Qt.alpha(Theme.text, cma.containsMouse ? 0.1 : 0)
                scale: cma.pressed ? 0.9 : 1
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 150 } }
                Icon { anchors.fill: parent; name: cb.modelData.g; size: cb.modelData.main ? 22 : 20; fill: 1; color: cb.modelData.main ? Theme.frame : Theme.text }
                MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (cb.modelData.ok) cb.modelData.go() }
            }
        }
    }

    // ── progress: click or drag to seek ──
    readonly property real length: root.player?.length ?? 0
    readonly property real pos: root.player?.position ?? 0
    // MPRIS doesn't push the position: ask for it while the card shows
    Timer {
        interval: 500
        repeat: true
        running: root.active && !!root.player?.isPlaying && !seek.pressed
        onTriggered: root.player?.positionChanged()
    }
    function fmt(s: real): string {
        s = Math.max(0, Math.floor(s));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    Label {
        id: posLabel
        x: art.x
        anchors.verticalCenter: bar.verticalCenter
        width: 34
        font.pixelSize: 10
        font.features: { "tnum": 1 }
        text: root.fmt(seek.pressed ? seek.preview * root.length : root.pos)
    }
    Label {
        id: lenLabel
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: bar.verticalCenter
        font.pixelSize: 10
        font.features: { "tnum": 1 }
        text: root.fmt(root.length)
    }
    Rectangle {
        id: bar
        visible: root.length > 0
        x: posLabel.x + posLabel.width + 4
        y: root.height - 14
        width: lenLabel.x - 8 - x
        height: seek.containsMouse || seek.pressed ? 6 : 4
        radius: height / 2
        color: Qt.alpha(Theme.text, 0.12)
        Behavior on height { NumberAnimation { duration: 120 } }
        Rectangle {
            height: parent.height
            radius: parent.radius
            color: Theme.tone("action")
            width: parent.width * Math.max(0, Math.min(1, seek.pressed ? seek.preview : root.pos / Math.max(1, root.length)))
            Behavior on width { enabled: !seek.pressed; NumberAnimation { duration: 450 } }
        }
        MouseArea {
            id: seek
            anchors.fill: parent
            anchors.margins: -8
            hoverEnabled: true
            enabled: root.player?.canSeek ?? false
            cursorShape: Qt.PointingHandCursor
            property real preview: 0
            onPressed: e => preview = Math.max(0, Math.min(1, (e.x - 8) / bar.width))
            onPositionChanged: e => { if (pressed) preview = Math.max(0, Math.min(1, (e.x - 8) / bar.width)); }
            onReleased: {
                if (!root.player) return;
                root.player.position = preview * root.length;
                root.player.positionChanged();
            }
        }
    }
}
