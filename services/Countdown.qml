pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// A timer or a stopwatch, shown live on the island.
// IPC "timer": start <25m|90s|1h30m|10> (a bare number is minutes),
// stopwatch, toggle (pause/resume), stop.
Singleton {
    id: root

    property string mode: ""        // "" | timer | stopwatch
    property bool running: false
    property real total: 0          // ms (timer)
    property real accumulated: 0    // ms counted before the current run
    property real startedAt: 0
    property real now: Date.now()
    readonly property real elapsed: accumulated + (running ? Math.max(0, now - startedAt) : 0)
    readonly property real remaining: Math.max(0, total - elapsed)
    readonly property real progress: mode === "timer" && total > 0 ? Math.min(1, elapsed / total) : 0
    readonly property string label: fmt(mode === "timer" ? remaining : elapsed)
    signal finished(real total)

    function fmt(ms: real): string {
        const s = Math.ceil(ms / 1000) - (mode === "stopwatch" ? 1 : 0);
        const t = Math.max(0, mode === "stopwatch" ? Math.floor(ms / 1000) : s);
        const h = Math.floor(t / 3600), m = Math.floor(t % 3600 / 60), sec = t % 60;
        return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(sec).padStart(2, "0");
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

    function startTimer(ms: real): void {
        if (ms <= 0) return;
        mode = "timer"; total = ms; accumulated = 0; startedAt = Date.now(); now = startedAt; running = true;
    }
    function startStopwatch(): void {
        mode = "stopwatch"; total = 0; accumulated = 0; startedAt = Date.now(); now = startedAt; running = true;
    }
    function toggle(): void {
        if (!mode) return;
        now = Date.now();
        if (running) { accumulated += now - startedAt; running = false; }
        else { startedAt = now; running = true; }
    }
    function stop(): void { mode = ""; running = false; accumulated = 0; total = 0; }

    Timer {
        interval: 200
        repeat: true
        running: root.running
        onTriggered: {
            root.now = Date.now();
            if (root.mode === "timer" && root.remaining <= 0) {
                const t = root.total;
                root.stop();
                root.finished(t);
                notify.command = ["notify-send", "-a", "Timer", "-i", "alarm-symbolic", "Timer done", root.fmtTotal(t) + " is up"];
                notify.running = true;
            }
        }
    }
    function fmtTotal(ms: real): string {
        const t = Math.round(ms / 1000), h = Math.floor(t / 3600), m = Math.floor(t % 3600 / 60), s = t % 60;
        return [h ? h + "h" : "", m ? m + "m" : "", s ? s + "s" : ""].join(" ").trim() || "0s";
    }
    Process { id: notify }

    IpcHandler {
        target: "timer"
        function start(spec: string): string {
            const ms = root.parse(spec);
            if (ms <= 0) return "can't read '" + spec + "' (try 25m, 90s, 1h30m)";
            root.startTimer(ms);
            return "ok";
        }
        function stopwatch(): void { root.startStopwatch(); }
        function toggle(): void { root.toggle(); }
        function stop(): void { root.stop(); }
    }
}
