pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "pkgs.js" as Pkgs

// OS updates: checks the repos (checkupdates: a temporary copy of the sync
// database, no root, nothing changes), the AUR (paru -Qua) and Flathub
// (flatpak remote-ls --updates) a couple of minutes after start and every 3
// hours. `items` is the parsed list (pkgs.js), each marked when the computer
// should be restarted after it. A notification says when there are
// new ones; its Update button opens paru (or yay, or pacman) in a terminal, and a check follows.
Singleton {
    id: root

    property list<string> repo: []
    property list<string> aur: []
    property list<string> flatpak: []   // "app.id\tversion"
    readonly property var items: Pkgs.parseUpdates(repo.join("\n"), aur.join("\n"), flatpak.join("\n"))
    readonly property bool restart: items.some(u => u.restart)
    readonly property int count: repo.length + aur.length + flatpak.length
    property bool checking: false
    property bool checked: false   // a check has finished since bead started
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
        Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/bead-term", "--title", "System update", "--", "sh", "-c",
            "if command -v paru >/dev/null; then paru; elif command -v yay >/dev/null; then yay; else sudo pacman -Syu; fi; "
            + "if command -v flatpak >/dev/null && [ -n \"$(flatpak remote-ls --updates --app 2>/dev/null)\" ]; then echo; echo ':: Flatpak'; flatpak update; fi; "
            + "echo; printf 'Done. Press Enter to close… '; read _"]);
        recheck.restart();
    }

    Timer { interval: 2 * 60 * 1000; running: true; onTriggered: root.check() }
    Timer { interval: 3 * 3600 * 1000; repeat: true; running: true; onTriggered: root.check() }
    // after updating: look again once the terminal has had time
    Timer { id: recheck; interval: 10 * 60 * 1000; onTriggered: root.check() }

    Process {
        id: probe
        // two blocks: repo lines, a marker, AUR lines ("name old -> new")
        command: ["sh", "-c", "checkupdates 2>/dev/null; echo '--aur--'; if command -v paru >/dev/null; then paru -Qua; elif command -v yay >/dev/null; then yay -Qua; fi 2>/dev/null; "
            + "echo '--flatpak--'; command -v flatpak >/dev/null && flatpak remote-ls --updates --app --columns=application,version 2>/dev/null"]
        property list<string> lines: []
        stdout: SplitParser { onRead: line => probe.lines = [...probe.lines, line] }
        onStarted: lines = []
        onExited: {
            const i = lines.indexOf("--aur--"), j = lines.indexOf("--flatpak--");
            const clean = l => l.trim() && !l.includes("[ignored]");
            root.repo = lines.slice(0, i < 0 ? lines.length : i).filter(clean);
            root.aur = i < 0 ? [] : lines.slice(i + 1, j < 0 ? lines.length : j).filter(clean);
            root.flatpak = j < 0 ? [] : lines.slice(j + 1).filter(clean);
            root.checking = false;
            root.checked = true;
            root.maybeNotify();
        }
    }

    function maybeNotify(): void {
        const key = items.map(u => u.name).sort().join(",");
        if (count === 0) { if (notified) remember(""); return; }
        if (key === notified) return; // nothing new since we last said
        remember(key);
        const names = items.map(u => u.name);
        const body = (restart ? "Restart after: " + items.filter(u => u.restart).map(u => u.name).join(", ") + ". " : "")
            + names.slice(0, 6).join(", ") + (names.length > 6 ? " and " + (names.length - 6) + " more" : "")
            + (aur.length ? " · " + aur.length + " from the AUR" : "") + (flatpak.length ? " · " + flatpak.length + " Flatpak" + (flatpak.length > 1 ? "s" : "") : "");
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
        function status(): string { return root.checking ? "checking" : root.count + " (" + root.repo.length + " repo, " + root.aur.length + " aur, " + root.flatpak.length + " flatpak)"; }
        function list(): string { return root.items.map(u => u.source + "\t" + u.name + "\t" + u.from + " -> " + u.to + (u.restart ? "\trestart" : "")).join("\n"); }
    }
}
