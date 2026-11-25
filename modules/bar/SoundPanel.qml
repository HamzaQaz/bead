pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// Sound: output and mic level (click the icon to mute, scroll anywhere on a
// slider), which device plays and which records, and a level per app.
PanelColumn {
    id: root
    width: 292
    signal done()
    spacing: 8

    // a labelled level: mute button, slider, percent
    component Level: Row {
        id: lv
        property string glyph: ""
        property real value: 0
        property bool muted: false
        signal moved(real v)
        signal nudged(int dir)
        signal muteClicked()
        width: root.width
        spacing: 8
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 15
            color: Qt.alpha(lv.muted ? Theme.neutral : Theme.tone("action"), muteMa.containsMouse ? 0.24 : 0.13)
            Behavior on color { ColorAnimation { duration: 150 } }
            Icon { anchors.fill: parent; name: lv.glyph; ref: "volume_up"; size: 17; fill: 1; color: lv.muted ? Theme.neutral : Theme.tone("action") }
            MouseArea { id: muteMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lv.muteClicked() }
        }
        Slider {
            anchors.verticalCenter: parent.verticalCenter
            width: lv.width - 30 - 34 - lv.spacing * 2
            value: lv.muted ? 0 : lv.value
            dim: lv.muted
            onMoved: v => lv.moved(v)
            onNudged: d => lv.nudged(d)
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            horizontalAlignment: Text.AlignRight
            font.pixelSize: 11
            font.features: { "tnum": 1 }
            color: Theme.text
            text: lv.muted ? "off" : Math.round(lv.value * 100) + "%"
        }
    }
    component Section: Label {
        x: 4
        topPadding: 6
        font.pixelSize: 11
        font.weight: Font.DemiBold
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
    }

    PanelHeader { icon: "volume_up"; title: "Sound" }
    // the full mixer: two outputs at once, mic effects, every app
    Row {
        anchors.right: parent.right
        Action { text: "Advanced"; glyph: "tune"; onHit: { root.done(); AudioFx.open = true; } }
    }

    Level {
        glyph: Audio.levelGlyph(Audio.volume, Audio.muted)
        value: Audio.volume
        muted: Audio.muted
        onMoved: v => Audio.setVolume(v)
        onNudged: d => Audio.setVolume(Audio.volume + d * 0.05)
        onMuteClicked: Audio.toggleMute()
    }
    Level {
        visible: !!Audio.source
        glyph: Audio.micMuted ? "mic_off" : "mic"
        value: Audio.micVolume
        muted: Audio.micMuted
        onMoved: v => Audio.setMicVolume(v)
        onNudged: d => Audio.setMicVolume(Audio.micVolume + d * 0.05)
        onMuteClicked: Audio.toggleMicMute()
    }

    Section { text: "Output"; visible: Audio.sinks.length > 0 }
    Repeater {
        model: Audio.sinks
        PanelRow {
            required property PwNode modelData
            icon: Audio.deviceGlyph(modelData, false)
            title: Audio.deviceName(modelData)
            lit: modelData === Audio.sink
            onClicked: Audio.useSink(modelData)
        }
    }

    Section { text: "Input"; visible: Audio.sources.length > 1 }
    Repeater {
        model: Audio.sources.length > 1 ? Audio.sources : []
        PanelRow {
            required property PwNode modelData
            icon: Audio.deviceGlyph(modelData, true)
            title: Audio.deviceName(modelData)
            lit: modelData === Audio.source
            onClicked: Audio.useSource(modelData)
        }
    }

    Section { text: "Apps"; visible: Audio.playing.length > 0 }
    Repeater {
        model: Audio.playing
        Item {
            id: app
            required property PwNode modelData
            width: root.width
            height: 46
            IconImage {
                id: appIcon
                x: 7
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: 24
                source: Audio.appIcon(app.modelData)
            }
            Column {
                x: 42
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 42 - 4
                spacing: 3
                Row {
                    width: parent.width
                    Text {
                        width: parent.width - pct.width
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: Theme.text
                        text: Audio.appName(app.modelData)
                    }
                    Label {
                        id: pct
                        font.pixelSize: 11
                        font.features: { "tnum": 1 }
                        text: app.modelData.audio?.muted ? "off" : Math.round((app.modelData.audio?.volume ?? 0) * 100) + "%"
                    }
                }
                Slider {
                    width: parent.width
                    implicitHeight: 14
                    value: app.modelData.audio?.muted ? 0 : (app.modelData.audio?.volume ?? 0)
                    dim: app.modelData.audio?.muted ?? false
                    onMoved: v => Audio.setNodeVolume(app.modelData, v)
                    onNudged: d => Audio.setNodeVolume(app.modelData, (app.modelData.audio?.volume ?? 0) + d * 0.05)
                }
            }
        }
    }
}
