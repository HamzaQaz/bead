pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Networking
import qs.components
import qs.config

// Wi-Fi: on/off, the networks in range (connected, then known, then by
// signal). Click to connect or disconnect; a secured network you haven't
// joined asks for its password inline.
Column {
    id: root
    property bool active: false // shown: scan while open
    width: 272
    spacing: 6

    readonly property var dev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var nets: {
        const all = (root.dev?.networks?.values ?? []).filter(n => n.name);
        const rank = n => (n.connected ? 2 : 0) + (n.known ? 1 : 0);
        return all.map((n, i) => ({ n, i }))
            .sort((a, b) => rank(b.n) - rank(a.n) || b.n.signalStrength - a.n.signalStrength || a.i - b.i)
            .map(x => x.n).slice(0, 8);
    }
    property string asking: ""   // network waiting for a password
    property string failed: ""   // last network that failed to connect

    onActiveChanged: { if (!active) { asking = ""; failed = ""; } if (dev) dev.scannerEnabled = active; }

    function strengthIcon(s: real): string {
        return s > 0.75 ? "signal_wifi_4_bar" : s > 0.5 ? "network_wifi_3_bar" : s > 0.25 ? "network_wifi_2_bar" : "network_wifi_1_bar";
    }

    PanelHeader {
        icon: "wifi"
        title: "Wi-Fi"
        Toggle {
            anchors.verticalCenter: parent.verticalCenter
            checked: Networking.wifiEnabled
            onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
        }
    }

    Label {
        x: 4
        visible: !Networking.wifiEnabled || root.nets.length === 0
        topPadding: 6
        bottomPadding: 6
        text: !Networking.wifiEnabled ? "Wi-Fi is off" : !root.dev ? "No Wi-Fi adapter" : "Looking for networks…"
    }

    Repeater {
        model: Networking.wifiEnabled ? root.nets : []
        Column {
            id: item
            required property var modelData
            readonly property var n: modelData
            readonly property bool open: n.security === WifiSecurityType.Open || n.security === WifiSecurityType.Owe
            readonly property bool busy: n.stateChanging || n.state === ConnectionState.Connecting
            width: root.width
            spacing: 4

            Connections {
                target: item.n
                function onConnectionFailed(reason) {
                    if (reason === ConnectionFailReason.NoSecrets) root.asking = item.n.name;
                    else root.failed = item.n.name;
                }
                function onConnectedChanged() { if (item.n.connected && root.failed === item.n.name) root.failed = ""; }
            }

            PanelRow {
                icon: root.strengthIcon(item.n.signalStrength)
                title: item.n.name
                lit: item.n.connected
                busy: item.busy
                sub: item.busy ? "Connecting…"
                    : item.n.connected ? "Connected"
                    : root.failed === item.n.name ? "Couldn't connect"
                    : item.n.known ? "Saved" : ""
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !item.open
                    name: "lock"
                    size: 14
                    color: Theme.subtext
                }
                onClicked: {
                    root.failed = "";
                    if (item.n.connected) item.n.disconnect();
                    else if (item.n.known || item.open) item.n.connect();
                    else { root.asking = root.asking === item.n.name ? "" : item.n.name; }
                }
            }

            // password, when needed
            Rectangle {
                visible: root.asking === item.n.name
                onVisibleChanged: if (visible) pw.forceActiveFocus()
                width: parent.width
                height: 34
                radius: 17
                color: Qt.alpha(Theme.text, 0.06)
                border.width: 1
                border.color: Qt.alpha(Theme.tone("action"), pw.activeFocus ? 0.5 : 0)
                TextInput {
                    id: pw
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 40
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    font.family: Theme.font
                    font.pixelSize: 13
                    color: Theme.text
                    selectionColor: Qt.alpha(Theme.tone("action"), 0.4)
                    clip: true
                    function go(): void {
                        if (!text) return;
                        item.n.connectWithPsk(text);
                        text = "";
                        root.asking = "";
                    }
                    Keys.onReturnPressed: go()
                    Keys.onEnterPressed: go()
                    Keys.onEscapePressed: { text = ""; root.asking = ""; }
                }
                Label {
                    x: 16
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !pw.text && !pw.preeditText
                    text: "Password"
                }
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26; height: 26; radius: 13
                    color: Theme.tone("action")
                    opacity: pw.text ? 1 : 0.4
                    Icon { anchors.centerIn: parent; name: "arrow_forward"; size: 16; color: Theme.frame }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pw.go() }
                }
            }
        }
    }
}
