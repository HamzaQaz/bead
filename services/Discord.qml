pragma Singleton

import QtQuick
import Quickshell
import qs.config
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import "presence.js" as P

// Discord, from bin/bead-discord (Discord's local RPC socket): voice calls,
// calls ringing (answer / leave), the inbox (unread DMs and @mentions; they
// clear when you look: focus Discord, or open one), busy voice channels in
// your servers ("Voice now"), and opt-in Rich Presence (music, project).
// Needs a personal Discord app: see `bead discord setup`.
Singleton {
    id: root

    property string state: ""       // setup | offline | authorizing | ready | error
    property string detail: ""
    property var channel: null      // { id, name, guild } while in a call
    property list<var> members: []  // { id, name, avatar, mute, deaf, speaking, me }
    property bool mute: false
    property bool deaf: false

    property list<var> dms: []      // { channel, guild, kind: dm|mention, name, avatar, count, text, link }, newest first
    property var ring: null         // { channel, name, avatar } while a call rings
    property list<var> voiceNow: [] // { id, name, guild, count, people: [{ id, name, avatar }] }
    property bool scanning: false
    property int dmUnread: 0
    readonly property int dmCount: Demo.on ? 0 : dmUnread // demo mode: none

    readonly property bool inCall: !!channel && !Demo.on
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
    function markRead(): void { if (dmUnread > 0) send("read"); }
    function answer(): void { if (ring && ring.channel !== "preview") send("answer " + ring.channel); else ring = null; }
    function dismiss(): void { if (ring?.channel === "preview") ring = null; else send("dismiss"); }
    function join(id: string): void { send("join " + id); }
    function scanVoice(): void { if (helper.running && state === "ready") { scanning = true; send("voice-now"); } }
    // an inbox item: open its channel in Discord, and it's read
    function open(item: var): void {
        send("read " + item.channel);
        Quickshell.execDetached(["xdg-open", item.link]);
        Hyprland.dispatch('hl.dsp.focus({ window = "class:discord" })');
    }
    signal ringing(var call)

    // ── presence: only what Settings allow; sent when it changes ──
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? null
    readonly property string presenceJson: {
        const prefs = { music: Settings.discordMusic, project: Settings.discordProject };
        if (!prefs.music && !prefs.project) return JSON.stringify({ prefs });
        const t = Hyprland.activeToplevel;
        return JSON.stringify({
            prefs,
            track: prefs.music && player && !Demo.on ? { title: player.trackTitle || "", artist: player.trackArtist || "" } : null,
            project: prefs.project && !Demo.on ? P.project(t?.wayland?.appId || t?.lastIpcObject?.class || "", t?.title || "") : ""
        });
    }
    // a project stays named while you glance at a browser: keep the last one a while
    onPresenceJsonChanged: presenceTimer.restart()
    Timer { id: presenceTimer; interval: 3000; onTriggered: root.sendPresence() }
    property string lastProject: ""
    function sendPresence(): void {
        if (state !== "ready") return;
        const p = JSON.parse(presenceJson);
        if (p.project) lastProject = p.project;
        else if (p.prefs.project) p.project = lastProject;
        send("presence " + JSON.stringify(p));
    }
    onStateChanged: if (state === "ready") presenceTimer.restart()
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
        command: [Paths.cmd("bead-discord")]
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.type === "status") {
                    root.state = m.state;
                    root.detail = m.detail || "";
                } else if (m.type === "dms") {
                    const before = root.dmUnread;
                    root.dms = m.from ?? [];
                    root.dmUnread = m.count ?? 0;
                    if (root.dmUnread > before && root.dms.length) root.dmArrived(root.dms[0]);
                } else if (m.type === "ring") {
                    root.ring = m.call ?? null;
                    if (root.ring) root.ringing(root.ring);
                } else if (m.type === "voicenow") {
                    root.voiceNow = m.channels ?? [];
                    root.scanning = false;
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
        onExited: { root.primed = false; root.channel = null; root.members = []; root.dms = []; root.dmUnread = 0; root.ring = null; root.voiceNow = []; root.scanning = false; restart.start(); }
        onRunningChanged: if (running) prime.restart()
    }
    Timer { id: restart; interval: 5000; onTriggered: helper.running = true }
    Timer { id: ringEnd; interval: 8000; onTriggered: if (root.ring?.channel === "preview") root.ring = null }
    Timer { id: previewEnd; interval: 8000; onTriggered: if (root.dms[0]?.channel === "preview") { root.dms = []; root.dmUnread = 0; } }

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
        function answer(): void { root.answer(); }
        // scan your servers' voice channels; `voiceNow` again to read what it found
        function voiceNow(): string { root.scanVoice(); return root.voiceNow.map(c => c.name + " (" + c.guild + "): " + c.people.map(p => p.name).join(", ")).join("\n"); }
        // a pretend incoming call for 8 s
        function previewRing(): void {
            root.ring = { channel: "preview", name: "Preview", avatar: "https://cdn.discordapp.com/embed/avatars/1.png" };
            root.ringing(root.ring);
            ringEnd.restart();
        }
        // a pretend unread DM for 8 s, to see how it looks
        function preview(): void {
            root.dms = [{ channel: "preview", name: "Preview", avatar: "https://cdn.discordapp.com/embed/avatars/0.png", count: 2, text: "" }];
            root.dmUnread = 2;
            root.dmArrived(root.dms[0]);
            previewEnd.restart();
        }
    }
}
