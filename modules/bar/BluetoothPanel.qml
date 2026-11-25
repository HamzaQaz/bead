pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth
import Quickshell.Io
import qs.components
import qs.config
import "bluetooth.js" as Bt
import qs.services
import "../../services/demo.js" as DemoData

// Bluetooth: on/off, scanning, devices (connected, then paired, then nearby
// ones with a name). Click connects / disconnects; a new device pairs, is
// trusted and connects. Pairing goes through bluetoothctl with a one-off
// agent (Quickshell has none, and BlueZ won't pair most devices without one);
// it lives only while bead pairs, so nothing else can pair unasked.
PanelColumn {
    id: root
    property bool active: false // shown: scan while open
    width: 272
    spacing: 6

    readonly property BluetoothAdapter bt: Bluetooth.defaultAdapter
    readonly property var devices: {
        if (Demo.on) return DemoData.bluetooth.map((d, i) => ({
            name: d.name, deviceName: d.name, icon: d.icon, address: "demo-" + i,
            connected: !!d.connected, paired: !!(d.paired || d.connected), trusted: true, pairing: false,
            state: BluetoothDeviceState.Disconnected, batteryAvailable: d.battery !== undefined, battery: (d.battery ?? 0) / 100,
            connect() {}, disconnect() {}
        }));
        const all = (root.bt?.devices?.values ?? []).filter(d => d.paired || d.deviceName);
        const rank = d => (d.connected ? 2 : 0) + (d.paired ? 1 : 0);
        return all.map((d, i) => ({ d, i }))
            .sort((a, b) => rank(b.d) - rank(a.d) || a.d.name.localeCompare(b.d.name) || a.i - b.i)
            .map(x => x.d).slice(0, 9);
    }

    // ── pairing ──
    property string pairingAddr: ""
    property var pairErrors: ({})   // address → why it didn't pair
    function pair(d: var): void {
        if (pairer.running) return;
        const e = Object.assign({}, pairErrors); delete e[d.address]; pairErrors = e;
        pairingAddr = d.address;
        pairer.command = ["bluetoothctl", "--agent", "NoInputNoOutput", "--timeout", "30", "pair", d.address];
        pairer.running = true;
    }
    Process {
        id: pairer
        stdout: StdioCollector {
            onStreamFinished: {
                const why = Bt.pairResult(text);
                if (why) { const e = Object.assign({}, root.pairErrors); e[root.pairingAddr] = why; root.pairErrors = e; }
                root.pairingAddr = "";
            }
        }
    }

    // look for new devices while the panel is open
    onActiveChanged: scan()
    Connections { target: root.bt; function onEnabledChanged() { root.scan(); } }
    function scan(): void { if (bt && bt.enabled) bt.discovering = active; }
    // the refresh button: a fresh scan (the panel is already scanning while open,
    // so a plain toggle would have stopped it)
    function rescan(): void {
        if (!bt || !bt.enabled) return;
        if (bt.discovering) { bt.discovering = false; rescanTimer.restart(); }
        else bt.discovering = true;
    }
    Timer { id: rescanTimer; interval: 400; onTriggered: if (root.bt?.enabled) root.bt.discovering = true }

    function glyph(icon: string): string {
        if (/headset|headphone/.test(icon)) return "headphones";
        if (/audio|speaker/.test(icon)) return "speaker";
        if (/mouse/.test(icon)) return "mouse";
        if (/keyboard/.test(icon)) return "keyboard";
        if (/gaming|joystick/.test(icon)) return "stadia_controller";
        if (/phone/.test(icon)) return "smartphone";
        if (/computer|laptop/.test(icon)) return "computer";
        if (/watch/.test(icon)) return "watch";
        return "bluetooth";
    }

    PanelHeader {
        icon: "bluetooth"
        title: "Bluetooth"
        Rectangle { // scan
            anchors.verticalCenter: parent.verticalCenter
            visible: !!root.bt?.enabled
            width: 26; height: 26; radius: 13
            color: Qt.alpha(Theme.text, scanMa.containsMouse ? 0.1 : 0)
            Icon {
                id: scanIcon
                anchors.centerIn: parent
                name: "refresh"
                ref: "circle" // centre on the arrow's circle, not its ink (the arrowhead skews that), so it spins true
                size: 17
                color: root.bt?.discovering ? Theme.tone("action") : Theme.subtext
                RotationAnimation on rotation {
                    running: !!root.bt?.discovering
                    loops: Animation.Infinite
                    from: 0; to: 360; duration: 1400
                    onRunningChanged: if (!running) scanIcon.rotation = 0
                }
            }
            MouseArea { id: scanMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.rescan() }
        }
        Toggle {
            anchors.verticalCenter: parent.verticalCenter
            checked: !!root.bt?.enabled
            onToggled: if (root.bt) root.bt.enabled = !root.bt.enabled
        }
    }

    Label {
        x: 4
        visible: !root.bt?.enabled || root.devices.length === 0
        topPadding: 6
        bottomPadding: 6
        text: !root.bt ? "No Bluetooth adapter" : !root.bt.enabled ? "Bluetooth is off"
            : root.bt.discovering ? "Looking for devices…" : "No devices yet. Refresh to search."
    }

    Repeater {
        model: root.bt?.enabled || Demo.on ? root.devices : []
        PanelRow {
            id: row
            required property var modelData   // a BluetoothDevice, or demo mode's made-up one
            readonly property var d: modelData
            icon: root.glyph(d.icon)
            title: d.name
            lit: d.connected
            dim: !d.paired && !d.connected
            readonly property bool pairingNow: d.pairing || root.pairingAddr === d.address
            busy: pairingNow || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting
            sub: pairingNow ? "Pairing…"
                : !d.paired && root.pairErrors[d.address] ? root.pairErrors[d.address]
                : d.state === BluetoothDeviceState.Connecting ? "Connecting…"
                : d.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…"
                : d.connected ? (d.batteryAvailable ? `Connected · ${Math.round(d.battery * 100)}%` : "Connected")
                : d.paired ? "Paired" : "Tap to pair"
            // freshly paired: trust it and connect
            Connections {
                target: typeof row.d?.pairedChanged === "function" ? row.d : null   // a real device, not a demo one
                function onPairedChanged() { if (row.d.paired) { row.d.trusted = true; row.d.connect(); } }
            }
            onClicked: {
                if (Demo.on) return;
                if (d.connected) d.disconnect();
                else if (d.paired) { d.trusted = true; d.connect(); }
                else if (row.pairingNow) { pairer.running = false; root.pairingAddr = ""; }
                else root.pair(d);
            }
        }
    }
}
