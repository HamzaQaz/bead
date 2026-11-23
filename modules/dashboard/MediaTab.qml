pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import qs.components
import qs.config

// Now playing, big: the cover over a blurred, dimmed copy of itself, title,
// artist and album, a seekable progress bar, controls with shuffle/loop, and
// chips to switch between players when several are running.
Item {
    id: root
    property MprisPlayer player
    signal pick(MprisPlayer p)

    Card {
        id: card
        anchors.fill: parent
        clip: true

        // blurred backdrop
        Image {
            id: backdrop
            anchors.fill: parent
            source: root.player?.trackArtUrl ?? ""
            sourceSize: Qt.size(200, 200)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        Rectangle { id: cardMask; anchors.fill: parent; radius: card.radius; visible: false; layer.enabled: true }
        MultiEffect {
            anchors.fill: parent
            source: backdrop
            blurEnabled: true
            blur: 1
            blurMax: 64
            saturation: 0.2
            maskEnabled: true
            maskSource: cardMask
            opacity: backdrop.status === Image.Ready ? 0.45 : 0
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }
        Rectangle { anchors.fill: parent; radius: card.radius; color: Qt.alpha(Theme.frame, 0.35) }

        Row {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 26

            Art {
                id: art
                width: parent.height
                height: parent.height
                radius: 20
                source: root.player?.trackArtUrl ?? ""
                // breathes in a little while paused
                scale: root.player?.isPlaying ? 1 : 0.93
                Behavior on scale { SpringAnimation { spring: 3.5; damping: 0.28; epsilon: 0.002 } }
            }

            Column {
                width: parent.width - art.width - 26
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Row {
                    spacing: 6
                    visible: Mpris.players.values.length > 1
                    Repeater {
                        model: Mpris.players.values
                        Rectangle {
                            id: chip
                            required property MprisPlayer modelData
                            readonly property bool current: modelData === root.player
                            width: chipText.implicitWidth + 20
                            height: 24
                            radius: 12
                            color: Qt.alpha(Theme.text, current ? 0.16 : chipMa.containsMouse ? 0.1 : 0.05)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Label {
                                id: chipText
                                anchors.centerIn: parent
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: chip.current ? Theme.text : Theme.subtext
                                text: chip.modelData.identity
                            }
                            MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pick(chip.modelData) }
                        }
                    }
                }

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 22
                    font.weight: Font.DemiBold
                    color: Theme.text
                    text: root.player?.trackTitle || "Nothing playing"
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 14
                    color: Theme.text
                    opacity: 0.85
                    text: root.player?.trackArtist ?? ""
                }
                Label {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.player?.trackAlbum ?? ""
                }
                Item { width: 1; height: 8 }
                Progress { width: parent.width; player: root.player; barHeight: 5; visible: (root.player?.length ?? 0) > 0 }
                Item { width: 1; height: 4 }
                Controls { anchors.horizontalCenter: parent.horizontalCenter; player: root.player; size: 50; extras: true; visible: root.player !== null }
            }
        }
    }
}
