pragma Singleton

import QtQuick
import Quickshell
import qs.config
import Quickshell.Io
import "pkgs.js" as Pkgs
import "sysupdate.js" as U
import "reboot.js" as R
import "trust.js" as T
import "store.js" as S

// OS updates: checks the repos (checkupdates: a temporary copy of the sync
// database, no root, nothing changes), the AUR (paru -Qua) and Flathub
// (flatpak remote-ls --updates) a couple of minutes after start and every 3
// hours. `items` is the parsed list (pkgs.js), each marked when the computer
// should be restarted after it. A notification says when there are
// new ones. Update runs it all without a terminal (bin/bead-sysupdate),
// shown in the island (modules/island/UpdateView.qml): AUR changes to look at
// first, then which app it's on and how far along, the output on demand, and
// how it went. Passwords are asked by bead's polkit agent (services/Polkit.qml).
// If it fails, "Open in a terminal" runs the old way (paru in a terminal).
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
    // ── updating ──
    // "" | review (AUR changes to look at first) | running | done | failed
    property string phase: ""
    readonly property bool running: phase === "running"
    property bool shown: false          // in the island (Hide keeps it running)
    property var counts: ({ repo: 0, aur: 0, flatpak: 0 })
    property var aurNames: []           // what the review lists (the riskiest first, once checked)

    // ── is each AUR update real and safe-looking? (services/trust.js): the
    // AUR's facts and its build files, read by bin/bead-pkgcheck during the
    // review. name → { level: ok|caution|danger, reasons, notes } ──
    property var trust: ({})
    readonly property bool trustChecking: trustProbe.running
    readonly property string trustWorst: aurNames.reduce((w, n) => {
        const l = trust[n]?.level ?? "ok";
        return l === "danger" || w === "danger" ? "danger" : l === "caution" || w === "caution" ? "caution" : "ok";
    }, "ok")
    function checkTrust(names: var): void {
        trust = {};
        if (!names.length) return;
        trustProbe.command = [Paths.cmd("bead-pkgcheck"), "aur", ...names];
        trustProbe.running = true;
    }
    Process {
        id: trustProbe
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try { list = JSON.parse(text); } catch (e) { return; }
                const now = Date.now() / 1000, t = {};
                for (const p of list) {
                    let found = [];
                    for (const f in p.files ?? {}) found = found.concat(T.scan(p.files[f]));
                    t[p.name] = T.verdict(T.aurRisk(p.exists ? p.info : null, now), found);
                }
                root.trust = t;
                const rank = { danger: 0, caution: 1, ok: 2 };
                root.aurNames = root.aurNames.slice().sort((a, b) => (rank[t[a]?.level] ?? 2) - (rank[t[b]?.level] ?? 2));
            }
        }
    }
    property string stage: ""           // repo | aur | flatpak
    property string current: ""         // the package being worked on
    property string doing: ""           // upgrading | downloading | building…
    property int stepI: 0
    property int stepN: 0
    readonly property real progress: running ? (job ? S.installFraction(inst) : U.progress(counts, stage, stepI, stepN)) : phase === "done" ? 1 : 0

    // ── one app from the App Store, on the same card (services/Store.qml) ──
    property var job: null              // { title, name, source, icon }
    property var inst: S.installStart() // its progress (store.js)
    signal appInstalled(var job)
    function installApp(j: var): bool {
        if (running || phase === "review") { shown = true; return false; }
        job = j; inst = S.installStart();
        stage = "install"; current = ""; doing = ""; stepI = 0; stepN = 0;
        log = []; error = ""; failedStage = ""; updated = [];
        needsRestart = false;
        runner.command = [Paths.cmd("bead-sysupdate"), ...S.installArgs(j)];
        phase = "running"; shown = true;
        runner.running = true;
        return true;
    }
    property list<string> log: []
    property string error: ""
    property string failedStage: ""
    property list<string> updated: []   // names finished, newest last
    // the update included something that wants a restart (kernel, glibc, systemd…):
    // kept from the start, since the check afterwards empties the list
    property bool needsRestart: false

    // ── restarting after it: now, tonight, or when you say ──
    // a user timer (systemd-run --user): it survives bead restarts and logs
    // nothing in your files; a notification comes 5 minutes before
    property real rebootAt: 0           // ms since the epoch; 0: none scheduled
    readonly property string rebootLabel: rebootAt ? R.label(new Date(rebootAt), new Date(clock.now)) : ""
    QtObject { id: clock; property real now: Date.now() }
    Timer { interval: 30000; running: root.rebootAt > 0; repeat: true; onTriggered: clock.now = Date.now() }
    function rebootNow(): void { hide(); Quickshell.execDetached(["systemctl", "reboot"]); }
    function scheduleReboot(h: int, m: int): void {
        const t = R.next(h, m, new Date());
        const warn = new Date(t.getTime() - 5 * 60000);
        Quickshell.execDetached(["sh", "-c", `
            systemctl --user stop bead-reboot.timer bead-reboot-warn.timer 2>/dev/null
            systemd-run --user --quiet --unit=bead-reboot --on-calendar="$1" --timer-property=AccuracySec=1s systemctl reboot
            [ "$3" = yes ] && systemd-run --user --quiet --unit=bead-reboot-warn --on-calendar="$2" --timer-property=AccuracySec=1s \
                notify-send -a "System updates" -i system-reboot -u critical "Restarting in 5 minutes" "To finish the update. Save your work, or cancel it in the bar's updates button."
            exit 0`, "sh", R.calendar(t), R.calendar(warn), warn > new Date() ? "yes" : "no"]);
        rebootAt = t.getTime();
        clock.now = Date.now();
    }
    function cancelReboot(): void {
        Quickshell.execDetached(["systemctl", "--user", "stop", "bead-reboot.timer", "bead-reboot-warn.timer"]);
        rebootAt = 0;
    }
    // after a bead restart: is one still scheduled?
    Process {
        running: true
        command: ["systemctl", "--user", "list-timers", "--all", "-o", "json", "bead-reboot.timer"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const t = JSON.parse(text || "[]").find(x => x.unit === "bead-reboot.timer");
                    if (t && t.next) root.rebootAt = t.next / 1000;
                } catch (e) {}
            }
        }
    }

    function update(): void {
        if (running) { shown = true; return; }
        counts = { repo: repo.length, aur: aur.length, flatpak: flatpak.length };
        aurNames = items.filter(u => u.source === "aur").map(u => u.name);
        shown = true;
        if (aurNames.length) { phase = "review"; checkTrust(aurNames); }
        else start();
    }
    // withAur false: the repos and Flatpaks only (the review found an AUR update risky)
    function start(withAur = true): void {
        if (!withAur) counts = Object.assign({}, counts, { aur: 0 });
        stage = ""; current = ""; doing = ""; stepI = 0; stepN = 0;
        log = []; error = ""; failedStage = ""; updated = [];
        needsRestart = restart;
        job = null;
        runner.command = [Paths.cmd("bead-sysupdate"), ...["repo", "aur", "flatpak"].filter(s => (counts[s] || 0) > 0)];
        phase = "running";
        runner.running = true;
    }
    function cancel(): void { if (phase === "review" || phase === "done" || phase === "failed") { phase = ""; shown = false; } }
    function hide(): void { shown = false; if (phase === "done" || phase === "failed") { phase = ""; job = null; } }
    // the old way: paru (or yay, or pacman) in a terminal, where you answer everything
    function terminal(): void {
        phase = ""; shown = false;
        Quickshell.execDetached([Paths.cmd("bead-term"), "--title", "System update", "--", "sh", "-c",
            "if command -v paru >/dev/null; then paru; elif command -v yay >/dev/null; then yay; else sudo pacman -Syu; fi; "
            + "if command -v flatpak >/dev/null && [ -n \"$(flatpak remote-ls --updates --app 2>/dev/null)\" ]; then echo; echo ':: Flatpak'; flatpak update; fi; "
            + "echo; printf 'Done. Press Enter to close… '; read _"]);
        recheck.restart();
    }
    function aurLink(name: string): string { return "https://aur.archlinux.org/cgit/aur.git/log/?h=" + encodeURIComponent(name); }

    function line(l: string): void {
        if (job) {
            inst = S.installStep(inst, l);
            if (!l.startsWith("@@")) log = [...log, l].slice(-200);
            if (inst.error) error = inst.error;
            return;
        }
        if (l.startsWith("@@done")) return;
        if (l.startsWith("@@fail")) { failedStage = l.split(" ")[1] ?? ""; return; }
        const r = U.parse(l);
        if (r.kind === "stage") { stage = r.stage; current = ""; doing = ""; stepI = 0; stepN = 0; return; }
        if (!l.startsWith("@@")) log = [...log, l].slice(-200);
        if (r.kind === "step") {
            if (current && current !== r.name && doing !== "downloading") updated = [...updated, current].slice(-50);
            current = r.name; doing = r.verb;
            if (r.n > 0) { stepI = r.i; stepN = r.n; }
            else { stepI = stepI + 1; stepN = Math.max(stepI, counts[stage] || 1); }
        } else if (r.kind === "download") { current = r.name; doing = "downloading"; }
        else if (r.kind === "build") {
            if (current && current !== r.name) updated = [...updated, current].slice(-50);
            current = r.name; doing = "building"; stepI = stepI + 1; stepN = Math.max(stepI, counts.aur || 1);
        }
        else if (r.kind === "error") error = r.text || l;
    }
    Process {
        id: runner
        stdout: SplitParser { onRead: l => root.line(l) }
        onExited: code => {
            if (root.current) root.updated = [...root.updated, root.current].slice(-50);
            root.current = ""; root.doing = "";
            // done: stays up while a restart is wanted (it asks when); else it goes by itself
            if (code === 0) { root.phase = "done"; root.shown = true; if (!root.needsRestart) doneHide.restart(); if (root.job) root.appInstalled(root.job); }
            else {
                root.phase = "failed"; root.shown = true;
                if (!root.error) root.error = code === 126 || code === 127 ? "The password was cancelled" : "Stopped with code " + code;
            }
            root.check();
        }
    }
    Timer { id: doneHide; interval: root.job ? 9000 : 6000; onTriggered: if (root.phase === "done") root.hide() }

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
        function show(): void { if (root.phase) root.shown = true; }
        function terminal(): void { root.terminal(); }
        // restart at h:m (the next time it comes round), or cancel it
        function scheduleReboot(h: int, m: int): string { root.scheduleReboot(h, m); return root.rebootLabel; }
        function cancelReboot(): void { root.cancelReboot(); }
        function rebootStatus(): string { return root.rebootAt ? root.rebootLabel : "none"; }
        // the island's after-update view as if a restart were wanted (nothing runs)
        // the review as if these AUR packages had updates (checked for real; nothing runs)
        function cancel(): void { root.cancel(); }
        function previewReview(names: string): void { root.aurNames = names.split(/[ ,]+/).filter(Boolean); root.phase = "review"; root.shown = true; root.checkTrust(root.aurNames); }
        function previewDone(): void { root.needsRestart = true; root.updated = ["linux", "systemd", "glibc"]; root.phase = "done"; root.shown = true; }
        function status(): string { return root.checking ? "checking" : root.count + " (" + root.repo.length + " repo, " + root.aur.length + " aur, " + root.flatpak.length + " flatpak)"; }
        function list(): string { return root.items.map(u => u.source + "\t" + u.name + "\t" + u.from + " -> " + u.to + (u.restart ? "\trestart" : "")).join("\n"); }
    }
}
