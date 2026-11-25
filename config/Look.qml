pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "look.js" as L

// Customisation: the options in look.js, kept in ~/.config/bead/look.json
// (only what differs from the defaults, plus saved presets). `v` is every
// option, checked; panels bind to it (Look.v.islandRadius) and follow live.
// Settings → Customise draws its pages from the same list.
Singleton {
    id: root

    property var v: L.load({})
    property var presets: ({})          // saved: name → changes
    // "Try it" in Settings: the island and the pop-ups show the real thing
    // (volume | notif | toast | dashboard | popup | popups)
    signal tryIt(string what)
    function sample(i: int): var {
        const s = [["A sample pop-up", "This is how notifications look with your settings."],
                   ["Another one", "Stacked under the first, melting into it."], ["And a third", "Older ones shrink to their icon."]][i % 3];
        // each from its own app, so a stack stays a stack (one app's would combine)
        return { key: Date.now() * 1000 + i, time: Date.now(), appName: ["bead", "bead · preview", "bead · sample"][i % 3], summary: s[0], body: s[1], appIcon: "", image: "", urgency: 1, actions: [] };
    }
    readonly property string active: L.matching(v, presets)   // the preset these values are ("" none)

    function set(k: string, x: var): void { v = L.set(v, k, x); save(); }
    function resetPage(page: string): void { v = L.resetPage(v, page); save(); }
    function resetAll(): void { v = L.load({}); save(); }
    function apply(id: string): bool {
        const p = L.preset(id, presets);
        if (!p) return false;
        v = p; save(); return true;
    }
    function savePreset(name: string): string {
        name = (name || "").trim().slice(0, 40);
        if (!name) return "Name it first";
        if (L.PRESETS.some(p => p.id === name.toLowerCase() || p.name === name)) return "That's a built-in preset's name";
        const p = Object.assign({}, presets); p[name] = L.diff(v); presets = p; save();
        return "";
    }
    function deletePreset(name: string): void { const p = Object.assign({}, presets); delete p[name]; presets = p; save(); }

    // ── sharing: as text (the clipboard) or a file ──
    function exportText(name: string): string { return L.exportText(v, name || active || "My look"); }
    function copyLook(name: string): void { Quickshell.execDetached(["wl-copy", "--", exportText(name)]); }
    readonly property string exportDir: Quickshell.env("HOME") + "/Documents"
    function exportFile(name: string): string {
        const n = (name || active || "my-look").replace(/[^A-Za-z0-9_-]+/g, "-").toLowerCase();
        const path = exportDir + "/bead-look-" + n + ".json";
        writer.path = path; writer.setText(exportText(name));
        return path;
    }
    FileView { id: writer; printErrors: false; atomicWrites: true }
    // a look someone shared: as its own preset, and applied
    signal imported(string name, string error)
    function importText(text: string): void {
        const r = L.importText(text);
        if (!r.ok) { imported("", r.error); return; }
        let name = r.name, i = 2;
        while (presets[name] || L.PRESETS.some(p => p.name === name)) name = r.name + " " + i++;
        const p = Object.assign({}, presets); p[name] = L.diff(r.values); presets = p;
        v = r.values; save();
        imported(name, "");
    }
    function importClipboard(): void { paster.running = true; }
    Process { id: paster; command: ["wl-paste", "--no-newline"]; stdout: StdioCollector { onStreamFinished: root.importText(text) } }

    // ── the file ──
    property bool loaded: false
    function save(): void { if (loaded) saveTimer.restart(); }
    Timer { id: saveTimer; interval: 250; onTriggered: file.setText(JSON.stringify({ values: L.diff(root.v), presets: root.presets }, null, 2)) }
    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/bead/look.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const o = JSON.parse(text());
                const next = L.load(o.values ?? {});
                if (JSON.stringify(next) !== JSON.stringify(root.v)) root.v = next;
                const ps = {};
                for (const k in o.presets ?? {}) if (k && typeof o.presets[k] === "object") ps[k] = L.diff(L.load(o.presets[k]));
                root.presets = ps;
            } catch (e) {}
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true
    }

    IpcHandler {
        target: "look"
        function get(k: string): string { return JSON.stringify(k ? root.v[k] : L.diff(root.v)); }
        // a value as JSON: look set islandRadius 12, look set popScreen '"focused"'
        function set(k: string, json: string): string {
            if (!L.entry(k)) return "no such option";
            let x; try { x = JSON.parse(json); } catch (e) { x = json; }
            root.set(k, x); return JSON.stringify(root.v[k]);
        }
        function preset(id: string): string { return root.apply(id) ? "applied" : "no such preset"; }
        function reset(page: string): void { page ? root.resetPage(page) : root.resetAll(); }
        function presets(): string { return [...L.PRESETS.map(p => p.id), ...Object.keys(root.presets)].join("\n"); }
        function active(): string { return root.active; }
        // the Customise previews' buttons: rest | notif | volume | toast | media | dashboard | popup | popups
        function demo(what: string): void { root.tryIt(what); }
        function exportLook(name: string): string { return root.exportText(name); }
    }
}
