pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Default speaker and microphone (PipeWire): volume and mute.
Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.sink, root.source] }

    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property bool micMuted: source?.audio?.muted ?? false

    function setVolume(v: real): void {
        if (!sink?.audio) return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1.5, Math.round(v * 100) / 100));
    }
    function toggleMute(): void { if (sink?.audio) sink.audio.muted = !sink.audio.muted; }
}
