pragma Singleton

import Quickshell
import Quickshell.Io

// Demo mode, for screenshots (tools/screenshots.sh): hides what's yours (your
// name in the greeting, Discord calls and DMs) while it's on. Not saved: a
// restart turns it off. `qs ipc call demo on|off`
Singleton {
    id: root
    property bool on: false
    IpcHandler {
        target: "demo"
        function on(): void { root.on = true; }
        function off(): void { root.on = false; }
    }
}
