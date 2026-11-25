pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.SystemTray
import qs.components
import qs.config
import qs.services

// Every tray app. Click opens it, right click its menu, the pin keeps it in
// the bar.
PanelColumn {
    id: root
    width: 248
    spacing: 4
    signal activated(SystemTrayItem item)
    signal menu(SystemTrayItem item, Item at)

    PanelHeader {
        icon: "apps"
        title: "Tray"
        Label { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Theme.caption; text: "pin to keep in the bar" }
    }

    Label {
        x: 4
        visible: SystemTray.items.values.length === 0
        topPadding: 6
        bottomPadding: 6
        text: "Nothing in the tray"
    }

    Repeater {
        model: SystemTray.items
        PanelRow {
            id: row
            required property SystemTrayItem modelData
            readonly property bool pinned: !!modelData && TrayPins.isPinned(modelData.id)
            image: modelData?.icon ?? ""
            // some apps report themselves in lower case ("spotify")
            // modelData goes null for a moment when an app quits
            readonly property string name: modelData?.tooltipTitle || modelData?.title || modelData?.id || ""
            title: name.charAt(0).toUpperCase() + name.slice(1)
            sub: modelData?.title && modelData.title !== title ? modelData.title : ""
            onClicked: e => {
                if (e.button === Qt.RightButton || row.modelData.onlyMenu) root.menu(row.modelData, row);
                else if (e.button === Qt.MiddleButton) row.modelData.secondaryActivate();
                else root.activated(row.modelData);
            }
            Rectangle { // pin
                anchors.verticalCenter: parent.verticalCenter
                width: 26; height: 26; radius: 13
                color: row.pinned ? Qt.alpha(Theme.tone("action"), pinMa.containsMouse ? 0.3 : 0.18)
                    : Qt.alpha(Theme.text, pinMa.containsMouse ? 0.1 : 0)
                Behavior on color { ColorAnimation { duration: 150 } }
                Icon {
                    anchors.centerIn: parent
                    name: "keep"
                    size: 16
                    fill: row.pinned ? 1 : 0
                    rotation: row.pinned ? 0 : 45
                    color: row.pinned ? Theme.tone("action") : Theme.subtext
                    Behavior on rotation { SpringAnimation { spring: 5; damping: 0.3 } }
                }
                MouseArea { id: pinMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: TrayPins.toggle(row.modelData.id) }
            }
        }
    }
}
