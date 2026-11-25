pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.config
import "audiofx.js" as F

// The mixer's extras (modules/mixer/MixerWindow.qml), all made at runtime and
// gone with bead: nothing is written to your PipeWire config.
//   Both     one sound on two outputs at once (two headphones): PipeWire's
//            combine sink, made the default while on
//   Mic      effects on your mic: RNNoise noise suppression, an EQ preset,
//            gain. bead runs a small filter chain (pipewire -c) that records
//            from your mic and appears as "bead Mic", the default input while on
//   Monitor  hear your mic in your headphones (a loopback)
// Settings keep what's on; each start clears anything an old bead left.
Singleton {
    id: root

    property bool open: false   // the mixer window
    IpcHandler {
        target: "mixer"
        function open(): void { root.open = true; }
        function close(): void { root.open = false; }
        function toggle(): void { root.open = !root.open; }
        function status(): string { return JSON.stringify({ effects: root.effectsOn, beadMic: !!root.beadMic, both: !!root.bothSink, monitor: root.monitorModule >= 0, mic: root.micName }); }
    }

    readonly property string rnnoise: "/usr/lib/ladspa/librnnoise_ladspa.so"
    property bool hasRnnoise: false
    readonly property string confPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/bead/mic-chain.conf"

    // ── the real mic: what bead Mic records from (never bead Mic itself) ──
    readonly property PwNode beadMic: Audio.sources.find(n => n.name === "bead_mic") ?? null
    readonly property var realSources: Audio.sources.filter(n => n.name !== "bead_mic")
    readonly property string micName: Settings.micSource || (Audio.source && Audio.source.name !== "bead_mic" ? Audio.source.name : realSources[0]?.name ?? "")

    // ── mic effects ──
    readonly property var opts: ({ noise: Settings.micNoise && hasRnnoise, threshold: Settings.micThreshold, eq: Settings.micEq, gain: Settings.micGain, source: micName })
    readonly property string chain: micName ? F.micChain(opts, rnnoise) : ""
    readonly property bool effectsOn: chain !== ""
    onChainChanged: restartChain.restart()
    Timer {
        id: restartChain
        interval: 300   // a slider being dragged: once it settles
        onTriggered: {
            chainProc.running = false;
            if (!root.effectsOn) { root.useMic(false); return; }
            writer.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"', "sh", root.confPath, root.chain];
            writer.running = true;
        }
    }
    Process { id: writer; onExited: chainProc.running = true }
    Process {
        id: chainProc
        command: ["pipewire", "-c", root.confPath]
        onRunningChanged: if (!running && root.effectsOn && !restartChain.running) crashRestart.restart()
    }
    Timer { id: crashRestart; interval: 3000; onTriggered: if (root.effectsOn && !chainProc.running) chainProc.running = true }
    // bead Mic appears: make it the default input; effects off: back to the real one
    onBeadMicChanged: {
        if (beadMic && effectsOn) useMic(true);
        if (Settings.micMonitor) monFollow.restart();
    }
    function useMic(fx: bool): void {
        if (fx && beadMic) Pipewire.preferredDefaultAudioSource = beadMic;
        else if (!fx) {
            const real = realSources.find(n => n.name === micName);
            if (real && Audio.source?.name === "bead_mic") Pipewire.preferredDefaultAudioSource = real;
        }
    }

    // ── Both ──
    property int bothModule: -1
    readonly property PwNode bothSink: Audio.sinks.find(n => n.name === "bead_both") ?? null
    function setBoth(on: bool): void {
        Settings.audioBoth = on;
        applyBoth();
    }
    function applyBoth(): void {
        unload(bothModule); bothModule = -1;
        const args = Settings.audioBoth ? F.combineArgs(Settings.audioBothSinks) : null;
        if (!args) return;
        bothLoader.command = ["pactl", ...args];
        bothLoader.running = true;
    }
    Process {
        id: bothLoader
        stdout: StdioCollector { onStreamFinished: { const id = parseInt(text); if (!isNaN(id)) root.bothModule = id; } }
    }
    onBothSinkChanged: if (bothSink && Settings.audioBoth) Pipewire.preferredDefaultAudioSink = bothSink

    // ── Monitor ──
    property int monitorModule: -1
    function setMonitor(on: bool): void { Settings.micMonitor = on; applyMonitor(); }
    function applyMonitor(): void {
        unload(monitorModule); monitorModule = -1;
        if (!Settings.micMonitor) return;
        monLoader.command = ["pactl", ...F.loopbackArgs(effectsOn && beadMic ? "bead_mic" : micName, 30)];
        monLoader.running = true;
    }
    Process {
        id: monLoader
        stdout: StdioCollector { onStreamFinished: { const id = parseInt(text); if (!isNaN(id)) root.monitorModule = id; } }
    }
    // the monitor follows the mic you hear: the effects coming or going
    onEffectsOnChanged: if (Settings.micMonitor) monFollow.restart()
    Timer { id: monFollow; interval: 400; onTriggered: root.applyMonitor() }
    readonly property PwNode monitorStream: Audio.audioNodes.find(n => n.isStream && n.properties?.["media.name"] === "bead-monitor") ?? null

    function unload(id: int): void { if (id >= 0) Quickshell.execDetached(["pactl", "unload-module", String(id)]); }

    // ── start: clear what an old bead left, then make what Settings say ──
    Process {
        id: sweep
        running: true
        command: ["sh", "-c", `
            pactl list short modules | awk '/sink_name=bead_both|media.name=bead-monitor/ {print $1}' | xargs -r -n1 pactl unload-module
            pkill -u "$(id -u)" -f '^pipewire -c .*/bead/mic-chain.conf$'
            [ -f "$1" ] && echo rnnoise; exit 0`, "sh", root.rnnoise]
        stdout: StdioCollector { onStreamFinished: root.hasRnnoise = text.includes("rnnoise") }
        onExited: { root.applyBoth(); root.applyMonitor(); if (root.effectsOn) restartChain.restart(); }
    }
}
