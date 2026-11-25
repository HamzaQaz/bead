pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.config
import "focus.js" as F
import "../config/look.js" as L

// Focus modes (focus.js): Work, Game, Night and your own. A mode makes its
// changes together (a look preset, Do Not Disturb with some apps let through,
// night light, a wallpaper) and leaving it puts back exactly what was there
// before. It turns on by hand (Settings, the launcher, the island, IPC), on
// its schedule, or while one of its apps is open; your own choice holds until
// the automatic answer changes (focus.js resolve).
//
// The modes: ~/.config/bead/focus.json. What's on, and what to put back:
// $XDG_STATE_HOME/bead/focus.json (a restart keeps both).
Singleton {
    id: root

    property var modes: F.cleanAll(F.DEFAULTS)
    property string active: ""          // the mode on now ("" none)
    property var manual: null           // your choice: an id, "off", or null
    property string lastAuto: ""
    property string reason: ""          // why it's on: "you" | "schedule" | "app"
    property var saved: null            // what it changed, as it was before
    readonly property var mode: modes.find(m => m.id === active) ?? null
    signal switched(string from, string to)

    // ── turning modes on and off ──
    function on(id: string): bool {
        if (!modes.some(m => m.id === id)) return false;
        manual = id; evaluate(); return true;
    }
    function off(): void { manual = "off"; evaluate(); }
    function toggle(id: string): void { if (active === id) off(); else on(id); }

    // window classes now (for modes that come on with an app)
    readonly property var classes: Hyprland.toplevels.values.map(t => String(t.wayland?.appId || t.lastIpcObject?.class || "")).filter(Boolean)
    onClassesChanged: soon.restart()
    Timer { id: soon; interval: 800; onTriggered: root.evaluate() }
    Timer { interval: 30000; repeat: true; running: root.loaded; onTriggered: root.evaluate() }   // schedules

    function evaluate(): void {
        if (!loaded) return;
        const autoNow = F.auto(modes, new Date(), classes);
        const r = F.resolve({ manual: manual, lastAuto: lastAuto }, autoNow);
        manual = r.manual; lastAuto = r.lastAuto;
        const why = r.manual !== null ? "you" : !r.active ? "" : modes.find(m => m.id === r.active)?.apps.length && F.appMatches(modes.find(m => m.id === r.active).apps, classes) ? "app" : "schedule";
        if (r.active !== active) apply(r.active, why);
        else if (reason !== why && active) reason = why;
        saveState();
    }

    // leave the mode that's on (put back what it changed), then make the new one's changes
    function apply(id: string, why: string): void {
        const from = active;
        if (saved) restore(saved);
        saved = null;
        active = id; reason = id ? why : "";
        const m = mode;
        if (m) {
            saved = { look: Look.v, dnd: Notifs.dnd, nightLight: Settings.nightLight, wallpaper: { kind: Wallpaper.kind, current: Wallpaper.current } };
            if (m.preset) Look.apply(m.preset);
            if (m.dnd) Notifs.dnd = true;
            if (m.nightLight) Settings.nightLight = m.nightLight;
            if (m.wallpaper?.id) Wallpaper.setLive(m.wallpaper.id);
            else if (m.wallpaper?.path) Wallpaper.setStill(m.wallpaper.path);
        }
        saveState();
        switched(from, id);
    }
    function restore(s: var): void {
        if (s.look) { Look.v = L.load(s.look); Look.save(); }
        if (s.dnd !== undefined) Notifs.dnd = s.dnd;
        if (s.nightLight !== undefined) Settings.nightLight = s.nightLight;
        const w = s.wallpaper;
        if (w && w.current && !(w.kind === Wallpaper.kind && w.current === Wallpaper.current)) {
            if (w.kind === "live") Wallpaper.setLive(w.current); else Wallpaper.setStill(w.current);
        }
    }
    // a notification while Do Not Disturb is on: this mode lets it through?
    function letsThrough(app: string): bool { return F.letsThrough(mode, app); }

    // ── editing modes (Settings) ──
    function update(id: string, changes: var): void {
        modes = modes.map(m => m.id === id ? F.clean(Object.assign({}, m, changes)) ?? m : m);
        saveModes();
        // the one that's on changed: make its changes again
        if (id === active) { const keep = saved; saved = null; if (keep) restore(keep); active = ""; apply(id, reason || "you"); }
        evaluate();
    }
    function add(name: string): string {
        const id = F.newId(name, modes);
        modes = [...modes, F.clean({ id: id, name: (name || "New mode").trim() || "New mode", icon: "self_improvement" })];
        saveModes();
        return id;
    }
    function duplicate(id: string): string {
        const m = modes.find(x => x.id === id);
        if (!m) return "";
        const name = m.name + " copy", nid = F.newId(name, modes);
        const i = modes.indexOf(m);
        modes = [...modes.slice(0, i + 1), F.clean(Object.assign({}, m, { id: nid, name: name, schedule: Object.assign({}, m.schedule, { on: false }) })), ...modes.slice(i + 1)];
        saveModes();
        return nid;
    }
    function remove(id: string): void {
        if (active === id) { manual = null; apply("", ""); }
        modes = modes.filter(m => m.id !== id);
        saveModes();
        evaluate();
    }
    function restoreDefaults(): void { if (active) apply("", ""); manual = null; modes = F.cleanAll(F.DEFAULTS); saveModes(); evaluate(); }
    function summary(m: var): string { const n = {}; for (const p of L.PRESETS) n[p.id] = p.name; for (const k in Look.presets) n[k] = k; return F.summary(m, n); }
    function when(m: var): string { return F.when(m); }

    // ── files ──
    property bool loaded: false
    property bool modesLoaded: false
    property bool stateLoaded: false
    onModesLoadedChanged: loaded = modesLoaded && stateLoaded
    onStateLoadedChanged: loaded = modesLoaded && stateLoaded
    onLoadedChanged: if (loaded) evaluate()
    function saveModes(): void { if (loaded) modesFile.setText(JSON.stringify({ modes: modes }, null, 2)); }
    function saveState(): void { if (loaded) stateSave.restart(); }
    Timer { id: stateSave; interval: 200; onTriggered: stateFile.setText(JSON.stringify({ active: root.active, manual: root.manual, lastAuto: root.lastAuto, reason: root.reason, saved: root.saved })) }
    FileView {
        id: modesFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/bead/focus.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: { try { const m = F.cleanAll(JSON.parse(text()).modes); if (m.length || root.modesLoaded) root.modes = m; } catch (e) {} root.modesLoaded = true; }
        onLoadFailed: root.modesLoaded = true
    }
    FileView {
        id: stateFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/bead/focus.json"
        blockLoading: true
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                const o = JSON.parse(text());
                root.active = typeof o.active === "string" ? o.active : "";
                root.manual = typeof o.manual === "string" ? o.manual : null;
                root.lastAuto = typeof o.lastAuto === "string" ? o.lastAuto : "";
                root.reason = typeof o.reason === "string" ? o.reason : "";
                root.saved = o.saved && typeof o.saved === "object" ? o.saved : null;
            } catch (e) {}
            root.stateLoaded = true;
        }
        onLoadFailed: root.stateLoaded = true
    }

    IpcHandler {
        target: "focus"
        // "id<TAB>name<TAB>on|-<TAB>what it does"
        function list(): string { return root.modes.map(m => m.id + "\t" + m.name + "\t" + (m.id === root.active ? "on" : "-") + "\t" + root.summary(m)).join("\n"); }
        function on(id: string): string { return root.on(id) ? "on" : "no such mode"; }
        function off(): void { root.off(); }
        function toggle(id: string): void { root.toggle(id); }
        function status(): string { return root.active ? root.active + " (" + root.reason + ")" : "off"; }
        // what a mode touches, now: to check it put things back
        function state(): string { return JSON.stringify({ active: root.active, dnd: Notifs.dnd, nightLight: Settings.nightLight, look: Look.active, wallpaper: Wallpaper.current }); }
    }
}
