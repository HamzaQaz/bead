pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Emoji and symbols (data/emojis.txt, from Caelestia's CLI: "<char> <words>").
// search() matches every typed word against the names; type() types the
// character into the window you were in (wtype), or copies it.
Singleton {
    id: root

    property list<var> all: []   // { c, name }
    FileView {
        path: Quickshell.shellPath("data/emojis.txt")
        onLoaded: {
            const out = [];
            for (const line of text().split("\n")) {
                const sp = line.indexOf(" ");
                if (sp > 0) out.push({ c: line.slice(0, sp), name: line.slice(sp + 1) });
            }
            root.all = out;
        }
    }

    function search(q: string): list<var> {
        const words = q.toLowerCase().split(/\s+/).filter(w => w);
        if (!words.length) return all.slice(0, 60);
        const out = [];
        for (const e of all) {
            const n = e.name.toLowerCase();
            if (!words.every(w => n.includes(w))) continue;
            // whole-word and leading matches first
            const s = words.reduce((acc, w) => acc + (new RegExp("(^|\\s)" + w.replace(/[^a-z0-9]/g, "")).test(n) ? 2 : 1), 0);
            out.push({ e, s });
            if (out.length > 400) break;
        }
        return out.sort((a, b) => b.s - a.s).slice(0, 60).map(x => x.e);
    }

    function type(e: var, copyOnly: bool): void {
        if (copyOnly) Quickshell.execDetached(["wl-copy", e.c]);
        else Quickshell.execDetached(["sh", "-c", 'printf %s "$1" | wl-copy; sleep 0.25; wtype -- "$1"', "sh", e.c]);
    }
}
