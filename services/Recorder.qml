pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Notices a screen recording in progress (wf-recorder, gpu-screen-recorder:
// what Caelestia's recorder and most scripts use) and can stop it.
Singleton {
    id: root

    property int pid: 0
    property string name: ""
    property real startedAt: 0      // ms epoch
    readonly property bool recording: pid > 0
    property real now: Date.now()
    readonly property string label: {
        const t = Math.max(0, Math.floor((now - startedAt) / 1000));
        const h = Math.floor(t / 3600), m = Math.floor(t % 3600 / 60), s = t % 60;
        return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(s).padStart(2, "0");
    }

    // SIGINT lets the recorder finish writing the file
    function stop(): void {
        if (pid > 0) { killer.command = ["kill", "-INT", String(pid)]; killer.running = true; }
    }
    Process { id: killer }

    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: probe.running = true
    }
    Timer { interval: 1000; repeat: true; running: root.recording; onTriggered: root.now = Date.now() }

    Process {
        id: probe
        command: ["sh", "-c", "p=$(pgrep -o -x 'wf-recorder|gpu-screen-reco' 2>/dev/null) && echo \"$p $(ps -o etimes= -p $p) $(cat /proc/$p/comm)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(/\s+/);
                const pid = parseInt(f[0]) || 0;
                if (pid !== root.pid) {
                    root.pid = pid;
                    root.name = f[2] ?? "";
                    root.startedAt = Date.now() - (parseInt(f[1]) || 0) * 1000;
                    root.now = Date.now();
                }
            }
        }
    }
}
