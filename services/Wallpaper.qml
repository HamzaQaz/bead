pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Wallpapers: bead's own still, stills from ~/Pictures/Wallpapers (bead draws them, see
// modules/background) and live Wallpaper Engine items from Steam's workshop
// (played by ~/.local/bin/wallengine through linux-wallpaperengine). Picking
// either rebuilds the colours with Tint (bin/bead-tint), which bead's Theme
// reads; Tint also records the wallpaper's still (stillPath) for the lock
// screen and the overview. The choice is kept in
// $XDG_STATE_HOME/bead/wallpaper.json and restored when bead starts.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string stillDir: (Quickshell.env("XDG_PICTURES_DIR") || home + "/Pictures") + "/Wallpapers"
    readonly property string workshop: home + "/.local/share/Steam/steamapps/workshop/content/431960"
    readonly property string engine: home + "/.local/bin/wallengine"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/bead"

    property string kind: ""      // "still" | "live"
    property string current: ""   // a still's path, or a workshop id
    property list<var> stills: []  // { path, name }
    property list<var> lives: []   // { id, title, type, preview }
    property bool busy: false

    // the wallpaper as a still image: Tint's record of it
    readonly property string stillPath: tintPath
    property string tintPath: ""
    FileView {
        path: root.stateDir + "/wallpaper-path"
        watchChanges: true
        printErrors: false
        onLoaded: root.tintPath = text().trim()
        onFileChanged: reload()
        onLoadFailed: root.tintPath = ""
    }

    // ── Tint ──
    readonly property string tintBin: Paths.cmd("bead-tint")
    // a live wallpaper: its captured still if there is one, else the workshop preview
    function tintLive(id: string): string {
        return `f="$3/we-$2-live.png"; [ -f "$f" ] || f="$4"; [ -n "$f" ] && "$5" --variant "$6" "$f"`;
    }
    function retint(): void {
        if (kind === "still" && current) start(["sh", "-c", '"$1" --variant "$2" "$3"', "sh", tintBin, Settings.tint, current]);
        else if (kind === "live" && current)
            start(["sh", "-c", tintLive(current) + "; exit 0", "sh", "", current, stillDir, lives.find(x => x.id === current)?.preview ?? "", tintBin, Settings.tint]);
    }
    Connections { target: Settings; function onTintChanged(): void { root.retint(); } }

    // a file:// URL that survives #, ?, % and spaces in names
    function url(path: string): string { return path ? "file://" + path.split("/").map(encodeURIComponent).join("/") : ""; }

    function isCurrent(w: var): bool { return w.id ? kind === "live" && current === w.id : kind === "still" && current === w.path; }

    function setStill(path: string): void {
        kind = "still"; current = path; save();
        start(["sh", "-c", '[ -x "$1" ] && "$1" stop; "$3" --variant "$4" "$2"', "sh", engine, path, tintBin, Settings.tint]);
    }
    function setLive(id: string): void {
        kind = "live"; current = id; save();
        // wallengine themes from the workshop preview; a still capture of the
        // live wallpaper (~/Pictures/Wallpapers/we-<id>-live.png) is better
        start(["sh", "-c", '"$1" "$2"; ' + tintLive(id) + '; exit 0', "sh", engine, id, stillDir, lives.find(x => x.id === id)?.preview ?? "", tintBin, Settings.tint]);
    }
    function pick(w: var): void { if (w.id) setLive(w.id); else setStill(w.path); }
    function random(which: string): void {
        const pool = which === "live" ? lives : which === "still" ? stills : [...stills, ...lives];
        const others = pool.filter(w => !isCurrent(w));
        if (others.length) pick(others[Math.floor(Math.random() * others.length)]);
    }
    function refresh(): void { lister.running = true; }
    readonly property list<string> beads: ["bead", "solo", "dusk", "tide", "ember", "mono"]
    readonly property var own: stills.filter(w => !w.bead)   // the user's, not bead's

    // one switch at a time; a pick made meanwhile runs next (the latest wins)
    property var pending: null
    function start(cmd: var): void {
        if (run.running) { pending = cmd; return; }
        busy = true;
        run.command = cmd;
        run.running = true;
    }
    Process {
        id: run
        onExited: {
            if (root.pending) { const c = root.pending; root.pending = null; root.busy = false; root.start(c); }
            else root.busy = false;
        }
    }

    // list both kinds: "S\tpath" and "L\tid\ttype\tpreview\ttitle"
    Process {
        id: lister
        command: ["sh", "-c", `
            find "$1" -maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) ! -name 'we-*' -printf 'S\\t%p\\n' | sort
            [ -x "$3" ] || exit 0 # live wallpapers need the engine
            for d in "$2"/*/; do
                p=$(ls "$d"preview.* 2>/dev/null | head -1); [ -n "$p" ] && [ -f "$d"project.json ] || continue
                jq -r --arg id "$(basename "$d")" --arg p "$p" 'select(.type != null) | ["L", $id, (.type | ascii_downcase), $p, (.title // $id)] | @tsv' "$d"project.json 2>/dev/null
            done`, "sh", root.stillDir, root.workshop, root.engine]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = [], l = [];
                for (const line of text.split("\n")) {
                    const f = line.split("\t");
                    if (f[0] === "S" && f[1]) s.push({ path: f[1], name: f[1].split("/").pop().replace(/\.[^.]+$/, "").replace(/^od_/, "").replace(/[_-]+/g, " ") });
                    else if (f[0] === "L" && f.length >= 5) l.push({ id: f[1], type: f[2], preview: f[3], title: f.slice(4).join(" ") });
                }
                l.sort((a, b) => a.title.localeCompare(b.title));
                // bead's own (data/wallpapers, from tools/make-wallpaper.py) come
                // first, so a first run with no wallpapers of its own starts on them
                root.stills = [...root.beads.map(n => ({ path: Quickshell.shellPath("data/wallpapers/" + n + ".jpg"), name: n, bead: true })), ...s];
                root.lives = l;
                root.firstPick();
            }
        }
    }

    // ── remembered choice ──
    FileView {
        id: state
        path: root.stateDir + "/wallpaper.json"
        blockLoading: true
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try { const j = JSON.parse(text()); root.kind = j.kind || ""; root.current = j.current || ""; } catch (e) {}
            root.restore();
        }
        onLoadFailed: root.restore()
    }
    function save(): void { state.setText(JSON.stringify({ kind, current })); }

    // at start: a still means no player; live means make sure it's playing.
    // With nothing saved yet, adopt whatever wallengine last played.
    function restore(): void {
        if (kind === "still") Quickshell.execDetached(["sh", "-c", '[ -x "$1" ] && exec "$1" stop', "sh", engine]);
        else if (kind === "live") Quickshell.execDetached(["sh", "-c", '[ -x "$1" ] && ! pgrep -x linux-wallpaper >/dev/null && exec "$1"', "sh", engine]);
        if (!kind) adopt.running = true;
        firstTint.restart();
    }
    // no Tint colours yet (a first run): make them
    Timer { id: firstTint; interval: 3000; onTriggered: if (!root.tintPath) root.retint() }
    Process {
        id: adopt
        command: ["cat", root.home + "/.local/state/wallengine-current"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim()) { root.kind = "live"; root.current = text.trim(); root.save(); }
                else root.firstPick();
            }
        }
    }
    // a first run with nothing to adopt: start on the first still there is
    function firstPick(): void {
        if (!kind && !adopt.running && stills.length) setStill(stills[0].path);
    }

    Component.onCompleted: { Quickshell.execDetached(["mkdir", "-p", stateDir]); refresh(); }

    // `qs ipc call wallpaper still PATH | live ID | random [still|live] | current`
    IpcHandler {
        target: "wallpaper"
        function still(path: string): void { root.setStill(path); }
        function live(id: string): void { root.setLive(id); }
        function random(which: string): void { root.random(which); }
        function current(): string { return root.kind + " " + root.current; }
    }
}
