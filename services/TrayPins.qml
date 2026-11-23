pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Which tray apps are pinned to the bar (the rest live in the tray panel),
// saved to $XDG_STATE_HOME/bead/tray.json by tray item id.
Singleton {
    id: root

    property list<string> pinned: []

    function isPinned(id: string): bool { return pinned.includes(id); }
    function toggle(id: string): void {
        pinned = isPinned(id) ? pinned.filter(p => p !== id) : [...pinned, id];
    }

    property bool loaded: false
    onPinnedChanged: if (loaded) saveTimer.restart()
    Timer { id: saveTimer; interval: 300; onTriggered: store.setText(JSON.stringify({ pinned: root.pinned })) }
    FileView {
        id: store
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/bead/tray.json"
        blockLoading: true
        printErrors: false
        atomicWrites: true
        onLoaded: { try { root.pinned = JSON.parse(text()).pinned ?? []; } catch (e) {} root.loaded = true; }
        onLoadFailed: root.loaded = true
    }
}
