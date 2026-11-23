pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Discord voice calls, from bin/bead-discord (Discord's local RPC socket).
// Needs a personal Discord app: see `bead discord setup`.
Singleton {
    id: root

    property string state: ""       // setup | offline | authorizing | ready | error
    property string detail: ""
    property var channel: null      // { id, name, guild } while in a call
    property list<var> members: []  // { id, name, avatar, mute, deaf, speaking, me }
    property bool mute: false
    property bool deaf: false

    readonly property bool inCall: !!channel
    readonly property list<var> speaking: members.filter(m => m.speaking)

    // a (re)started helper reports the call you're already in: not a "join"
    property bool primed: false
    Timer { id: prime; interval: 4000; running: true; onTriggered: root.primed = true }

    signal joined(string name)
    signal left
    signal muteToggled(bool mute)

    function send(c: string): void { if (helper.running) helper.write(c + "\n"); }
    function toggleMute(): void { send("toggle-mute"); }
    function toggleDeaf(): void { send("toggle-deaf"); }
    function leave(): void { send("leave"); }

    Process {
        id: helper
        running: true
        stdinEnabled: true
        command: [Quickshell.env("HOME") + "/.local/bin/bead-discord"]
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.type === "status") {
                    root.state = m.state;
                    root.detail = m.detail || "";
                } else if (m.type === "voice") {
                    const was = root.channel?.id ?? "";
                    const now = m.channel?.id ?? "";
                    const wasMuted = root.mute;
                    root.channel = m.channel;
                    root.members = m.members ?? [];
                    root.mute = !!m.mute;
                    root.deaf = !!m.deaf;
                    if (!root.primed) return;
                    if (now && now !== was) root.joined(m.channel.name);
                    else if (!now && was) root.left();
                    if (now && now === was && wasMuted !== root.mute) root.muteToggled(root.mute);
                }
            }
        }
        onExited: { root.primed = false; root.channel = null; root.members = []; restart.start(); }
        onRunningChanged: if (running) prime.restart()
    }
    Timer { id: restart; interval: 5000; onTriggered: helper.running = true }

    // a new or edited config: start over
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/bead/discord.json"
        watchChanges: true
        printErrors: false
        onFileChanged: { helper.running = false; restart.restart(); }
    }

    IpcHandler {
        target: "discord"
        function status(): string {
            if (!root.inCall) return root.state + (root.detail ? ": " + root.detail : "");
            return "in " + root.channel.name + (root.channel.guild ? " (" + root.channel.guild + ")" : "")
                + " with " + root.members.map(m => m.name + (m.speaking ? "*" : "")).join(", ")
                + (root.mute ? " [muted]" : "") + (root.deaf ? " [deafened]" : "");
        }
        function mute(): void { root.toggleMute(); }
        function deafen(): void { root.toggleDeaf(); }
        function leave(): void { root.leave(); }
    }
}
