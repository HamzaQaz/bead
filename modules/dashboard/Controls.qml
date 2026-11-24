pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import qs.components
import qs.config

// previous / play-pause / next, with optional shuffle and loop.
//  - play/pause: one shape that morphs (bars bend into the triangle); a ring
//    ripples out of the button on every press; it breathes while playing
//  - skip: the glyph kicks the way you went
//  - shuffle / loop: a dot under them while they're on
Row {
    id: root
    property MprisPlayer player
    property real size: 44
    property bool extras: false
    spacing: 14
    readonly property bool playing: player?.isPlaying ?? false

    component Btn: Item {
        id: b
        property string icon: ""
        property bool big: false
        property bool active: false
        property real kick: 0 // -1 back, 1 forward: the glyph jumps that way
        signal clicked()
        readonly property bool focusStop: true   // a stop for the dashboard's keyboard ring
        readonly property real focusRadius: width / 2
        function focusPress(): void { b.clicked(); }
        width: big ? root.size : root.size * 0.76
        height: width
        anchors.verticalCenter: parent?.verticalCenter

        // the big one breathes while music plays (on the outer item, so it
        // doesn't fight the hover/press scale of the face)
        SequentialAnimation {
            running: b.big && root.playing
            loops: Animation.Infinite
            onRunningChanged: if (!running) b.scale = 1
            NumberAnimation { target: b; property: "scale"; to: 1.04; duration: 1100; easing.type: Easing.InOutSine }
            NumberAnimation { target: b; property: "scale"; to: 1; duration: 1100; easing.type: Easing.InOutSine }
        }

        function press(): void {
            ripple.restart();
            if (kick !== 0) kickAnim.restart();
            clicked();
        }

        // the ripple: a ring that grows out and fades on each press
        Rectangle {
            id: ring
            anchors.centerIn: parent
            width: parent.width; height: width; radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: b.big ? Theme.tone("action") : Qt.alpha(Theme.text, 0.5)
            opacity: 0
            ParallelAnimation {
                id: ripple
                NumberAnimation { target: ring; property: "scale"; from: 1; to: 1.55; duration: 520; easing.type: Easing.OutCubic }
                NumberAnimation { target: ring; property: "opacity"; from: 0.7; to: 0; duration: 520; easing.type: Easing.OutCubic }
            }
        }
        Rectangle {
            id: face
            anchors.fill: parent
            radius: width / 2
            color: b.big ? Theme.tone("action") : Qt.alpha(Theme.text, b.active ? 0.16 : ma.containsMouse ? 0.12 : 0.06)
            scale: ma.pressed ? 0.86 : ma.containsMouse ? 1.05 : 1
            Behavior on scale { SpringAnimation { spring: 6; damping: 0.28; epsilon: 0.002 } }
            Behavior on color { ColorAnimation { duration: 150 } }
            PlayPause { // the big one: a shape that morphs between play and pause
                visible: b.big
                anchors.centerIn: parent
                size: root.size * 0.46
                playing: root.playing
                color: Theme.frame
            }
            Icon { // the glyph being replaced, fading out during a morph
                id: ghost
                anchors.centerIn: parent
                opacity: 0
                size: glyph.size
                fill: 1
                color: glyph.color
            }
            Icon {
                id: glyph
                visible: !b.big
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: b.kick * kickX
                property real kickX: 0
                name: b.icon
                size: b.big ? root.size * 0.5 : root.size * 0.36
                fill: 1
                color: b.big ? Theme.frame : b.active ? Theme.tone("action") : Theme.text
                Behavior on color { ColorAnimation { duration: 150 } }
                // a new glyph (play <-> pause, repeat <-> repeat one): the old one
                // shrinks away under it while this one grows in and settles
                property string last: ""
                onNameChanged: {
                    if (b.big) return;
                    if (last && last !== name) { ghost.name = last; morph.restart(); }
                    last = name;
                }
                Component.onCompleted: last = name
                ParallelAnimation {
                    id: morph
                    NumberAnimation { target: glyph; property: "scale"; from: 0.55; to: 1; duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                    NumberAnimation { target: glyph; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
                    NumberAnimation { target: ghost; property: "scale"; from: 1; to: 0.55; duration: 200; easing.type: Easing.InCubic }
                    NumberAnimation { target: ghost; property: "opacity"; from: 1; to: 0; duration: 160; easing.type: Easing.InCubic }
                }
                SequentialAnimation {
                    id: kickAnim
                    NumberAnimation { target: glyph; property: "kickX"; to: 7; duration: 90; easing.type: Easing.OutQuad }
                    NumberAnimation { target: glyph; property: "kickX"; to: 0; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2 }
                }
            }
        }
        // on (shuffle, loop): a dot underneath
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height + 4
            width: b.active ? 4 : 0
            height: width
            radius: width / 2
            color: Theme.tone("action")
            Behavior on width { SpringAnimation { spring: 5; damping: 0.3 } }
        }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.press() }
    }

    Btn {
        visible: root.extras && (root.player?.shuffleSupported ?? false)
        icon: "shuffle"
        active: root.player?.shuffle ?? false
        onClicked: root.player.shuffle = !root.player.shuffle
    }
    Btn { icon: "skip_previous"; kick: -1; onClicked: root.player?.previous() }
    Btn { big: true; icon: root.playing ? "pause" : "play_arrow"; onClicked: root.player?.togglePlaying() }
    Btn { icon: "skip_next"; kick: 1; onClicked: root.player?.next() }
    Btn {
        visible: root.extras && (root.player?.loopSupported ?? false)
        icon: root.player?.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
        active: (root.player?.loopState ?? MprisLoopState.None) !== MprisLoopState.None
        onClicked: root.player.loopState = root.player.loopState === MprisLoopState.None ? MprisLoopState.Playlist
            : root.player.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None
    }
}
