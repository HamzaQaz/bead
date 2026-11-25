pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.config
import qs.services

// Discord without its window (services/Discord.qml): a call ringing (Answer),
// the call you're in (Leave), the inbox (DMs and @mentions; click one to open
// it in Discord) and Voice now (busy voice channels in your pinned and recent
// servers; click to join). Voice now is scanned each time the panel opens.
PanelColumn {
    id: root
    property bool active: false
    signal done()
    width: 320
    spacing: 10
    onActiveChanged: if (active) Discord.scanVoice()

    component Label: Text {
        x: 4
        font.family: Theme.font
        font.pixelSize: 11
        font.weight: Font.Bold
        font.letterSpacing: 0.4
        color: Theme.subtext
    }
    component Empty: Text {
        x: 4
        width: root.width - 8
        wrapMode: Text.Wrap
        font.family: Theme.font
        font.pixelSize: 12
        color: Theme.subtext
    }

    PanelHeader {
        icon: "forum"
        title: Discord.state === "ready" ? "Discord"
            : Discord.state === "offline" ? "Discord isn't running"
            : Discord.state === "setup" ? "Discord isn't set up"
            : Discord.state === "authorizing" ? "Allow bead in Discord…"
            : Discord.state === "error" ? "Discord isn't connected" : "Discord"
    }
    // not connected: why, in Discord's or bead's words, and a way to try again
    Empty {
        visible: Discord.state !== "ready" && Discord.state !== ""
        color: Discord.state === "error" || Discord.state === "setup" ? Theme.tone("warning") : Theme.subtext
        text: Discord.detail || (Discord.state === "setup" ? "Run `bead discord setup` in a terminal to connect your Discord." : "")
    }
    Row {
        visible: Discord.state === "error" || Discord.state === "setup" || Discord.state === "offline"
        anchors.right: parent.right
        Action { text: "Try again"; glyph: "refresh"; onHit: Discord.retry() }
    }

    // ── ringing ──
    PanelRow {
        visible: !!Discord.ring
        lit: true
        busy: true
        image: Discord.ring?.avatar ?? ""
        title: (Discord.ring?.name ?? "") + " is calling"
        sub: "Direct call"
        Action { text: "Answer"; glyph: "call"; accent: true; onHit: Discord.answer() }
        Action { glyph: "close"; onHit: Discord.dismiss() }
    }

    // ── in a call ──
    PanelRow {
        visible: Discord.inCall
        lit: true
        icon: Discord.deaf ? "headset_off" : Discord.mute ? "mic_off" : "headset_mic"
        title: Discord.channel?.name ?? ""
        sub: (Discord.channel?.guild ?? "") + " · " + Discord.members.length + (Discord.members.length === 1 ? " person" : " people")
        Action { text: "Leave"; glyph: "call_end"; onHit: Discord.leave() }
    }

    // ── inbox ──
    Label { visible: Discord.state === "ready"; text: "INBOX" }
    Empty {
        visible: Discord.state === "ready" && Discord.dms.length === 0
        color: Discord.quiet ? Theme.tone("warning") : Theme.subtext
        text: Discord.quiet
            ? "Nothing from Discord for hours. Is your status Do Not Disturb? Discord tells bead about messages only when it shows a notification (Settings → Notifications → Enable Desktop Notifications)."
            : "No unread DMs or mentions."
    }
    Repeater {
        model: Discord.dms.slice(0, 6)
        PanelRow {
            required property var modelData
            image: modelData.avatar
            title: modelData.name + (modelData.count > 1 ? "  ·  " + modelData.count : "")
            sub: (modelData.kind === "mention" ? "@ " : "") + (modelData.text || (modelData.kind === "mention" ? "Mentioned you" : "Sent a message"))
            onClicked: { root.done(); Discord.open(modelData); }
            Action { text: "Reply"; glyph: "reply"; onHit: { root.done(); Discord.open(modelData); } }
        }
    }

    // ── voice now ──
    Item {
        visible: Discord.state === "ready"
        width: root.width
        height: 20
        Label { anchors.verticalCenter: parent.verticalCenter; text: "VOICE NOW" }
        Icon {
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            name: "refresh"
            size: 15
            color: Theme.subtext
            RotationAnimation on rotation { running: Discord.scanning; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: Discord.scanVoice() }
        }
    }
    Empty {
        visible: Discord.state === "ready" && !Discord.scanning && Discord.voiceNow.length === 0
        text: "Nobody's in voice in the servers you use."
    }
    Repeater {
        model: Discord.voiceNow.slice(0, 5)
        PanelRow {
            required property var modelData
            image: modelData.people[0]?.avatar ?? ""
            title: modelData.name
            sub: modelData.guild + " · " + modelData.people.map(p => p.name).slice(0, 3).join(", ") + (modelData.count > 3 ? " +" + (modelData.count - 3) : "")
            onClicked: { root.done(); Discord.join(modelData.id); }
        }
    }
}
