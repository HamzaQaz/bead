pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.config
import qs.services

// Widgets: every widget you've made (Settings → Widgets) as a card. A toggle's
// card flips it; the rest refresh. The pinned ones are also on the island.
Item {
    id: root

    onVisibleChanged: if (visible) Widgets.refresh("")

    // nothing made yet
    Column {
        visible: Widgets.items.length === 0
        anchors.centerIn: parent
        spacing: 10
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "widgets"; size: 36; color: Theme.subtext }
        Label { anchors.horizontalCenter: parent.horizontalCenter; text: "No widgets yet"; font.pixelSize: Theme.title; color: Theme.text }
        Label { anchors.horizontalCenter: parent.horizontalCenter; text: "Keep an eye on a server, a build or a number"; font.pixelSize: Theme.small; color: Theme.subtext }
        Action { anchors.horizontalCenter: parent.horizontalCenter; text: "Make one"; glyph: "add"; accent: true; onHit: SettingsApp.show("widgets") }
    }

    Flickable {
        visible: Widgets.items.length > 0
        anchors.fill: parent
        contentHeight: grid.height + 56
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: head
            width: parent.width
            height: 40
            Label { anchors.verticalCenter: parent.verticalCenter; text: "Widgets · " + Widgets.items.length; font.pixelSize: Theme.body; color: Theme.text; width: parent.width - edit.width }
            Action { id: edit; anchors.verticalCenter: parent.verticalCenter; text: "Edit"; glyph: "tune"; onHit: SettingsApp.show("widgets") }
        }

        Grid {
            id: grid
            y: 48
            width: parent.width
            columns: Math.max(1, Math.floor((width + 12) / 232))
            spacing: 12
            Repeater {
                model: Widgets.items
                delegate: Card {
                    id: card
                    required property var modelData
                    readonly property bool isToggle: modelData.template === "toggle"
                    readonly property color tone: modelData.tone ? Theme.tone(modelData.tone) : Theme.text
                    readonly property bool focusStop: true
                    function focusPress(): void { Widgets.activate(modelData.id); }
                    width: (grid.width - grid.spacing * (grid.columns - 1)) / grid.columns
                    height: 96

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius ?? 16
                        color: Qt.alpha(Theme.text, tap.pressed ? 0.08 : hov.hovered ? 0.04 : 0)
                    }
                    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: tap; onTapped: Widgets.activate(card.modelData.id) }

                    Row {
                        x: 16; y: 14
                        spacing: 8
                        width: parent.width - 32
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: card.modelData.icon; size: 18; fill: 1; color: card.modelData.tone ? card.tone : Theme.subtext }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 26 - (pin.visible ? pin.width + 8 : 0)
                            elide: Text.ElideRight
                            text: card.modelData.label
                            font.pixelSize: Theme.small
                            color: Theme.subtext
                        }
                        Icon { id: pin; visible: card.modelData.pinned; anchors.verticalCenter: parent.verticalCenter; name: "keep"; size: 14; color: Theme.subtext }
                    }
                    RollText {
                        x: 16; y: 42
                        maxWidth: parent.width - 32 - (sw.visible ? sw.width + 8 : 0)
                        rise: 10
                        font.family: Theme.font
                        font.pixelSize: Theme.heading
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        color: card.modelData.tone ? card.tone : Theme.text
                        text: card.modelData.value
                    }
                    Toggle {
                        id: sw
                        visible: card.isToggle
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        y: 46
                        checked: card.modelData.on === true
                        onToggled: Widgets.activate(card.modelData.id)
                    }
                    Label {
                        x: 16
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 10
                        font.pixelSize: Theme.tiny
                        color: Qt.alpha(Theme.subtext, 0.8)
                        text: card.modelData.at ? "every " + (card.modelData.every < 60 ? card.modelData.every + " s" : Math.round(card.modelData.every / 60) + " min") : "checking…"
                    }
                }
            }
        }
    }
}
