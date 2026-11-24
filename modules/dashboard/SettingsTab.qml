pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.config
import qs.services

// The dashboard's Settings tab: a way into the Settings window
// (modules/settings). A tile per page; picking one opens the window there
// and puts the dashboard away.
Item {
    id: root

    readonly property var tiles: [
        { id: "wifi", t: "Wi-Fi", g: "wifi" },
        { id: "bluetooth", t: "Bluetooth", g: "bluetooth" },
        { id: "sound", t: "Sound", g: "volume_up" },
        { id: "displays", t: "Displays", g: "monitor" },
        { id: "wallpaper", t: "Wallpaper", g: "wallpaper" },
        { id: "appearance", t: "Appearance", g: "palette" },
        { id: "notifications", t: "Notifications", g: "notifications" },
        { id: "night", t: "Night light", g: "nightlight" },
        { id: "power", t: "Power & idle", g: "bedtime" },
        { id: "assistant", t: "Assistant", g: "graphic_eq" },
        { id: "keyboard", t: "Shortcuts", g: "keyboard" },
        { id: "updates", t: "Updates", g: "system_update" },
        { id: "about", t: "About", g: "info" }
    ]
    function open(page: string): void {
        SettingsApp.show(page);
        Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "dashboard", "close"]);
    }

    Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 760)
        spacing: 18

        Row {
            spacing: 14
            Rectangle {
                width: 44; height: 44; radius: 13
                color: Theme.tone("action")
                Icon { anchors.centerIn: parent; name: "settings"; size: 24; fill: 1; color: Theme.frame }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text { font.family: Theme.font; font.pixelSize: 18; font.weight: Font.Bold; color: Theme.text; text: "Settings" }
                Label { font.pixelSize: 11; text: "Everything bead can change, in its own window" }
            }
        }

        Grid {
            id: grid
            columns: 5
            columnSpacing: 10
            rowSpacing: 10
            readonly property real cw: (parent.width - columnSpacing * (columns - 1)) / columns
            Repeater {
                model: root.tiles
                Rectangle {
                    id: tile
                    required property var modelData
                    readonly property bool focusStop: true   // a stop for the keyboard ring (focusnav.js)
                    readonly property real focusRadius: 14
                    function focusPress(): void { root.open(modelData.id); }
                    width: grid.cw
                    height: 64
                    radius: 14
                    color: Qt.alpha(Theme.text, ma.pressed ? 0.12 : ma.containsMouse ? 0.08 : 0.045)
                    scale: ma.pressed ? 0.97 : 1
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Row {
                        x: 14; anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: tile.modelData.g; size: 20; color: Theme.tone("action") }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: tile.width - 14 - 20 - 10 - 10
                            elide: Text.ElideRight
                            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                            color: Theme.text
                            text: tile.modelData.t
                        }
                    }
                    Rectangle {
                        visible: (tile.modelData.id === "updates" && Updates.count > 0) || (tile.modelData.id === "about" && Release.available)
                        anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 10
                        width: 7; height: 7; radius: 3.5
                        color: Theme.tone("action")
                    }
                    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.open(tile.modelData.id) }
                }
            }
        }

        Label { font.pixelSize: 11; text: "Also: the launcher (type “settings”) or  bead settings [page]" }
    }
}
