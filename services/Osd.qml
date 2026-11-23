pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.UPower

// Small events worth a glance, shown as island toasts (Island.qml listens):
// wireless device batteries (charging, low, full), Bluetooth devices coming and
// going, Do Not Disturb, keyboard layout changes. Silent for a few seconds after
// startup, so a restart doesn't announce everything that's already there.
Singleton {
    id: root

    signal toast(string icon, string text, string tone, int ms)

    property bool primed: false
    Timer { interval: 5000; running: true; onTriggered: root.primed = true }
    function say(icon: string, text: string, tone: string, ms: int): void {
        if (primed) toast(icon, text, tone, ms);
    }

    // ── wireless device batteries (UPower: mice, keyboards, headsets…) ──
    function pct(d: UPowerDevice): int {
        const p = d.percentage;
        return Math.round(p <= 1 ? p * 100 : p); // 0..1 in recent Quickshell
    }
    function glyphFor(d: UPowerDevice): string {
        switch (d.type) {
        case UPowerDeviceType.Mouse: return "mouse";
        case UPowerDeviceType.Keyboard: return "keyboard";
        case UPowerDeviceType.Headset:
        case UPowerDeviceType.Headphones: return "headphones";
        case UPowerDeviceType.GamingInput: return "sports_esports";
        case UPowerDeviceType.Phone: return "smartphone";
        default: return "battery_full";
        }
    }
    // `qs ipc call devices list`: what's watched, for checking
    IpcHandler {
        target: "devices"
        function list(): string {
            const out = [];
            for (let i = 0; i < batteries.count; i++) {
                const o = batteries.objectAt(i);
                if (o?.watched) out.push(o.name + ": " + root.pct(o.modelData) + "% " + UPowerDeviceState.toString(o.modelData.state));
            }
            for (const d of Bluetooth.devices.values)
                if (d.connected) out.push((d.name || d.deviceName) + ": bluetooth connected" + (d.batteryAvailable ? " " + Math.round(d.battery <= 1 ? d.battery * 100 : d.battery) + "%" : ""));
            return out.join("\n") || "none";
        }
    }
    Instantiator {
        id: batteries
        model: UPower.devices
        delegate: QtObject {
            id: dev
            required property UPowerDevice modelData
            // peripherals only: not the laptop battery, the mains, or UPower's summary device
            readonly property bool watched: !modelData.isLaptopBattery && modelData.nativePath !== ""
                && modelData.type !== UPowerDeviceType.LinePower && modelData.isPresent
            readonly property string name: modelData.model || "Device"
            property int lastPct: -1
            property int lastState: -1

            function check(): void {
                if (!watched) return;
                const p = root.pct(modelData), st = modelData.state;
                if (lastState >= 0 && st !== lastState) {
                    if (st === UPowerDeviceState.Charging) root.say("battery_charging_full", name + " charging  ·  " + p + "%", "success", 1800);
                    else if (st === UPowerDeviceState.FullyCharged) root.say("battery_full", name + " fully charged", "success", 1800);
                }
                // crossing 20 / 10 / 5 % on the way down
                if (lastPct >= 0 && st !== UPowerDeviceState.Charging)
                    for (const t of [5, 10, 20])
                        if (lastPct > t && p <= t) {
                            root.say("battery_alert", name + " battery low  ·  " + p + "%", t <= 10 ? "error" : "warning", 3000);
                            break;
                        }
                lastPct = p;
                lastState = st;
            }
            readonly property Connections watch: Connections {
                target: dev.modelData
                function onPercentageChanged() { dev.check(); }
                function onStateChanged() { dev.check(); }
            }
            Component.onCompleted: check()
        }
    }

    // ── Bluetooth devices ──
    function btGlyph(icon: string): string {
        if (/audio|head/.test(icon)) return "headphones";
        if (/mouse/.test(icon)) return "mouse";
        if (/keyboard/.test(icon)) return "keyboard";
        if (/phone/.test(icon)) return "smartphone";
        if (/gaming|joystick/.test(icon)) return "sports_esports";
        return "bluetooth";
    }
    Instantiator {
        model: Bluetooth.devices
        delegate: QtObject {
            id: bt
            required property BluetoothDevice modelData
            readonly property Connections watch: Connections {
                target: bt.modelData
                function onConnectedChanged() {
                    const d = bt.modelData;
                    const name = d.name || d.deviceName || "Bluetooth device";
                    if (d.connected) {
                        const batt = d.batteryAvailable ? "  ·  " + Math.round(d.battery <= 1 ? d.battery * 100 : d.battery) + "%" : "";
                        root.say(root.btGlyph(d.icon), name + " connected" + batt, "action", 1800);
                    } else {
                        root.say("bluetooth_disabled", name + " disconnected", "loading", 1500);
                    }
                }
            }
        }
    }

    // ── Do Not Disturb ──
    Connections {
        target: Notifs
        function onDndChanged() {
            root.say(Notifs.dnd ? "do_not_disturb_on" : "notifications", Notifs.dnd ? "Do Not Disturb on" : "Do Not Disturb off", Notifs.dnd ? "warning" : "action", 1400);
        }
    }

    // ── keyboard layout ──
    property string layout: ""
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activelayout") return;
            const name = event.data.slice(event.data.indexOf(",") + 1);
            if (!name || name === root.layout) return;
            const first = root.layout === "";
            root.layout = name;
            if (!first) root.say("keyboard", name, "info", 1400);
        }
    }
}
