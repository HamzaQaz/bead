pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Clipboard history (cliphist, fed by wl-paste --watch). `load()` reads the
// list; pick() copies an entry back and pastes it into the window you were
// in (wtype; Ctrl+Shift+V in terminals); remove() deletes it. Images get a
// cached thumbnail in ~/.cache/bead/clip.
Singleton {
    id: root

    // each: { id, line (as cliphist printed it), text, image: { fmt, w, h } | null }
    property list<var> entries: []
    property bool loading: false
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/bead/clip"

    function load(): void { loading = true; lister.running = true; }

    Process {
        id: lister
        command: ["cliphist", "list"]
        onExited: root.loading = false   // even if it failed
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0) continue;
                    const id = line.slice(0, tab), body = line.slice(tab + 1);
                    const m = /^\[\[ binary data .* (png|jpe?g|webp|gif|bmp) (\d+)x(\d+) \]\]$/.exec(body);
                    out.push({ id, line, text: m ? "" : body, image: m ? { fmt: m[1], w: +m[2], h: +m[3] } : null });
                }
                root.entries = out;
                root.loading = false;
                // forget thumbnails of entries no longer in the history
                const keep = out.filter(e => e.image).map(e => e.id).join(" ");
                Quickshell.execDetached(["sh", "-c", 'cd "$1" 2>/dev/null || exit 0; for f in *; do [ -e "$f" ] || continue; case " $2 " in *" ${f%.*} "*) ;; *) rm -f -- "$f" ;; esac; done', "sh", root.cacheDir, keep]);
            }
        }
    }

    function thumbPath(e: var): string { return `${cacheDir}/${e.id}.${e.image?.fmt ?? "png"}`; }
    // write the image to the cache (once); `done` runs when it's there
    // entry id -> thumbnail URL, once it's on disk (rows bind to this, so a
    // row that's gone by then is simply not around to care)
    property var thumbs: ({})
    function ensureThumb(e: var): void {
        if (thumbs[e.id]) return;
        const p = Qt.createQmlObject('import Quickshell.Io; Process {}', root);
        const path = thumbPath(e);
        p.command = ["sh", "-c", 'mkdir -p "$1"; [ -s "$2" ] || printf "%s\\n" "$3" | cliphist decode > "$2"', "sh", cacheDir, path, e.line];
        p.exited.connect(() => {
            root.thumbs = Object.assign({}, root.thumbs, { [e.id]: "file://" + path });
            p.destroy();
        });
        p.running = true;
    }

    // copy it back, and paste unless copyOnly
    function pick(e: var, copyOnly: bool): void {
        Quickshell.execDetached(["sh", "-c", `
            printf '%s\\n' "$1" | cliphist decode | wl-copy
            [ "$2" = copy ] && exit 0
            sleep 0.25
            cls=$(hyprctl activewindow -j | sed -n 's/.*"class": "\\([^"]*\\)".*/\\1/p' | head -1)
            case $cls in
            *kitty*|*foot*|*alacritty*|*wezterm*|*ghostty*|*konsole*|*terminal*|*Terminal*) wtype -M ctrl -M shift -k v -m shift -m ctrl ;;
            *) wtype -M ctrl -k v -m ctrl ;;
            esac`, "sh", e.line, copyOnly ? "copy" : "paste"]);
    }
    function remove(e: var): void {
        Quickshell.execDetached(["sh", "-c", 'printf "%s\\n" "$1" | cliphist delete', "sh", e.line]);
        entries = entries.filter(x => x.id !== e.id);
    }
}
