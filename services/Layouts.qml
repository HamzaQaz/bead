pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// Workspace layouts: "save this layout as coding", later "set up coding".
// A layout is which apps were on which workspaces (special ones left out), kept
// in ~/.config/bead/layouts.json. Setting one up moves windows of those apps
// that are already open onto their workspaces and opens the missing ones there;
// nothing else is closed. Where a window sits inside its workspace is up to
// Hyprland's tiling, as when you open it yourself.
Singleton {
    id: root

    property var layouts: ({})       // name -> { saved: ms, windows: [{ cls, ws, title }] }
    readonly property list<string> names: Object.keys(layouts).sort()

    function key(name: string): string { return String(name).toLowerCase().replace(/[^a-z0-9 ]+/g, " ").replace(/\b(layout|the|my|setup|set up)\b/g, " ").replace(/\s+/g, " ").trim(); }
    // the saved layout nearest to what was said
    function find(name: string): string {
        const k = key(name);
        if (!k) return "";
        if (layouts[k]) return k;
        let best = "", score = 0;
        for (const n of names) {
            const v = n.includes(k) || k.includes(n) ? 0.9 : Apps.similar(k.replace(/ /g, ""), n.replace(/ /g, ""));
            if (v > score) { score = v; best = n; }
        }
        return score >= 0.6 ? best : "";
    }

    // save what's open now; then(name, windows, workspaces)
    function save(name: string, then: var): void {
        const k = key(name);
        if (!k) return;
        saver.name = k;
        saver.then = then;
        saver.running = true;
    }
    Process {
        id: saver
        property string name
        property var then: null
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try { list = JSON.parse(text); } catch (e) { return; }
                const wins = list.filter(c => c.mapped && !c.hidden && c.workspace?.id > 0 && c.class)
                    .sort((a, b) => a.workspace.id - b.workspace.id || a.at[0] - b.at[0] || a.at[1] - b.at[1])
                    .map(c => ({ cls: c.class, ws: c.workspace.id, title: c.title }));
                root.layouts = Object.assign({}, root.layouts, { [saver.name]: { saved: Date.now(), windows: wins } });
                file.setText(JSON.stringify(root.layouts, null, 2) + "\n");
                if (saver.then) saver.then(saver.name, wins.length, [...new Set(wins.map(w => w.ws))]);
            }
        }
    }

    // set one back as it was (null: remove it)
    function put(name: string, value: var): void {
        const l = Object.assign({}, layouts);
        if (value) l[name] = value; else delete l[name];
        layouts = l;
        file.setText(JSON.stringify(layouts, null, 2) + "\n");
    }

    // what setting it up would do: { moves: [{ t, ws, from }], opens: [{ e, ws }], unknown: [cls] }
    function plan(name: string): var {
        const l = layouts[name];
        if (!l) return null;
        const taken = new Set(), out = { moves: [], opens: [], unknown: [] };
        const cls = t => String(t.wayland?.appId ?? t.lastIpcObject?.class ?? "").toLowerCase();
        for (const w of l.windows) {
            const want = w.cls.toLowerCase();
            // the same app: one already on that workspace first, then any other
            const all = Hyprland.toplevels.values.filter(t => cls(t) === want && !taken.has(t) && (t.workspace?.id ?? 0) > 0);
            const t = all.find(x => x.workspace?.id === w.ws) ?? all[0];
            if (t) {
                taken.add(t);
                if (t.workspace?.id !== w.ws) out.moves.push({ t: t, ws: w.ws, from: t.workspace?.name ?? "" });
                continue;
            }
            const e = Apps.entryFor(w.cls);
            if (e) out.opens.push({ e: e, ws: w.ws, cls: w.cls });
            else out.unknown.push(w.cls);
        }
        return out;
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/bead/layouts.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.layouts = JSON.parse(text()) ?? {}; } catch (e) { console.warn("layouts.json isn't valid JSON:", e.message); } }
    }
}
