pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Push-to-talk dictation: hold the key, speak, release, and the words are
// typed into whatever text field has focus (any app, or bead's own fields).
// The work is bin/bead-dictate: pw-record, then whisper.cpp, then wtype.
// Live: the words are typed while you speak (through the warm whisper-server
// voice commands use), and the final transcript corrects them on release.
Singleton {
    id: root

    // "" | listening | transcribing
    property string state: ""
    readonly property bool active: state !== ""
    property real level: 0
    property string lastText: ""
    signal failed(string why)
    signal typed(string text)

    function start(): void {
        if (helper.running) return;
        // a muted mic records silence, which then does nothing: say so instead
        if (Audio.micMuted) { root.failed("Your mic is muted"); return; }
        Voice.ensureWhisper();
        level = 0;
        state = "listening";
        helper.running = true;
    }
    function stop(): void { if (helper.running && state === "listening") helper.write("stop\n"); }
    function cancel(): void { if (helper.running) helper.write("cancel\n"); }
    function toggle(): void { if (state === "listening") stop(); else if (!active) start(); }

    // the shortcut: hold it to talk (typed when you let go: while Super is
    // down, typed letters would be shortcuts), or tap it to go hands-free
    // (typed live as you speak; tap again, or stop talking, to finish)
    property bool handsFree: false
    property real pressedAt: 0
    function keyDown(): void {
        if (state === "listening" && handsFree) { stop(); return; } // the second tap
        if (active) return;
        handsFree = false;
        pressedAt = Date.now();
        start();
    }
    function keyUp(): void {
        if (state !== "listening" || handsFree) return;
        if (Date.now() - pressedAt < 350) { handsFree = true; helper.write("free\n"); }
        else stop();
    }

    Process {
        id: helper
        command: [Quickshell.env("HOME") + "/.local/bin/bead-dictate", "--live", "--partials",
            "--server", "http://127.0.0.1:" + Voice.whisperPort]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.level !== undefined) root.level = m.level;
                else if (m.state) { root.state = m.state; root.level = 0; }
                else if (m.error) root.failed(m.error);
                else if (m.text !== undefined) { root.lastText = m.text; if (m.text) root.typed(m.text); }
            }
        }
        onExited: { root.state = ""; root.level = 0; root.handsFree = false; }
    }

    IpcHandler {
        target: "dictate"
        function start(): void { root.start(); }
        function stop(): void { root.stop(); }
        function cancel(): void { root.cancel(); }
        function toggle(): void { root.toggle(); }
        // hands-free from a script or another key: start, typing live at once
        function live(): void { if (!root.active) { root.start(); root.handsFree = true; helper.write("free\n"); } }
        function status(): string { return root.state || "idle"; }
    }
}
