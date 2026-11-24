pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Live activities: something running that the island shows as a small chip
// with a ring (its progress, or a spinner when there isn't one) until it ends,
// then says how it went. Anything can post one:
//   bead-activity "Build" -- make               (runs it, shows it, says done/failed)
//   qs -p ~/.local/share/bead ipc call activity set ID ICON LABEL PROGRESS
//        (PROGRESS 0-1, or -1 for a spinner; again to update)
//   qs ... ipc call activity done ID "text"   |   ... fail ID "text"   |   ... clear ID
// An activity nobody updates for 6 hours is dropped.
Singleton {
    id: root

    property list<var> items: []   // oldest first: { id, icon, label, progress, started, seen }
    property real now: Date.now()
    signal finished(var item, bool ok, string text)

    function set(id: string, icon: string, label: string, progress: real): void {
        if (!id) return;
        const old = items.find(i => i.id === id);
        const it = { id: id, icon: icon || old?.icon || "progress_activity", label: label || old?.label || id,
            progress: Number.isFinite(progress) ? Math.min(1, progress) : -1, started: old?.started ?? Date.now(), seen: Date.now() };
        items = old ? items.map(i => i.id === id ? it : i) : [...items, it];
    }
    function end(id: string, ok: bool, text: string): void {
        const it = items.find(i => i.id === id);
        if (!it) return;
        now = Date.now(); // the time taken, to the second
        items = items.filter(i => i.id !== id);
        finished(it, ok, text);
    }
    function elapsed(it: var): string {
        const s = Math.max(0, Math.round((now - it.started) / 1000));
        return s < 60 ? s + "s" : s < 3600 ? Math.floor(s / 60) + "m " + String(s % 60).padStart(2, "0") + "s" : Math.floor(s / 3600) + "h " + String(Math.floor(s / 60) % 60).padStart(2, "0") + "m";
    }

    // the clock for elapsed times, and the stale ones dropped
    Timer {
        running: root.items.length > 0
        interval: 1000
        repeat: true
        onTriggered: {
            root.now = Date.now();
            const stale = root.items.filter(i => root.now - i.seen > 6 * 3600 * 1000);
            if (stale.length) root.items = root.items.filter(i => !stale.includes(i));
        }
    }

    IpcHandler {
        target: "activity"
        function set(id: string, icon: string, label: string, progress: string): void { root.set(id, icon, label, progress === "" ? -1 : parseFloat(progress)); }
        function done(id: string, text: string): void { root.end(id, true, text); }
        function fail(id: string, text: string): void { root.end(id, false, text); }
        function clear(id: string): void { root.items = root.items.filter(i => i.id !== id); }
        function list(): string { return root.items.map(i => i.id + "\t" + i.label + "\t" + (i.progress < 0 ? "-" : Math.round(i.progress * 100) + "%")).join("\n"); }
    }
}
