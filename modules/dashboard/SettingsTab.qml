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

    // 14 tiles, 7 by 2, filling the tab: the pages, and the window itself
    readonly property var all: [{ id: "", t: "All settings", g: "settings", main: true }, ...tiles]
    Grid {
        id: grid
        anchors.fill: parent
        anchors.margins: 4
        columns: 7
        columnSpacing: 10
        rowSpacing: 10
        readonly property real cw: (width - columnSpacing * (columns - 1)) / columns
        readonly property real ch: (height - rowSpacing) / 2
        Repeater {
            model: root.all
            Rectangle {
                id: tile
                required property var modelData
                readonly property bool main: !!modelData.main
                readonly property bool focusStop: true   // a stop for the keyboard ring (focusnav.js)
                readonly property real focusRadius: 16
                function focusPress(): void { root.open(modelData.id); }
                width: grid.cw
                height: grid.ch
                radius: 16
                color: main ? Qt.alpha(Theme.tone("action"), ma.pressed ? 0.3 : ma.containsMouse ? 0.24 : 0.18)
                    : Qt.alpha(Theme.text, ma.pressed ? 0.12 : ma.containsMouse ? 0.08 : 0.045)
                Behavior on color { ColorAnimation { duration: 120 } }
                scale: ma.pressed ? 0.96 : 1
                Behavior on scale { NumberAnimation { duration: 120 } }
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 16
                    spacing: 8
                    Icon { anchors.horizontalCenter: parent.horizontalCenter; name: tile.modelData.g; size: 24; fill: tile.main ? 1 : 0; color: Theme.tone("action") }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        font.family: Theme.font; font.pixelSize: Theme.small; font.weight: tile.main ? Font.Medium : Font.Medium
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
}
