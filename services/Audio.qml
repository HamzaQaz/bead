pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "autosink.js" as AutoSink

// PipeWire: the default speaker and microphone (volume, mute), the output
// and input devices to choose from, and the apps playing or recording.
// Bluetooth headphones are followed: when they connect, sound moves to them;
// when they go, it moves back to what was playing before (autosink.js).
Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    // a node's properties and audio only fill in once it's tracked: track them all
    PwObjectTracker { objects: Pipewire.nodes.values }
    readonly property list<PwNode> audioNodes: Pipewire.nodes.values.filter(n => n.audio && /Audio/.test(n.properties?.["media.class"] ?? ""))
    readonly property list<PwNode> sinks: audioNodes.filter(n => n.isSink && !n.isStream)
    readonly property list<PwNode> sources: audioNodes.filter(n => !n.isSink && !n.isStream)
    // apps playing (streams that output) and recording (streams that take input)
    // (by media class: isSink reads the other way round for streams)
    function mediaClass(n: PwNode): string { return n?.properties?.["media.class"] ?? ""; }
    readonly property list<PwNode> playing: audioNodes.filter(n => n.isStream && mediaClass(n) === "Stream/Output/Audio")
    readonly property list<PwNode> recording: audioNodes.filter(n => n.isStream && mediaClass(n) === "Stream/Input/Audio"
        && !/^(cava|pipewire|wireplumber|quickshell|qs)/i.test(appName(n)))

    // ── following Bluetooth headphones ──
    readonly property var sinkNames: sinks.map(n => n.name).filter(Boolean)
    property var lastNames: []
    property string switchedTo: ""
    property string before: ""
    property bool settled: false       // what's there at start was already chosen
    Timer { running: true; interval: 4000; onTriggered: { root.lastNames = root.sinkNames; root.settled = true; } }
    // the headphones just went: wait out a blip before going back (opening a
    // game or a call can drop and remake their output in a moment)
    property var blipFrom: null
    Timer { id: blip; interval: 5000; onTriggered: { const was = root.blipFrom; root.blipFrom = null; root.follow(was, root.sinkNames); } }
    onSinkNamesChanged: {
        if (!settled) return;
        const was = blipFrom ?? lastNames;
        lastNames = sinkNames;
        if (blip.running) {
            const back = sinkNames.find(n => AutoSink.sameDevice(n, switchedTo) || n === switchedTo);
            if (!back) return; // still gone: keep waiting
            blip.stop(); blipFrom = null;
            switchedTo = back;
            const to = sinks.find(n => n.name === back);
            if (to && sink?.name !== back) useSink(to); // quietly back on them
            return;
        }
        if (AutoSink.waits(was, sinkNames, switchedTo)) { blipFrom = was; blip.restart(); return; }
        follow(was, sinkNames);
    }
    function follow(was: var, now: var): void {
        const d = AutoSink.decide(was, now, sink?.name ?? "", switchedTo, before);
        if (!d) return;
        const to = sinks.find(n => n.name === d.use);
        const onto = /^bluez_output\./.test(d.use);   // onto the headphones, or back from them
        switchedTo = onto ? d.use : "";
        before = onto ? d.before : "";
        if (!to) return;
        useSink(to);
        Osd.toast(switchedTo ? "headphones" : deviceGlyph(to, false), "Sound on " + deviceName(to), "info", 2600);
    }

    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property real micVolume: source?.audio?.volume ?? 0
    readonly property bool micMuted: source?.audio?.muted ?? false

    function clamp(v: real): real { return Math.max(0, Math.min(1.5, Math.round(v * 100) / 100)); }
    function setVolume(v: real): void {
        if (!sink?.audio) return;
        sink.audio.muted = false;
        sink.audio.volume = clamp(v);
    }
    function toggleMute(): void { if (sink?.audio) sink.audio.muted = !sink.audio.muted; }
    function setMicVolume(v: real): void {
        if (!source?.audio) return;
        source.audio.muted = false;
        source.audio.volume = clamp(v);
    }
    function toggleMicMute(): void { if (source?.audio) source.audio.muted = !source.audio.muted; }
    function setNodeVolume(n: PwNode, v: real): void {
        if (!n?.audio) return;
        n.audio.muted = false;
        n.audio.volume = clamp(v);
    }
    function useSink(n: PwNode): void { Pipewire.preferredDefaultAudioSink = n; }
    function useSource(n: PwNode): void { Pipewire.preferredDefaultAudioSource = n; }

    function deviceName(n: PwNode): string { return n?.description || n?.nickname || n?.name || ""; }
    function appName(n: PwNode): string {
        const p = n?.properties ?? {};
        return p["application.name"] || n?.description || n?.name || "";
    }
    function appIcon(n: PwNode): string {
        const p = n?.properties ?? {};
        const id = p["application.icon-name"] || p["application.process.binary"] || appName(n).toLowerCase();
        const e = DesktopEntries.heuristicLookup(id);
        return Quickshell.iconPath(e?.icon || id, true);
    }
    function deviceGlyph(n: PwNode, input: bool): string {
        const s = ((n?.description ?? "") + " " + (n?.name ?? "")).toLowerCase();
        if (input) return /webcam|camera/.test(s) ? "videocam" : "mic";
        if (/headset|headphone|buds|airpods/.test(s)) return "headphones";
        if (/hdmi|displayport|monitor/.test(s)) return "tv";
        if (/bluez|bluetooth/.test(s)) return "bluetooth";
        return "speaker";
    }
    function levelGlyph(v: real, m: bool): string {
        return m || v <= 0 ? "volume_off" : v < 0.34 ? "volume_mute" : v < 0.67 ? "volume_down" : "volume_up";
    }
}
