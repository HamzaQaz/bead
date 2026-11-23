pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import qs.components
import qs.config

// previous / play-pause / next, with optional shuffle and loop.
Row {
    id: root
    property MprisPlayer player
    property real size: 44
    property bool extras: false
    spacing: 14

    component Btn: Rectangle {
        id: b
        property string icon: ""
        property bool big: false
        property bool active: false
        signal clicked()
        width: big ? root.size : root.size * 0.76
        height: width
        radius: width / 2
        anchors.verticalCenter: parent?.verticalCenter
        color: big ? Theme.tone("action") : Qt.alpha(Theme.text, active ? 0.16 : ma.containsMouse ? 0.12 : 0.06)
        scale: ma.pressed ? 0.88 : 1
        Behavior on scale { SpringAnimation { spring: 6; damping: 0.3 } }
        Behavior on color { ColorAnimation { duration: 150 } }
        Icon {
            anchors.centerIn: parent
            name: b.icon
            size: b.big ? root.size * 0.5 : root.size * 0.36
            fill: 1
            color: b.big ? Theme.frame : b.active ? Theme.tone("action") : Theme.text
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
    }

    Btn {
        visible: root.extras && (root.player?.shuffleSupported ?? false)
        icon: "shuffle"
        active: root.player?.shuffle ?? false
        onClicked: root.player.shuffle = !root.player.shuffle
    }
    Btn { icon: "skip_previous"; onClicked: root.player?.previous() }
    Btn { big: true; icon: root.player?.isPlaying ? "pause" : "play_arrow"; onClicked: root.player?.togglePlaying() }
    Btn { icon: "skip_next"; onClicked: root.player?.next() }
    Btn {
        visible: root.extras && (root.player?.loopSupported ?? false)
        icon: root.player?.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
        active: (root.player?.loopState ?? MprisLoopState.None) !== MprisLoopState.None
        onClicked: root.player.loopState = root.player.loopState === MprisLoopState.None ? MprisLoopState.Playlist
            : root.player.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None
    }
}
