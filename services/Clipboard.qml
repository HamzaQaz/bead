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

    // each: { id, line (as cliphist printed it), text, image: { fmt, w, h } | null,
    //         type: image | secret | colour | link | path | command | code | number | text }
    property list<var> entries: []
    property bool loading: false
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/bead/clip"

    // Opening `;` shows what's already here at once and refreshes quietly behind
    // it (cliphist is quick, but only an unchanged list skips the redraw).
    // "Loading…" only shows on the very first load.
    function load(): void {
        if (!entries.length) loading = true;
        if (!lister.running) lister.running = true;
    }
    Component.onCompleted: load() // warm at startup

    Process {
        id: lister
        command: ["cliphist", "list", "-preview-width", "400"] // longer previews: search sees more
        onExited: root.loading = false   // even if it failed
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0) continue;
                    const id = line.slice(0, tab), body = line.slice(tab + 1);
                    const m = /^\[\[ binary data .* (png|jpe?g|webp|gif|bmp) (\d+)x(\d+) \]\]$/.exec(body);
                    if (m && (+m[2] < 8 || +m[3] < 8)) continue; // 2×1 slivers browsers copy along with text
                    const image = m ? { fmt: m[1], w: +m[2], h: +m[3] } : null;
                    out.push({ id, line, text: m ? "" : body, image, type: image ? "image" : root.typeOf(body) });
                }
                // skip the redraw when nothing changed
                if (out.map(e => e.line).join("\n") !== root.entries.map(e => e.line).join("\n")) root.entries = out;
                root.loading = false;
                // forget thumbnails of entries no longer in the history
                const keep = out.filter(e => e.image).map(e => e.id).join(" ");
                Quickshell.execDetached(["sh", "-c", 'cd "$1" 2>/dev/null || exit 0; for f in *; do [ -e "$f" ] || continue; case " $2 " in *" ${f%.*} "*) ;; *) rm -f -- "$f" ;; esac; done', "sh", root.cacheDir, keep]);
            }
        }
    }

    function typeOf(t: string): string {
        const s = t.trim();
        if (root.looksSecret(s)) return "secret";
        if (/^(#([0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})|(rgb|hsl)a?\([\d\s.,%\/deg]+\))$/i.test(s)) return "colour";
        if (/^(https?|ftp|file):\/\/\S+$/i.test(s) || /^www\.\S+\.\S+$/i.test(s)) return "link";
        if (/^(~|\/)[^\s]*$/.test(s) && s.length > 1) return "path";
        if (/^-?[\d\s.,_]+$/.test(s)) return "number";
        if (/^(sudo|git|cd|ls|paru|pacman|yay|npm|pnpm|bun|cargo|make|systemctl|journalctl|hyprctl|qs|bead|cp|mv|rm|mkdir|curl|wget|ssh|docker|python3?|chmod|echo|cat|grep|sed|jq|kill|pkill|tar|uv|pip)\s/.test(s) || / (&&|\|\|) /.test(s)) return "command";
        if (/[{};]\s*$|=>|\bfunction\b|\bconst |\bimport |\bdef |<\/?[a-z]+[ >]/.test(s)) return "code";
        return "text";
    }
    // API keys, tokens, client secrets: one long random-looking word. Shown
    // hidden (still pasteable), so they don't sit in plain sight in the picker.
    function looksSecret(s: string): bool {
        if (/\s/.test(s) || s.length < 20 || s.length > 400) return false;
        if (/^(ghp_|gho_|ghs_|github_pat_|glpat-|sk-|sk_live_|rk_live_|pk_live_|xox[abprs]-|AKIA|AIza|eyJ[\w-]+\.)/.test(s)) return true;
        if (/^[a-z]+:\/\/|[\/~]/.test(s)) return false;        // links and paths
        return /[a-z]/.test(s) && /[A-Z]/.test(s) && /\d/.test(s) // mixed like a random token
            && !/^[A-Za-z]+[A-Z][a-z]+\d*$/.test(s);            // not a CamelCase word
    }
    // a CSS-ish colour string, for the swatch
    function colourOf(t: string): string {
        const s = t.trim();
        if (s.startsWith("#") && (s.length === 5 || s.length === 9)) // #rgba / #rrggbbaa -> Qt's #aarrggbb
            return s.length === 5 ? "#" + s[4] + s.slice(1, 4) : "#" + s.slice(7) + s.slice(1, 7);
        return s;
    }

    // the whole text of an entry (the list only has a 400-character preview)
    property var full: ({}) // id -> text
    function loadFull(e: var): void {
        if (!e || e.image || full[e.id] !== undefined) return;
        const p = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector {} }', root);
        p.command = ["sh", "-c", 'printf "%s\\n" "$1" | cliphist decode | head -c 20000', "sh", e.line];
        p.stdout.streamFinished.connect(() => {
            root.full = Object.assign({}, root.full, { [e.id]: p.stdout.text });
            Qt.callLater(() => p.destroy());
        });
        p.running = true;
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
