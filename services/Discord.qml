pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Discord voice calls and unread direct messages (DMs and group DMs, never
// servers), from bin/bead-discord (Discord's local RPC socket). Unread DMs
// clear when you look: focus Discord, or tap the island's chip.
// Needs a personal Discord app: see `bead discord setup`.
Singleton {
    id: root

    property string state: ""       // setup | offline | authorizing | ready | error
    property string detail: ""
    property var channel: null      // { id, name, guild } while in a call
    property list<var> members: []  // { id, name, avatar, mute, deaf, speaking, me }
    property bool mute: false
    property bool deaf: false

    property list<var> dms: []      // { channel, name, avatar, count, text }, newest first
    property int dmCount: 0

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
    function markRead(): void { if (dmCount > 0) send("read"); }
    // to Discord (and they count as read)
    function openDms(): void {
        markRead();
        Hyprland.dispatch('hl.dsp.focus({ window = "class:discord" })');
    }
    signal dmArrived(var from)

    // looking at Discord reads them
    Connections {
        target: Hyprland
        function onRawEvent(e: HyprlandEvent): void {
            if (e.name === "activewindow" && /^discord,/i.test(e.data)) root.markRead();
        }
    }

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
                } else if (m.type === "dms") {
                    const before = root.dmCount;
                    root.dms = m.from ?? [];
                    root.dmCount = m.count ?? 0;
                    if (root.dmCount > before && root.dms.length) root.dmArrived(root.dms[0]);
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
        onExited: { root.primed = false; root.channel = null; root.members = []; root.dms = []; root.dmCount = 0; restart.start(); }
        onRunningChanged: if (running) prime.restart()
    }
    Timer { id: restart; interval: 5000; onTriggered: helper.running = true }
    Timer { id: previewEnd; interval: 8000; onTriggered: if (root.dms[0]?.channel === "preview") { root.dms = []; root.dmCount = 0; } }

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
        function dms(): string { return root.dmCount + (root.dms.length ? ": " + root.dms.map(d => d.name + " (" + d.count + ")").join(", ") : ""); }
        function read(): void { root.markRead(); }
        // a pretend unread DM for 8 s, to see how it looks
        function preview(): void {
            root.dms = [{ channel: "preview", name: "Preview", avatar: "https://cdn.discordapp.com/embed/avatars/0.png", count: 2, text: "" }];
            root.dmCount = 2;
            root.dmArrived(root.dms[0]);
            previewEnd.restart();
        }
    }
}
