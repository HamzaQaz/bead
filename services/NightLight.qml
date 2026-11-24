pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "nightlight.js" as Night

// The night light: a warmer screen in the evening, through hyprsunset. Off,
// on, or from sunset to sunrise (the weather's times; 19:00 to 7:00 without
// them): Settings.nightLight, and the Utilities panel's chip steps through
// them. bead runs hyprsunset itself while the screen is warm and stops it to
// go back; `available` is false (and the chip hidden) when it isn't installed.
Singleton {
    id: root

    property bool available: false
    readonly property string mode: Settings.nightLight
    property real now: Date.now()
    readonly property bool warm: available && Night.warm(mode, now, Weather.sunrise ? Weather.sunrise.getTime() : 0, Weather.sunset ? Weather.sunset.getTime() : 0)
    readonly property var chip: Night.chip(mode, warm)

    // the next mode; returns what to say about it
    function step(): string {
        Settings.nightLight = Night.nextMode(mode);
        now = Date.now();
        return Night.said(Settings.nightLight, warm, Weather.sunset ? Weather.sunset.getTime() : 0);
    }

    Timer { interval: 60000; repeat: true; running: root.mode === "sunset"; onTriggered: root.now = Date.now() }

    Process { // is it installed?
        running: true
        command: ["sh", "-c", "command -v hyprsunset"]
        onExited: code => root.available = code === 0
    }
    Process { // warm while it runs; colours go back when it stops
        running: root.warm
        command: ["hyprsunset", "--temperature", String(Night.temp(Settings.nightTemp))]
    }
}
