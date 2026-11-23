pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Bluetooth
import qs.components
import qs.config

// Bluetooth: on/off, scanning, devices (connected, then paired, then nearby
// ones with a name). Click connects / disconnects; a new device pairs, is
// trusted and connects.
Column {
    id: root
    property bool active: false // shown: scan while open
    width: 272
    spacing: 6

    readonly property BluetoothAdapter bt: Bluetooth.defaultAdapter
    readonly property var devices: {
        const all = (root.bt?.devices?.values ?? []).filter(d => d.paired || d.deviceName);
        const rank = d => (d.connected ? 2 : 0) + (d.paired ? 1 : 0);
        return all.map((d, i) => ({ d, i }))
            .sort((a, b) => rank(b.d) - rank(a.d) || a.d.name.localeCompare(b.d.name) || a.i - b.i)
            .map(x => x.d).slice(0, 9);
    }

    // look for new devices while the panel is open
    onActiveChanged: scan()
    Connections { target: root.bt; function onEnabledChanged() { root.scan(); } }
    function scan(): void { if (bt && bt.enabled) bt.discovering = active; }

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
                anchors.centerIn: parent
                name: "refresh"
                size: 17
                color: root.bt?.discovering ? Theme.tone("action") : Theme.subtext
                RotationAnimation on rotation {
                    running: !!root.bt?.discovering
                    loops: Animation.Infinite
                    from: 0; to: 360; duration: 1400
                    onRunningChanged: if (!running) parent.rotation = 0
                }
            }
            MouseArea { id: scanMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.bt.discovering = !root.bt.discovering }
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
        model: root.bt?.enabled ? root.devices : []
        PanelRow {
            id: row
            required property BluetoothDevice modelData
            readonly property BluetoothDevice d: modelData
            icon: root.glyph(d.icon)
            title: d.name
            lit: d.connected
            dim: !d.paired && !d.connected
            busy: d.pairing || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting
            sub: d.pairing ? "Pairing…"
                : d.state === BluetoothDeviceState.Connecting ? "Connecting…"
                : d.state === BluetoothDeviceState.Disconnecting ? "Disconnecting…"
                : d.connected ? (d.batteryAvailable ? `Connected · ${Math.round(d.battery * 100)}%` : "Connected")
                : d.paired ? "Paired" : "Tap to pair"
            // freshly paired: trust it and connect
            Connections {
                target: row.d
                function onPairedChanged() { if (row.d.paired) { row.d.trusted = true; row.d.connect(); } }
            }
            onClicked: {
                if (d.connected) d.disconnect();
                else if (d.paired) { d.trusted = true; d.connect(); }
                else if (d.pairing) d.cancelPair();
                else d.pair();
            }
        }
    }
}
