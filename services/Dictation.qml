pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Push-to-talk dictation: hold the key, speak, release, and the words are
// typed into whatever text field has focus (any app, or bead's own fields).
// The work is bin/bead-dictate: pw-record, then whisper.cpp, then wtype.
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
        level = 0;
        state = "listening";
        helper.running = true;
    }
    function stop(): void { if (helper.running && state === "listening") helper.write("stop\n"); }
    function cancel(): void { if (helper.running) helper.write("cancel\n"); }
    function toggle(): void { if (state === "listening") stop(); else if (!active) start(); }

    Process {
        id: helper
        command: [Quickshell.env("HOME") + "/.local/bin/bead-dictate"]
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
        onExited: { root.state = ""; root.level = 0; }
    }

    IpcHandler {
        target: "dictate"
        function start(): void { root.start(); }
        function stop(): void { root.stop(); }
        function cancel(): void { root.cancel(); }
        function toggle(): void { root.toggle(); }
        function status(): string { return root.state || "idle"; }
    }
}
