pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.config
import qs.services

// The updates waiting (Updates.items): repo, AUR and Flatpak, each with its
// old and new version, and a tag on those after which the computer should be
// restarted. Update runs it all in a terminal (paru, then flatpak), where
// you see and answer everything; Check looks again.
PanelColumn {
    id: root
    property bool active: false
    signal done()
    width: 320
    spacing: 12

    PanelHeader {
        icon: "system_update_alt"
        title: Updates.checking ? "Checking…" : !Updates.checked ? "Not checked yet" : Updates.count === 0 ? "Up to date" : Updates.count + (Updates.count === 1 ? " update" : " updates")
    }
    Text {
        x: 4
        width: parent.width - 8
        visible: Updates.restart
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11
        color: Theme.tone("warning")
        text: "Restart after updating: " + Updates.items.filter(u => u.restart).map(u => u.name).join(", ")
    }

    ListView {
        id: list
        width: parent.width
        height: Math.min(contentHeight, 300)
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: Updates.items
        delegate: Item {
            id: u
            required property var modelData
            width: list.width
            height: 38
            Column {
                x: 10
                width: parent.width - 20 - tags.width
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    color: Theme.text
                    text: u.modelData.name
                }
                Text {
                    width: parent.width
                    elide: Text.ElideMiddle
                    font.family: Theme.font
                    font.pixelSize: 10
                    font.features: { "tnum": 1 }
                    color: Theme.subtext
                    text: u.modelData.from ? u.modelData.from + "  →  " + u.modelData.to : u.modelData.to
                }
            }
            Row {
                id: tags
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                component Tag: Rectangle {
                    property string text: ""
                    property color tone: Theme.subtext
                    width: tt.implicitWidth + 12; height: 18; radius: 9
                    color: Qt.alpha(tone, 0.14)
                    Text { id: tt; anchors.centerIn: parent; font.family: Theme.font; font.pixelSize: 9; font.weight: Font.Medium; color: parent.tone; text: parent.text }
                }
                Tag { visible: u.modelData.restart; text: "restart after"; tone: Theme.tone("warning") }
                Tag { text: u.modelData.source === "repo" ? "repo" : u.modelData.source === "aur" ? "AUR" : "Flatpak" }
            }
        }
    }

    Row {
        anchors.right: parent.right
        spacing: 8
        Action { text: "Check"; glyph: "refresh"; onHit: Updates.check() }
        Action { visible: Updates.count > 0; accent: true; text: "Update"; glyph: "download"; onHit: { root.done(); Updates.update(); } }
    }
}
