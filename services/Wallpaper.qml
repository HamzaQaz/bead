pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Wallpapers: stills from ~/Pictures/Wallpapers (bead draws them, see
// modules/background) and live Wallpaper Engine items from Steam's workshop
// (played by ~/.local/bin/wallengine through linux-wallpaperengine). Picking
// either regenerates the colour scheme with `caelestia wallpaper -f`, which
// bead's Theme and the lock screen read. The choice is kept in
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

    function isCurrent(w: var): bool { return w.id ? kind === "live" && current === w.id : kind === "still" && current === w.path; }

    function setStill(path: string): void {
        kind = "still"; current = path; save();
        busy = true;
        run.command = ["sh", "-c", '"$1" stop; caelestia wallpaper -f "$2"', "sh", engine, path];
        run.running = true;
    }
    function setLive(id: string): void {
        kind = "live"; current = id; save();
        busy = true;
        // wallengine themes from the workshop preview; a still capture of the
        // live wallpaper (~/Pictures/Wallpapers/we-<id>-live.png) is better
        run.command = ["sh", "-c", '"$1" "$2"; f="$3/we-$2-live.png"; [ -f "$f" ] && caelestia wallpaper -f "$f"; exit 0', "sh", engine, id, stillDir];
        run.running = true;
    }
    function pick(w: var): void { if (w.id) setLive(w.id); else setStill(w.path); }
    function random(which: string): void {
        const pool = which === "live" ? lives : which === "still" ? stills : [...stills, ...lives];
        const others = pool.filter(w => !isCurrent(w));
        if (others.length) pick(others[Math.floor(Math.random() * others.length)]);
    }
    function refresh(): void { lister.running = true; }

    Process { id: run; onExited: root.busy = false }

    // list both kinds: "S\tpath" and "L\tid\ttype\tpreview\ttitle"
    Process {
        id: lister
        command: ["sh", "-c", `
            find "$1" -maxdepth 1 -type f \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \\) ! -name 'we-*' -printf 'S\\t%p\\n' | sort
            for d in "$2"/*/; do
                p=$(ls "$d"preview.* 2>/dev/null | head -1); [ -n "$p" ] && [ -f "$d"project.json ] || continue
                jq -r --arg id "$(basename "$d")" --arg p "$p" 'select(.type != null) | ["L", $id, (.type | ascii_downcase), $p, (.title // $id)] | @tsv' "$d"project.json 2>/dev/null
            done`, "sh", root.stillDir, root.workshop]
        stdout: StdioCollector {
            onStreamFinished: {
                const s = [], l = [];
                for (const line of text.split("\n")) {
                    const f = line.split("\t");
                    if (f[0] === "S" && f[1]) s.push({ path: f[1], name: f[1].split("/").pop().replace(/\.[^.]+$/, "").replace(/^od_/, "").replace(/[_-]+/g, " ") });
                    else if (f[0] === "L" && f.length >= 5) l.push({ id: f[1], type: f[2], preview: f[3], title: f.slice(4).join(" ") });
                }
                l.sort((a, b) => a.title.localeCompare(b.title));
                root.stills = s;
                root.lives = l;
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
        if (kind === "still") Quickshell.execDetached([engine, "stop"]);
        else Quickshell.execDetached(["sh", "-c", 'pgrep -x linux-wallpaper >/dev/null || exec "$1"', "sh", engine]);
        if (!kind) adopt.running = true;
    }
    Process {
        id: adopt
        command: ["cat", root.home + "/.local/state/wallengine-current"]
        stdout: StdioCollector { onStreamFinished: if (text.trim()) { root.kind = "live"; root.current = text.trim(); root.save(); } }
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
