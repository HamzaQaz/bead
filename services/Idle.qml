pragma Singleton

import QtQuick
import Quickshell
import qs.config
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland

// Idle and sleep, replacing Caelestia's (same defaults): lock after 3 min,
// screen off after 5 (on again when you're back), suspend after 10. Nothing
// happens while audio plays, while an app inhibits idle (a video, a game),
// or while you've turned on "keep awake". The screen also locks before the
// machine sleeps (bead holds a logind sleep delay until it has) and when
// asked to (`loginctl lock-session`).
Singleton {
    id: root

    // from Settings (minutes; 0 skips a step)
    readonly property list<var> steps: [
        { after: Settings.lockAfter * 60, idle: "lock" },
        { after: Settings.screenOffAfter * 60, idle: "dpms off", back: "dpms on" },
        { after: Settings.suspendAfter * 60, idle: "suspend" }
    ].filter(s => s.after > 0)

    property bool keepAwake: false
    readonly property bool playing: Mpris.players.values.some(p => p.isPlaying)
    readonly property bool active: !keepAwake && !(Settings.pauseForMedia && playing)

    function act(a: string): void {
        switch (a) {
        case "lock": Lock.lock(); break;
        case "dpms off": Hyprland.dispatch('hl.dsp.dpms({ action = "disable" })'); break;
        case "dpms on": Hyprland.dispatch('hl.dsp.dpms({ action = "enable" })'); break;
        case "suspend": Quickshell.execDetached(["systemctl", "suspend"]); break;
        }
    }

    Variants {
        model: root.steps
        IdleMonitor {
            required property var modelData
            enabled: root.active
            timeout: modelData.after
            respectInhibitors: true
            onIsIdleChanged: {
                const a = isIdle ? modelData.idle : modelData.back;
                if (a) root.act(a);
            }
        }
    }

    // ── logind: lock before sleep, lock-session requests ──
    // a delay inhibitor makes logind wait (up to its limit) until we let go
    Process {
        id: inhibitor
        running: true
        stdinEnabled: true
        command: ["systemd-inhibit", "--what=sleep", "--mode=delay", "--who=bead",
            "--why=Lock the screen before sleep", "sh", "-c", "read -r _"]
    }
    Timer { id: release; interval: 700; onTriggered: inhibitor.running = false }

    // our session's object path: /org/freedesktop/login1/session/<escaped id>
    readonly property string sessionPath: {
        const id = Quickshell.env("XDG_SESSION_ID") || "";
        let out = "";
        for (let i = 0; i < id.length; i++) {
            const c = id[i];
            out += /[A-Za-z]/.test(c) || (/[0-9]/.test(c) && i > 0) ? c : "_" + c.charCodeAt(0).toString(16);
        }
        return "/org/freedesktop/login1/session/" + out;
    }
    Process {
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"]
        stdout: SplitParser {
            onRead: line => {
                if (line.includes(".Manager.PrepareForSleep (true")) {
                    Lock.lock();
                    release.restart(); // let the lock appear, then let sleep go ahead
                } else if (line.includes(".Manager.PrepareForSleep (false")) {
                    inhibitor.running = true; // awake: hold it again for next time
                } else if (line.startsWith(root.sessionPath + ":") && line.includes(".Session.Lock ()")) {
                    Lock.lock();
                }
            }
        }
    }

    IpcHandler {
        target: "idle"
        function toggle(): bool { root.keepAwake = !root.keepAwake; return root.keepAwake; }
        function status(): string { return root.keepAwake ? "keeping awake" : root.playing ? "paused: audio playing" : "on"; }
    }
}
