pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// OS updates: checks the repos (checkupdates: a temporary copy of the sync
// database, no root, nothing changes) and the AUR (paru -Qua) a couple of
// minutes after start and every 3 hours. A notification says when there are
// new ones; its Update button opens paru in a terminal, and a check follows.
Singleton {
    id: root

    property list<string> repo: []
    property list<string> aur: []
    readonly property int count: repo.length + aur.length
    property bool checking: false
    // the set we last told you about, kept across restarts so a restart
    // doesn't tell you again
    property string notified: seen.loaded ? seen.text().trim() : ""
    FileView {
        id: seen
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/bead/updates-notified"
        blockLoading: true
        printErrors: false
    }
    function remember(key: string): void {
        notified = key;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "sh", seen.path, key]);
    }

    function check(): void { if (!probe.running) { checking = true; probe.running = true; } }
    function update(): void {
        Quickshell.execDetached(["kitty", "--title", "System update", "sh", "-c",
            "paru; echo; read -rp 'Done. Press Enter to close… ' _"]);
        recheck.restart();
    }

    Timer { interval: 2 * 60 * 1000; running: true; onTriggered: root.check() }
    Timer { interval: 3 * 3600 * 1000; repeat: true; running: true; onTriggered: root.check() }
    // after updating: look again once the terminal has had time
    Timer { id: recheck; interval: 10 * 60 * 1000; onTriggered: root.check() }

    Process {
        id: probe
        // two blocks: repo lines, a marker, AUR lines ("name old -> new")
        command: ["sh", "-c", "checkupdates 2>/dev/null; echo '--aur--'; paru -Qua 2>/dev/null"]
        property list<string> lines: []
        stdout: SplitParser { onRead: line => probe.lines = [...probe.lines, line] }
        onStarted: lines = []
        onExited: {
            const i = lines.indexOf("--aur--");
            const clean = l => l.trim() && !l.includes("[ignored]");
            root.repo = lines.slice(0, i < 0 ? lines.length : i).filter(clean);
            root.aur = i < 0 ? [] : lines.slice(i + 1).filter(clean);
            root.checking = false;
            root.maybeNotify();
        }
    }

    function maybeNotify(): void {
        const key = [...repo, ...aur].map(l => l.split(" ")[0]).sort().join(",");
        if (count === 0) { if (notified) remember(""); return; }
        if (key === notified) return; // nothing new since we last said
        remember(key);
        const names = [...repo, ...aur].map(l => l.split(" ")[0]);
        const kernel = names.some(n => /^linux(-cachyos)?(-lts|-zen)?$/.test(n));
        const body = (kernel ? "Includes a new kernel (reboot after). " : "")
            + names.slice(0, 6).join(", ") + (names.length > 6 ? " and " + (names.length - 6) + " more" : "")
            + (aur.length ? " · " + aur.length + " from the AUR" : "");
        notifier.command = ["sh", "-c",
            'a=$(timeout 3600 notify-send -a "System updates" -i system-software-update -A update=Update -A later=Later "$1" "$2"); [ "$a" = update ] && echo update',
            "sh", count + (count === 1 ? " update available" : " updates available"), body];
        notifier.running = true;
    }
    Process {
        id: notifier
        stdout: SplitParser { onRead: line => { if (line === "update") root.update(); } }
    }

    IpcHandler {
        target: "updates"
        function check(): void { root.check(); }
        function update(): void { root.update(); }
        function status(): string { return root.checking ? "checking" : root.count + " (" + root.repo.length + " repo, " + root.aur.length + " aur)"; }
        function list(): string { return [...root.repo, ...root.aur].join("\n"); }
    }
}
