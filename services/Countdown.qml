pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Timers and a stopwatch. Several timers can run at once, plus one stopwatch
// (with laps); each can pause, resume, gain a minute or stop. The island
// shows the most relevant one (`primary`: the soonest running timer, else the
// stopwatch, else whatever's paused), and the dashboard's Timers tab shows all.
// IPC "timer": start <25m|90s|1h30m|10> (bare number = minutes), stopwatch,
// toggle / stop (the primary), stopAll, list.
Singleton {
    id: root

    // each: { id, kind: "timer"|"stopwatch", name, total, accumulated, startedAt, running, laps: [ms] }
    property list<var> items: []
    property real now: Date.now()
    property int nextId: 1
    signal finished(real total)

    // ── reading an item (bind to these; they follow `now`) ──
    function elapsedOf(it: var): real { return it ? it.accumulated + (it.running ? Math.max(0, now - it.startedAt) : 0) : 0; }
    function remainingOf(it: var): real { return it ? Math.max(0, it.total - elapsedOf(it)) : 0; }
    function progressOf(it: var): real { return it && it.kind === "timer" && it.total > 0 ? Math.min(1, elapsedOf(it) / it.total) : 0; }
    function labelOf(it: var): string { return it ? clock(it.kind === "timer" ? remainingOf(it) : elapsedOf(it), it.kind === "timer") : ""; }
    function clock(ms: real, up: bool): string {
        const t = Math.max(0, up ? Math.ceil(ms / 1000) : Math.floor(ms / 1000));
        const h = Math.floor(t / 3600), m = Math.floor(t % 3600 / 60), sec = t % 60;
        return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(sec).padStart(2, "0");
    }
    function fmtTotal(ms: real): string {
        const t = Math.round(ms / 1000), h = Math.floor(t / 3600), m = Math.floor(t % 3600 / 60), s = t % 60;
        return [h ? h + "h" : "", m ? m + "m" : "", s ? s + "s" : ""].join(" ").trim() || "0s";
    }
    function parse(spec: string): real {
        spec = (spec || "").trim().toLowerCase();
        if (/^\d+(\.\d+)?$/.test(spec)) return parseFloat(spec) * 60000;
        let ms = 0, ok = false;
        const re = /(\d+(?:\.\d+)?)\s*(h|m|s)/g; // no matchAll in QML's JS
        for (let m = re.exec(spec); m; m = re.exec(spec)) {
            ms += parseFloat(m[1]) * (m[2] === "h" ? 3600000 : m[2] === "m" ? 60000 : 1000);
            ok = true;
        }
        return ok ? ms : 0;
    }

    readonly property var stopwatch: items.find(i => i.kind === "stopwatch") ?? null
    readonly property list<var> timers: items.filter(i => i.kind === "timer")
    readonly property var primary: {
        const run = timers.filter(t => t.running).sort((a, b) => remainingOf(a) - remainingOf(b) || a.id - b.id);
        return run[0] ?? (stopwatch?.running ? stopwatch : null) ?? items[0] ?? null;
    }

    // ── the primary, for the island (same names as before) ──
    readonly property string mode: primary?.kind ?? ""
    readonly property bool running: primary?.running ?? false
    readonly property real progress: progressOf(primary)
    readonly property string label: labelOf(primary)
    readonly property int count: items.length

    // ── changing ──
    function update(id: int, f: var): void {
        items = items.map(i => i.id === id ? f(Object.assign({}, i)) : i);
    }
    function startTimer(ms, name): int {
        if (ms <= 0) return 0;
        const t = Date.now();
        now = t;
        const id = nextId++;
        items = [...items, { id, kind: "timer", name: name || fmtTotal(ms), total: ms, accumulated: 0, startedAt: t, running: true, laps: [] }];
        return id;
    }
    function startStopwatch(): void {
        const t = Date.now();
        now = t;
        const sw = { id: nextId++, kind: "stopwatch", name: "Stopwatch", total: 0, accumulated: 0, startedAt: t, running: true, laps: [] };
        items = [...items.filter(i => i.kind !== "stopwatch"), sw];
    }
    function toggle(id): void {
        const it = id ? items.find(i => i.id === id) : primary;
        if (!it) return;
        const t = Date.now();
        now = t;
        update(it.id, i => {
            if (i.running) { i.accumulated += t - i.startedAt; i.running = false; }
            else { i.startedAt = t; i.running = true; }
            return i;
        });
    }
    function addTime(id: int, ms: real): void { update(id, i => { i.total += ms; return i; }); }
    function lap(id: int): void {
        const e = elapsedOf(items.find(i => i.id === id));
        update(id, i => { i.laps = [...i.laps, e]; return i; });
    }
    function stop(id): void {
        const it = id ? items.find(i => i.id === id) : primary;
        if (it) items = items.filter(i => i.id !== it.id);
    }
    function stopAll(): void { items = []; }

    Timer {
        interval: 100
        repeat: true
        running: root.items.some(i => i.running)
        onTriggered: {
            root.now = Date.now();
            // plain copies first: stop() rewrites the list we'd be walking
            const done = root.timers.filter(t => t.running && root.remainingOf(t) <= 0).map(t => ({ id: t.id, name: t.name, total: t.total }));
            for (const t of done) {
                root.stop(t.id);
                root.finished(t.total);
                Quickshell.execDetached(["notify-send", "-a", "Timer", "-i", "alarm-symbolic", "Timer done",
                    (t.name && t.name !== root.fmtTotal(t.total) ? t.name + " · " : "") + root.fmtTotal(t.total) + " is up"]);
            }
        }
    }

    IpcHandler {
        target: "timer"
        function start(spec: string): string {
            const ms = root.parse(spec);
            if (ms <= 0) return "can't read '" + spec + "' (try 25m, 90s, 1h30m)";
            root.startTimer(ms, "");
            return "ok";
        }
        function stopwatch(): void { root.startStopwatch(); }
        function toggle(): void { root.toggle(0); }
        function stop(): void { root.stop(0); }
        function stopAll(): void { root.stopAll(); }
        function list(): string {
            return root.items.map(i => `${i.kind} ${i.name}: ${root.labelOf(i)}${i.running ? "" : " (paused)"}`).join("\n") || "nothing running";
        }
    }
}
