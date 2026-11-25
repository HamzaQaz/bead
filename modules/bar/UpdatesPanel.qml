pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.config
import qs.services
import "../../services/history.js" as H

// The updates waiting (Updates.items): repo, AUR and Flatpak, each with its
// old and new version, and a tag on those after which the computer should be
// restarted. Update runs it on the island; Check looks again.
// History: what pacman did, one entry per update (its log), each one undoable
// from the package cache (Updates.rollback), and the versions held back since.
PanelColumn {
    id: root
    property bool active: false
    signal done()
    width: 320
    spacing: 12

    // which list: what's waiting, or what's been done
    property bool showHistory: false
    onActiveChanged: if (active) Updates.refreshHistory()
    Connections { target: Updates; function onHistoryAsked(n: int): void { root.showHistory = true; root.open = n; } }

    PanelHeader {
        icon: root.showHistory ? "history" : "system_update_alt"
        title: root.showHistory ? "Update history"
            : Updates.checking ? "Checking…" : !Updates.checked ? "Not checked yet" : Updates.count === 0 ? "Up to date" : Updates.count + (Updates.count === 1 ? " update" : " updates")
    }
    // Waiting | History
    Rectangle {
        width: parent.width; height: 30; radius: 15
        color: Qt.alpha(Theme.text, 0.06)
        Rectangle {
            width: parent.width / 2 - 4; height: parent.height - 6; radius: height / 2
            y: 3; x: root.showHistory ? parent.width / 2 + 1 : 3
            Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            color: Theme.fill
        }
        Row {
            anchors.fill: parent
            Repeater {
                model: [{ t: "Waiting", h: false }, { t: "History", h: true }]
                Item {
                    id: seg
                    required property var modelData
                    width: parent.width / 2; height: parent.height
                    Text {
                        anchors.centerIn: parent
                        font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                        color: root.showHistory === seg.modelData.h ? Theme.text : Theme.subtext
                        text: seg.modelData.t + (seg.modelData.h && Updates.holds.length ? " · " + Updates.holds.length + " held" : !seg.modelData.h && Updates.count ? " · " + Updates.count : "")
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.showHistory = seg.modelData.h }
                }
            }
        }
    }
    Text {
        x: 4
        width: parent.width - 8
        visible: !root.showHistory && Updates.restart
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 11
        color: Theme.tone("warning")
        text: "Restart after updating: " + Updates.items.filter(u => u.restart).map(u => u.name).join(", ")
    }

    ListView {
        id: list
        visible: !root.showHistory
        width: parent.width
        height: visible ? Math.min(contentHeight, 300) : 0
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

    // ── history ──
    component Small: Rectangle {
        id: sm
        property string text: ""
        property bool accent: false
        signal hit()
        width: st.implicitWidth + 16; height: 22; radius: 11
        color: Qt.alpha(accent ? Theme.tone("action") : Theme.text, sma.containsMouse ? 0.22 : 0.1)
        Behavior on color { ColorAnimation { duration: 120 } }
        Text { id: st; anchors.centerIn: parent; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Medium; color: sm.accent ? Theme.tone("action") : Theme.text; text: sm.text }
        MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: sm.hit() }
    }
    // held back: the versions you rolled back from, skipped until a newer one
    Column {
        visible: root.showHistory && Updates.holds.length > 0
        width: parent.width
        spacing: 4
        Text { x: 4; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium; color: Theme.tone("warning"); text: "Held back: updates skip these versions" }
        Repeater {
            model: Updates.holds
            Item {
                id: hd
                required property var modelData
                width: parent.width; height: 28
                Text {
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 20 - rel.width
                    elide: Text.ElideRight
                    font.family: Theme.font; font.pixelSize: 12; color: Theme.text
                    text: hd.modelData.name + "  <font color=\"" + Theme.subtext + "\">" + hd.modelData.version + "</font>"
                    textFormat: Text.StyledText
                }
                Small { id: rel; anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; text: "Release"; onHit: Updates.release(hd.modelData.name) }
            }
        }
    }
    property int open: -1        // the entry shown open
    property string note: ""     // why an undo can't run
    ListView {
        id: hist
        visible: root.showHistory
        width: parent.width
        height: visible ? Math.min(contentHeight, 360) : 0
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: Updates.history
        delegate: Item {
            id: e
            required property var modelData
            required property int index
            readonly property bool isOpen: root.open === index
            readonly property var plan: isOpen ? Updates.undoPlan(modelData, "") : null
            width: hist.width
            height: head.height + (isOpen ? body.implicitHeight + 6 : 0)
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            clip: true
            Rectangle { anchors.fill: parent; radius: 10; color: Qt.alpha(Theme.text, e.isOpen ? 0.05 : hma.containsMouse ? 0.04 : 0) }
            Item {
                id: head
                width: parent.width; height: 40
                Column {
                    x: 10; anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 20 - cnt.width
                    spacing: 1
                    Text { width: parent.width; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium; color: Theme.text; text: H.label(e.modelData) }
                    Text { width: parent.width; font.family: Theme.font; font.pixelSize: 10; color: Theme.subtext; text: H.when(e.modelData.time) }
                }
                Text {
                    id: cnt
                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.font; font.pixelSize: 10; color: Theme.subtext
                    text: e.modelData.changes.length + (e.modelData.changes.length === 1 ? " package" : " packages") + (e.isOpen ? "  ▴" : "  ▾")
                }
                MouseArea { id: hma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.note = ""; root.open = e.isOpen ? -1 : e.index; } }
            }
            Column {
                id: body
                visible: e.isOpen
                y: head.height
                x: 10; width: parent.width - 20
                spacing: 2
                // first, what undoing it all would do, and the button
                Text {
                    width: parent.width; wrapMode: Text.Wrap
                    topPadding: 2
                    font.family: Theme.font; font.pixelSize: 10; color: Theme.subtext
                    text: !e.plan ? "" : root.note || [
                        e.plan.files.length ? "Undo puts back " + e.plan.files.length + (e.plan.files.length === 1 ? " package" : " packages") + " from the cache" : "Nothing here can be undone from the cache",
                        e.plan.missing.length ? e.plan.missing.length + " no longer cached" : "",
                        e.plan.changed.length ? e.plan.changed.length + " updated again since" : "",
                        e.plan.kept.length ? e.plan.kept.length + " new ones stay installed" : ""
                    ].filter(Boolean).join(" · ")
                }
                Row {
                    visible: !!e.plan && e.plan.files.length > 0
                    topPadding: 4; bottomPadding: 4
                    Small { accent: true; text: "Undo this update"
                        onHit: { const r = Updates.rollback(e.modelData, ""); if (Updates.running) root.done(); else root.note = r; } }
                }
                Repeater {
                    model: e.isOpen ? e.modelData.changes.slice(0, 40) : []
                    Item {
                        id: ch
                        required property var modelData
                        readonly property bool can: e.plan && Updates.undoPlan(e.modelData, ch.modelData.name).files.length > 0
                        width: body.width; height: 24
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - (one.visible ? one.width + 6 : 0)
                            elide: Text.ElideMiddle
                            font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 }
                            color: Theme.text
                            textFormat: Text.StyledText
                            text: ch.modelData.name + "  <font color=\"" + Theme.subtext + "\">" + (ch.modelData.op === "installed" ? "new · " + ch.modelData.to
                                : ch.modelData.op === "removed" ? "removed · " + ch.modelData.from : ch.modelData.from + " → " + ch.modelData.to) + "</font>"
                        }
                        Small { id: one; visible: ch.can; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "Roll back"
                            onHit: { const r = Updates.rollback(e.modelData, ch.modelData.name); if (Updates.running) root.done(); else root.note = r; } }
                    }
                }
                Text {
                    visible: e.modelData.changes.length > 40
                    font.family: Theme.font; font.pixelSize: 10; color: Theme.subtext
                    text: "and " + (e.modelData.changes.length - 40) + " more"
                }
            }
        }
    }
    Text {
        visible: root.showHistory && Updates.history.length === 0
        x: 4; font.family: Theme.font; font.pixelSize: 12; color: Theme.subtext
        text: "No updates in pacman's log yet"
    }

    Row {
        visible: !root.showHistory
        anchors.right: parent.right
        spacing: 8
        Action { text: "Check"; glyph: "refresh"; onHit: Updates.check() }
        Action { visible: Updates.count > 0; accent: true; text: "Update"; glyph: "download"; onHit: { root.done(); Updates.update(); } }
    }
}
