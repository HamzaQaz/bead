pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Demo mode, for screenshots and the demo reel (tools/screenshots.sh,
// tools/clip.sh): while it's on, bead shows made-up things instead of yours
// (services/demo.js): notifications, Wi-Fi, Bluetooth, the clipboard, the
// overview's windows, what's playing, your name, and no Discord. Nothing it
// shows is saved, and a restart turns it off.
//   qs ipc call demo on | off | notify N   (N: which made-up pop-up)
Singleton {
    id: root
    property bool on: false

    // what's playing, made up: shaped like an MprisPlayer, so the media views
    // take it as one. Its buttons work on it alone; your player is untouched.
    readonly property QtObject player: QtObject {
        property string identity: "Spotify"
        property string desktopEntry: "spotify"
        property string trackTitle: "Slow Light"
        property string trackArtist: "Coastal Hours"
        property string trackAlbum: "Long Weekend"
        property string trackArtUrl: Qt.resolvedUrl("../data/demo-cover.jpg")
        property real length: 228
        property real position: 71
        property bool isPlaying: true
        property real volume: 0.6
        property bool shuffle: false
        property var loopState: MprisLoopState.None
        readonly property bool canControl: true
        readonly property bool canTogglePlaying: true
        readonly property bool canGoNext: true
        readonly property bool canGoPrevious: true
        readonly property bool canSeek: true
        readonly property bool volumeSupported: true
        readonly property bool shuffleSupported: true
        readonly property bool loopSupported: true
        function togglePlaying(): void { isPlaying = !isPlaying; }
        function next(): void { position = 0; }
        function previous(): void { position = 0; }
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.on && root.player.isPlaying
        onTriggered: root.player.position = (root.player.position + 1) % root.player.length
    }

    IpcHandler {
        target: "demo"
        function on(): void { root.on = true; }
        function off(): void { root.on = false; }
        function notify(i: int): void { Notifs.demoNotify(i); }
    }
}
