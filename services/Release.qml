pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// bead's own version and updates. `version` is the installed VERSION; the
// first start of a new version says so on the island (what's new is in
// Settings → System). Once a day, and on asking, `bead update --check` looks
// for a newer release: state is uptodate | available | dev | package |
// nosource | offline (bin/bead-update).
Singleton {
    id: root

    property string version: ""
    property string state: ""
    property string newest: ""
    property bool checking: false
    readonly property bool available: state === "available"
    readonly property string changelog: Paths.share + "/CHANGELOG.md"

    FileView {
        path: Paths.share + "/VERSION"
        printErrors: false
        onLoaded: { root.version = text().trim(); seen.reload(); }
    }
    // the last version that started here: a different one is new
    FileView {
        id: seen
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/bead/seen-version"
        printErrors: false
        onLoaded: root.greet(text().trim())
        onLoadFailed: root.greet("")
    }
    function greet(was: string): void {
        if (!version || was === version) return;
        seen.setText(version + "\n");
        if (was) hello.start();   // not on a first install: the welcome does that
    }
    Timer { id: hello; interval: 4000; onTriggered: Osd.toast("new_releases", "bead " + root.version + " · what's new is in Settings", "info", 5000) }

    function check(): void { if (!probe.running) { checking = true; probe.running = true; } }
    Process {
        id: probe
        command: [Paths.cmd("bead-update"), "--check"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(" ");
                root.state = f[0] ?? "";
                root.newest = f[2] ?? "";
                root.checking = false;
            }
        }
    }
    // a minute after start, then daily
    Timer { running: true; interval: 60000; onTriggered: { root.check(); daily.start(); } }
    Timer { id: daily; interval: 24 * 3600 * 1000; repeat: true; onTriggered: root.check() }

    function update(): void {
        Quickshell.execDetached([Paths.cmd("bead-term"), "--title", "bead update", "--", "sh", "-c",
            '"$1"; echo; printf "Press Enter to close… "; read _', "sh", Paths.cmd("bead-update")]);
    }
    function whatsNew(): void { Quickshell.execDetached(["xdg-open", changelog]); }
}
