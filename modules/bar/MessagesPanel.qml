pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.config
import qs.services

// WhatsApp and Telegram (services/Messengers.qml): unread chats, newest
// first. Click one to open it; Reply types back from here when the app's
// notification can take a reply (else it opens the chat).
PanelColumn {
    id: root
    property bool active: false
    signal done()
    width: 320
    spacing: 10
    property string replying: ""   // the chat id with the box open
    onActiveChanged: if (!active) replying = ""

    PanelHeader { icon: "chat"; title: "Messages" }
    Text {
        visible: Messengers.inbox.length === 0
        x: 4; width: root.width - 8
        wrapMode: Text.Wrap
        font.family: Theme.font; font.pixelSize: Theme.small
        color: Theme.subtext
        text: "Nothing unread. " + Messengers.on.map(a => Messengers.names[a]).join(" and ") + " show here when they send a notification (muted chats don't)."
    }
    Repeater {
        model: Messengers.inbox.slice(0, 8)
        Column {
            id: chat
            required property var modelData
            width: root.width
            spacing: 6
            PanelRow {
                icon: Messengers.glyphs[chat.modelData.app]
                title: chat.modelData.chat + (chat.modelData.count > 1 ? "  ·  " + chat.modelData.count : "")
                sub: Messengers.names[chat.modelData.app] + " · " + (chat.modelData.text || "New message")
                onClicked: { root.done(); Messengers.open(chat.modelData); }
                Action {
                    text: "Reply"; glyph: "reply"
                    onHit: {
                        if (Messengers.canReply(chat.modelData)) root.replying = root.replying === chat.modelData.id ? "" : chat.modelData.id;
                        else { root.done(); Messengers.open(chat.modelData); }
                    }
                }
                Action { glyph: "done"; onHit: Messengers.markRead(chat.modelData) }
            }
            Rectangle {
                visible: root.replying === chat.modelData.id
                onVisibleChanged: if (visible) box.forceActiveFocus()
                width: parent.width
                height: 34
                radius: 17
                color: Qt.alpha(Theme.text, 0.06)
                border.width: 1
                border.color: Qt.alpha(Theme.tone("action"), box.activeFocus ? 0.5 : 0)
                TextInput {
                    TextMenu {}   // right-click: cut, copy, paste
                    id: box
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 40
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.font
                    font.pixelSize: Theme.body
                    color: Theme.text
                    selectionColor: Qt.alpha(Theme.tone("action"), 0.4)
                    clip: true
                    function go(): void {
                        if (!text.trim()) return;
                        if (Messengers.reply(chat.modelData, text.trim())) Osd.toast("send", "Sent to " + chat.modelData.chat, "info", 1800);
                        text = "";
                        root.replying = "";
                    }
                    Keys.onReturnPressed: go()
                    Keys.onEnterPressed: go()
                    Keys.onEscapePressed: { text = ""; root.replying = ""; }
                    Text {
                        visible: !box.text
                        anchors.verticalCenter: parent.verticalCenter
                        font: box.font
                        color: Theme.subtext
                        text: "Reply to " + chat.modelData.chat
                    }
                }
                Icon {
                    anchors.right: parent.right; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    name: "send"; size: 17; color: Theme.tone("action")
                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: box.go() }
                }
            }
        }
    }
    Row {
        visible: Messengers.inbox.length > 1
        anchors.right: parent.right
        Action { text: "Mark all read"; glyph: "done_all"; onHit: Messengers.readAll() }
    }
}
