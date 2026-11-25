pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.config

// bead's one view of windows and workspaces, per monitor (the bar, its title,
// the overview and the launcher all read it).
//
// Each monitor owns a group of ten workspaces: the main one 1–10, the
// others 11–20, 21–30… left to right (Settings.workspaceGroups; off, everything is one
// group as in plain Hyprland). Each bar shows its own group, numbered 1–10.
// `bead:ws1`…`bead:ws10` (and `bead:move1`…) act on the focused monitor's
// group; bind them in place of Hyprland's workspace keys:
//     hl.bind("SUPER + " .. i % 10, hl.dsp.global("bead:ws" .. i))
//
// Windows are read through each workspace's own list (HyprlandWorkspace
// .toplevels), never a binding on every window's .workspace: that crashes
// Quickshell 0.3.2 with Qt 6.12 (Qt::endPropertyUpdateGroup).
Singleton {
    id: root

    readonly property bool groups: Settings.workspaceGroups

    // ── monitors and their groups ──
    function pos(m: var): var { const o = m?.lastIpcObject ?? {}; return { x: o.x ?? 0, y: o.y ?? 0 }; }
    // the main monitor (Settings.home, where the island lives) owns 1–10; the
    // others follow left to right
    readonly property list<var> monitors: Hyprland.monitors.values.slice()
        .sort((a, b) => ((b.name === Settings.home) - (a.name === Settings.home)) || (pos(a).x - pos(b).x) || (pos(a).y - pos(b).y))
    function groupOf(m: var): int {
        if (!groups || !m) return 0;
        return Math.max(0, monitors.findIndex(x => x.name === m.name));
    }
    function base(m: var): int { return groupOf(m) * 10; }
    // what a workspace is called on its monitor's bar: 13 on the second → 3
    function label(id: int, m: var): string {
        const b = base(m);
        return id > b && id <= b + 10 ? String(id - b) : String(id);
    }
    readonly property var focusedMonitor: Hyprland.focusedMonitor

    // ── workspaces and their windows ──
    function workspace(id: int): var { return Hyprland.workspaces.values.find(w => w.id === id) ?? null; }
    // workspace id → its windows. A property, not only a function: a binding
    // elsewhere that calls into a singleton's function doesn't see what the
    // function read, so it would keep the empty list from before Hyprland loaded
    // (a workspace's list doesn't always say when a window joins it, e.g. the
    // ones Hyprland already had at startup: also follow the global list and a
    // tick after each refresh)
    property int rev: 0
    readonly property var byId: {
        rev; Hyprland.toplevels.values;
        const o = {};
        // copied: .values is a Qt list reference, empty when read later from elsewhere
        for (const w of Hyprland.workspaces.values) o[w.id] = Array.from(w.toplevels.values);
        return o;
    }
    function windowsOn(id: int): list<var> { return byId[id] ?? []; }
    function special(name: string): var { return Hyprland.workspaces.values.find(w => w.name === name) ?? null; }

    // a monitor's workspaces for its bar: its group's 1–5 always, the rest of
    // its group while in use, whatever else is on it (a stray from an unplugged
    // screen), and the one it shows. Everything comes in as arguments: a binding
    // doesn't see what a function it calls reads, so it wouldn't update.
    //   ids: Windows.barIds(Hyprland.workspaces.values, Windows.monitors, Windows.groups, monitor, activeId)
    function barIds(all: var, mons: var, grouped: bool, m: var, act: int): list<int> {
        const b = grouped && m ? Math.max(0, mons.findIndex(x => x.name === m.name)) * 10 : 0;
        const set = [b + 1, b + 2, b + 3, b + 4, b + 5];
        for (const w of all) {
            if (w.id <= 0 || set.includes(w.id)) continue;
            const mine = w.id > b && w.id <= b + 10;
            if (grouped ? (mine || w.monitor?.name === m?.name) : true) set.push(w.id);
        }
        if (act > 0 && !set.includes(act)) set.push(act);
        return set.sort((x, y) => x - y);
    }

    // ── the title each monitor shows: its focused window, else the last one
    // focused there while it's still on the workspace that monitor shows.
    // Worked out when something changes, not as a binding: reading
    // activeToplevel mid-update made the bar's title a binding loop ──
    property var lastOn: ({})   // monitor name → HyprlandToplevel
    property var titles: ({})   // monitor name → the window its bar titles
    function retitle(): void {
        // (activeToplevel is null after a restart until focus moves)
        const o = {}, t = Hyprland.activeToplevel ?? Hyprland.toplevels.values.find(x => x.activated) ?? null;
        for (const m of Hyprland.monitors.values) {
            const here = byId[m.activeWorkspace?.id ?? -1] ?? [];
            const last = lastOn[m.name];
            o[m.name] = t && here.includes(t) ? t : last && here.includes(last) ? last : here.find(x => !x.lastIpcObject?.hidden) ?? null;
        }
        titles = o;
    }
    Timer { id: retitler; interval: 0; onTriggered: root.retitle() }
    onByIdChanged: retitler.restart()
    Connections {
        target: Hyprland
        function onActiveToplevelChanged(): void {
            const t = Hyprland.activeToplevel, m = Hyprland.focusedMonitor;
            if (t && m) {
                const o = Object.assign({}, root.lastOn);
                o[m.name] = t;
                root.lastOn = o;
            }
            retitler.restart();
        }
        function onFocusedMonitorChanged(): void { retitler.restart(); }
    }

    // ── going places ──
    function dispatch(cmd: string): void { Hyprland.dispatch(cmd); }
    // workspace n (1–10) of the focused monitor's group: opened on, or brought
    // to, this monitor
    function go(n: int): void {
        const id = base(focusedMonitor) + Math.max(1, Math.min(10, n));
        dispatch(`hl.dsp.focus({ workspace = "${id}", on_current_monitor = true })`);
    }
    function goId(id: int): void {
        // one of this monitor's own: open it here; another monitor's: go there
        const m = focusedMonitor, b = base(m);
        const mine = !groups || (id > b && id <= b + 10);
        dispatch(`hl.dsp.focus({ workspace = "${Math.max(1, id)}"${mine ? ", on_current_monitor = true" : ""} })`);
    }
    function move(n: int): void {
        const id = base(focusedMonitor) + Math.max(1, Math.min(10, n));
        dispatch(`hl.dsp.window.move({ workspace = "${id}" })`);
    }
    // the next or previous workspace, staying in this monitor's group
    function step(dir: int, m: var): void {
        const mm = m ?? focusedMonitor, b = base(mm);
        const at = mm?.activeWorkspace?.id ?? b + 1;
        const to = groups ? Math.max(b + 1, Math.min(b + 10, at + dir)) : Math.max(1, at + dir);
        if (to !== at) goId(to);
    }

    // ── keeping window details fresh: app ids and positions aren't pushed ──
    Connections {
        target: Hyprland
        function onRawEvent(e: var): void {
            if (/^(openwindow|closewindow|movewindow|windowtitle|activewindow)/.test(e.name)) refresh.restart();
            if (/^(workspace|focusedmon)/.test(e.name)) retitler.restart();
            else if (/^(monitoradded|monitorremoved|moveworkspace|createworkspace|destroyworkspace)/.test(e.name)) monRefresh.restart();
        }
    }
    Timer { id: refresh; interval: 100; onTriggered: { Hyprland.refreshToplevels(); settle.restart(); } }
    Timer { id: settle; interval: 120; onTriggered: root.rev++ }
    Timer { id: monRefresh; interval: 150; onTriggered: { Hyprland.refreshMonitors(); Hyprland.refreshWorkspaces(); settle.restart(); } }
    Component.onCompleted: { Hyprland.refreshMonitors(); Hyprland.refreshToplevels(); settle.restart(); }

    // `bead:ws1`…`bead:ws10`, `bead:move1`…`bead:move10`, `bead:wsprev` / `bead:wsnext`
    Instantiator {
        model: 10
        delegate: QtObject {
            required property int index
            readonly property GlobalShortcut goKey: GlobalShortcut {
                appid: "bead"; name: "ws" + (index + 1)
                description: "Workspace " + (index + 1) + " on this monitor"
                onPressed: root.go(index + 1)
            }
            readonly property GlobalShortcut moveKey: GlobalShortcut {
                appid: "bead"; name: "move" + (index + 1)
                description: "Move the window to workspace " + (index + 1) + " on this monitor"
                onPressed: root.move(index + 1)
            }
        }
    }
    GlobalShortcut { appid: "bead"; name: "wsprev"; description: "The previous workspace on this monitor"; onPressed: root.step(-1, null) }
    GlobalShortcut { appid: "bead"; name: "wsnext"; description: "The next workspace on this monitor"; onPressed: root.step(1, null) }
}
