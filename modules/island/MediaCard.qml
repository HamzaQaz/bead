pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Mpris
import qs.components
import qs.config
import qs.modules.dashboard
import qs.services

// The island's media card: what hovering it shows while something plays.
//   ┌───────────────────────────────────────────────┐
//   │ [art]  Title                     ⏮  ⏯  ⏭     │  top row, centred on the art
//   │        Artist                                  │
//   │ 1:24  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  3:58   │  seek bar (or volume, while scrolling)
//   └───────────────────────────────────────────────┘
// After a moment it goes on to the dashboard, but never while you're using it
// (controls, seek bar, scrolling the volume). Clicking the card goes at once.
Item {
    id: root
    required property var player   // an MprisPlayer, or demo mode's made-up one
    property bool active: false
    property bool pointerIn: false // the island is hovered (passed in)
    signal expand()

    property real radius: 0 // the island's corners, for the cover behind it
    readonly property real pad: 16
    readonly property real artSize: 48
    readonly property real rowH: 18
    readonly property real wantW: 440
    // the bottom row only when there's something in it
    readonly property real wantH: pad + artSize + (seekable || volHide.running ? 12 + rowH + pad - 2 : pad)

    // ── on to the dashboard ──
    readonly property bool usingControls: controlsHover.hovered || seekHover.hovered || seek.pressed || volHide.running
    Timer {
        interval: 800
        running: root.active && root.pointerIn && !root.usingControls // restarts after you stop using it
        onTriggered: root.expand()
    }
    // the cover, behind it all
    CoverBackdrop { anchors.fill: parent; radius: root.radius; source: root.player?.trackArtUrl ?? ""; blur: 0.6; veil: 0.4 }
    MouseArea { // clicking the card itself: at once
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.expand()
    }

    // ── top row: art, title and artist, controls ──
    Art {
        id: art
        x: root.pad
        y: root.pad
        width: root.artSize; height: root.artSize; radius: 12
        source: root.player?.trackArtUrl ?? ""
    }
    Column {
        anchors.left: art.right
        anchors.leftMargin: 12
        anchors.right: controls.left
        anchors.rightMargin: 12
        anchors.verticalCenter: art.verticalCenter
        spacing: 2
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
            visible: text !== ""
            elide: Text.ElideRight
            font.pixelSize: 12
            text: root.player?.trackArtist ?? ""
        }
    }
    Row {
        id: controls
        anchors.right: parent.right
        anchors.rightMargin: root.pad - 4
        anchors.verticalCenter: art.verticalCenter
        spacing: 4
        HoverHandler { id: controlsHover }
        Repeater {
            model: [
                { g: "skip_previous", ok: root.player?.canGoPrevious ?? false, go: () => root.player.previous() },
                { g: root.player?.isPlaying ? "pause" : "play_arrow", ok: root.player?.canTogglePlaying ?? false, go: () => root.player.togglePlaying(), main: true },
                { g: "skip_next", ok: root.player?.canGoNext ?? false, go: () => root.player.next() }
            ]
            Rectangle {
                id: cb
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                width: modelData.main ? 40 : 34
                height: width
                radius: width / 2
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

    // ── bottom row: the seek bar, or the volume while you scroll ──
    Item {
        id: bottom
        x: root.pad
        y: art.y + art.height + 12
        width: root.width - root.pad * 2
        height: root.rowH
    }

    // volume: scroll anywhere on the card. The player's own (MPRIS) when it has
    // one, else the system's
    readonly property bool ownVolume: root.player?.volumeSupported ?? false
    readonly property real vol: ownVolume ? root.player.volume : Audio.volume
    function setVol(v: real): void {
        v = Math.max(0, Math.min(1, v));
        if (ownVolume) root.player.volume = v; else Audio.setVolume(v);
    }
    property real volT: volHide.running ? 1 : 0
    Behavior on volT { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Timer { id: volHide; interval: 1200 }
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: e => {
            root.setVol(root.vol + (e.angleDelta.y > 0 ? 0.05 : -0.05));
            volHide.restart();
        }
    }

    // seek: click or drag. Hidden for streams with no length (Spotify's DJ…)
    readonly property real length: root.player?.length ?? 0
    readonly property real pos: root.player?.position ?? 0
    readonly property bool seekable: length > 0
    Timer { // MPRIS doesn't push the position: ask for it while the card shows
        interval: 500
        repeat: true
        running: root.active && !!root.player?.isPlaying && !seek.pressed
        onTriggered: root.player?.positionChanged()
    }
    function fmt(s: real): string {
        s = Math.max(0, Math.floor(s));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    // a level row: [lead]  ━━━━━━━━━  [trail]
    component LevelRow: Item {
        id: lr
        property string lead
        property string trail
        property real value: 0
        property bool thick: false
        property alias track: trackRect
        default property alias leadItem: leadSlot.data
        anchors.fill: bottom
        Item {
            id: leadSlot
            width: 34
            height: parent.height
            Label {
                visible: lr.lead !== ""
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 11
                font.features: { "tnum": 1 }
                text: lr.lead
            }
        }
        Rectangle {
            id: trackRect
            anchors.left: leadSlot.right
            anchors.right: trailLabel.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            height: lr.thick ? 6 : 4
            radius: height / 2
            color: Qt.alpha(Theme.text, 0.12)
            Behavior on height { NumberAnimation { duration: 120 } }
            Rectangle {
                height: parent.height
                radius: parent.radius
                color: Theme.tone("action")
                width: parent.width * Math.max(0, Math.min(1, lr.value))
            }
        }
        Label {
            id: trailLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            horizontalAlignment: Text.AlignRight
            font.pixelSize: 11
            font.features: { "tnum": 1 }
            text: lr.trail
        }
    }

    LevelRow {
        id: seekRow
        opacity: (1 - root.volT) * (root.seekable ? 1 : 0)
        visible: opacity > 0.01
        lead: root.fmt(seek.pressed ? seek.preview * root.length : root.pos)
        trail: root.fmt(root.length)
        value: seek.pressed ? seek.preview : root.pos / Math.max(1, root.length)
        thick: seekHover.hovered || seek.pressed
        HoverHandler { id: seekHover; margin: 6 }
        MouseArea {
            id: seek
            x: seekRow.track.x
            width: seekRow.track.width
            height: parent.height
            enabled: root.player?.canSeek ?? false
            cursorShape: Qt.PointingHandCursor
            property real preview: 0
            function at(x: real): real { return Math.max(0, Math.min(1, x / width)); }
            onPressed: e => preview = at(e.x)
            onPositionChanged: e => { if (pressed) preview = at(e.x); }
            onReleased: {
                if (!root.player) return;
                root.player.position = preview * root.length;
                root.player.positionChanged();
            }
        }
    }
    LevelRow {
        opacity: root.volT
        visible: opacity > 0.01
        value: root.vol
        thick: true
        trail: Math.round(root.vol * 100) + "%"
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: root.vol <= 0.001 ? "volume_off" : root.vol < 0.5 ? "volume_down" : "volume_up"
            ref: "volume_up"
            size: 16
            fill: 1
            color: Theme.subtext
        }
    }
}
