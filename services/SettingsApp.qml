pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The Settings window (modules/settings): whether it's open, and on which
// page. Opened from the dashboard, the launcher, or `bead settings [page]`.
Singleton {
    id: root

    property bool open: false
    property string page: "appearance"
    property string query: ""   // the search box

    function show(p: string): void {
        if (p) page = p;
        open = true;
    }

    IpcHandler {
        target: "settings"
        function open(page: string): void { root.show(page); }
        function close(): void { root.open = false; }
        function toggle(): void { root.open = !root.open; }
        function search(words: string): void { root.query = words; root.open = true; }
    }
}
