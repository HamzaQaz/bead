pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Caps Lock state, read from the keyboards' LEDs (/sys/class/leds/*::capslock).
// The kernel keeps every keyboard's LED in step, so any one of them lit means on.
// Hyprland sends no event for it, so the LEDs are polled (a tiny sysfs read).
Singleton {
    id: root

    property bool on: false
    property bool known: false // false until the first read, so startup isn't a "change"
    signal toggled(bool on)

    property list<string> leds: []

    IpcHandler {
        target: "capslock"
        function state(): string { return (root.on ? "on" : "off") + " (" + root.leds.length + " keyboards)"; }
    }

    // keyboards come and go (Bluetooth, RustDesk): look for LEDs now and then
    Process {
        id: finder
        running: true
        command: ["sh", "-c", "ls -d /sys/class/leds/*::capslock 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = text.split("\n").filter(l => l).map(l => l + "/brightness");
                if (found.join() !== root.leds.join()) root.leds = found;
            }
        }
    }
    Timer { interval: 10000; repeat: true; running: true; onTriggered: finder.running = true }

    Instantiator {
        id: views
        model: root.leds
        FileView {
            required property string modelData
            path: modelData
            blockLoading: true
            printErrors: false
        }
    }

    Timer {
        interval: 150
        repeat: true
        running: root.leds.length > 0
        onTriggered: {
            let lit = false;
            for (let i = 0; i < views.count; i++) {
                const v = views.objectAt(i);
                if (!v) continue;
                v.reload();
                if (v.text().trim() !== "0" && v.text().trim() !== "") lit = true;
            }
            if (!root.known) { root.on = lit; root.known = true; return; }
            if (lit !== root.on) { root.on = lit; root.toggled(lit); }
        }
    }
}
