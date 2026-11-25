pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// The mixer (Sound → Advanced): every output and input with its level, each
// app's level and where it plays, "Both" (one sound on two outputs, e.g. two
// headphones), and mic effects: noise suppression, an EQ preset, gain, and
// hearing yourself. The extras live in services/AudioFx.qml.
FloatingWindow {
    id: win
    title: "bead Mixer"
    implicitWidth: 860
    implicitHeight: 640
    color: Theme.frame
    visible: true
    onVisibleChanged: if (!visible) AudioFx.open = false

    component Head: Text {
        font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
        font.letterSpacing: 0.4; font.capitalization: Font.AllUppercase
        color: Theme.subtext
    }
    component Line: Text {
        font.family: Theme.font; font.pixelSize: 13
        color: Theme.text
        elide: Text.ElideRight
    }
    component Hint: Text {
        font.family: Theme.font; font.pixelSize: 11
        color: Theme.subtext
        wrapMode: Text.Wrap
    }
    // a device or app: icon, name, level, mute
    component Strip: Item {
        id: st
        property PwNode node
        property string glyph: ""
        property string image: ""
        property string name: ""
        property bool lit: false
        property bool pickable: false
        signal picked()
        default property alias extra: tail.data
        width: parent?.width ?? 0
        height: 52
        Rectangle {
            anchors.fill: parent
            radius: 12
            color: st.lit ? Qt.alpha(Theme.tone("action"), 0.12) : pickMa.containsMouse && st.pickable ? Qt.alpha(Theme.text, 0.05) : "transparent"
            Behavior on color { ColorAnimation { duration: 150 } }
        }
        MouseArea { id: pickMa; anchors.fill: parent; hoverEnabled: true; enabled: st.pickable; cursorShape: Qt.PointingHandCursor; onClicked: st.picked() }
        Item {
            id: ico
            x: 10; width: 30; height: 30
            anchors.verticalCenter: parent.verticalCenter
            Icon { anchors.fill: parent; visible: !st.image; name: st.glyph; size: 20; color: st.lit ? Theme.tone("action") : Theme.text }
            IconImage { anchors.centerIn: parent; visible: !!st.image; implicitSize: 24; source: st.image }
        }
        Column {
            x: 50
            width: parent.width - 50 - tail.width - 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Line { width: parent.width; text: st.name; font.weight: st.lit ? Font.DemiBold : Font.Normal }
            Row {
                width: parent.width
                spacing: 8
                Rectangle {
                    width: 22; height: 22; radius: 11
                    anchors.verticalCenter: parent.verticalCenter
                    color: Qt.alpha(st.node?.audio?.muted ? Theme.neutral : Theme.tone("action"), muteMa.containsMouse ? 0.24 : 0.12)
                    Icon { anchors.centerIn: parent; name: st.node?.audio?.muted ? "volume_off" : "volume_up"; size: 14; fill: 1; color: st.node?.audio?.muted ? Theme.neutral : Theme.tone("action") }
                    MouseArea { id: muteMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (st.node?.audio) st.node.audio.muted = !st.node.audio.muted }
                }
                Slider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 22 - 44 - 16
                    implicitHeight: 14
                    value: st.node?.audio?.muted ? 0 : (st.node?.audio?.volume ?? 0)
                    dim: st.node?.audio?.muted ?? false
                    onMoved: v => Audio.setNodeVolume(st.node, v)
                    onNudged: d => Audio.setNodeVolume(st.node, (st.node?.audio?.volume ?? 0) + d * 0.05)
                }
                Text {
                    width: 44
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    font.family: Theme.font; font.pixelSize: 11; font.features: { "tnum": 1 }
                    color: Theme.subtext
                    text: st.node?.audio?.muted ? "off" : Math.round((st.node?.audio?.volume ?? 0) * 100) + "%"
                }
            }
        }
        Row { id: tail; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; spacing: 6 }
    }
    // a small pill button
    component Chip: Rectangle {
        id: ch
        property string text: ""
        property bool on: false
        signal hit()
        width: chT.implicitWidth + 22; height: 28; radius: 14
        color: on ? Theme.tone("action") : Qt.alpha(Theme.text, chMa.containsMouse ? 0.1 : 0.06)
        Behavior on color { ColorAnimation { duration: 150 } }
        Text { id: chT; anchors.centerIn: parent; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: ch.on ? Theme.frame : Theme.text; text: ch.text }
        MouseArea { id: chMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ch.hit() }
    }
    component Pane: Rectangle {
        default property alias content: col.data
        property alias spacing: col.spacing
        width: parent?.width ?? 0
        height: col.implicitHeight + 28
        radius: 16
        color: Theme.fill
        Column { id: col; x: 14; y: 14; width: parent.width - 28; spacing: 8 }
    }

    readonly property var realSinks: Audio.sinks.filter(n => n.name !== "bead_both")

    Flickable {
        anchors.fill: parent
        anchors.margins: 20
        contentHeight: cols.implicitHeight
        clip: true
        Row {
            id: cols
            width: parent.width
            spacing: 20
            readonly property real cw: (width - spacing) / 2

            // ── left: outputs and apps ──
            Column {
                width: cols.cw
                spacing: 14
                Head { text: "Outputs" }
                Pane {
                    Repeater {
                        model: win.realSinks
                        Strip {
                            required property PwNode modelData
                            node: modelData
                            glyph: Audio.deviceGlyph(modelData, false)
                            name: Audio.deviceName(modelData)
                            lit: modelData === Audio.sink
                            pickable: true
                            onPicked: { if (Settings.audioBoth) AudioFx.setBoth(false); Audio.useSink(modelData); }
                        }
                    }
                }
                // Both: pick two, then on
                Pane {
                    Item {
                        width: parent.width; height: 30
                        Line { anchors.verticalCenter: parent.verticalCenter; text: "Play on two at once"; font.weight: Font.DemiBold }
                        Toggle {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            checked: Settings.audioBoth
                            onToggled: AudioFx.setBoth(!Settings.audioBoth)
                        }
                    }
                    Hint { width: parent.width; text: "Two headphones, or headphones and speakers: the same sound on both. Pick the two:" }
                    Flow {
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: win.realSinks
                            Chip {
                                required property PwNode modelData
                                text: Audio.deviceName(modelData).replace(/ Analog Stereo| Digital Stereo.*/, "")
                                on: Settings.audioBothSinks.includes(modelData.name)
                                onHit: {
                                    let s = Settings.audioBothSinks.filter(x => x !== modelData.name);
                                    if (!on) s = [...s, modelData.name].slice(-2);
                                    Settings.audioBothSinks = s;
                                    if (Settings.audioBoth) AudioFx.applyBoth();
                                }
                            }
                        }
                    }
                    Hint {
                        visible: Settings.audioBoth && !AudioFx.bothSink
                        width: parent.width
                        color: Theme.tone("warning")
                        text: Settings.audioBothSinks.length < 2 ? "Pick two outputs." : "Starting…"
                    }
                }
                Head { text: "Apps"; visible: Audio.playing.length > 0 }
                Pane {
                    visible: Audio.playing.length > 0
                    Repeater {
                        model: Audio.playing.filter(n => n.properties?.["media.name"] !== "bead-monitor")
                        Strip {
                            required property PwNode modelData
                            node: modelData
                            image: Audio.appIcon(modelData)
                            name: Audio.appName(modelData)
                        }
                    }
                }
            }

            // ── right: the mic ──
            Column {
                width: cols.cw
                spacing: 14
                Head { text: "Microphone" }
                Pane {
                    Repeater {
                        model: AudioFx.realSources
                        Strip {
                            required property PwNode modelData
                            node: modelData
                            glyph: Audio.deviceGlyph(modelData, true)
                            name: Audio.deviceName(modelData)
                            lit: modelData.name === AudioFx.micName
                            pickable: true
                            onPicked: { Settings.micSource = modelData.name; if (!AudioFx.effectsOn) Audio.useSource(modelData); }
                        }
                    }
                }
                Head { text: "Mic effects" }
                Pane {
                    spacing: 10
                    Hint {
                        width: parent.width
                        text: AudioFx.effectsOn ? (AudioFx.beadMic ? "On: apps hear \"bead Mic\", your mic with these effects." : "Starting…") : "Off: apps hear your mic as it is."
                        color: AudioFx.effectsOn && AudioFx.beadMic ? Theme.tone("success") : Theme.subtext
                    }
                    Item {
                        width: parent.width; height: 30
                        Line { anchors.verticalCenter: parent.verticalCenter; text: "Noise suppression"; font.weight: Font.DemiBold }
                        Toggle {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            enabled: AudioFx.hasRnnoise
                            checked: Settings.micNoise && AudioFx.hasRnnoise
                            onToggled: Settings.micNoise = !Settings.micNoise
                        }
                    }
                    Hint { visible: !AudioFx.hasRnnoise; width: parent.width; color: Theme.tone("warning"); text: "Needs the noise-suppression-for-voice package." }
                    Row {
                        visible: Settings.micNoise && AudioFx.hasRnnoise
                        width: parent.width
                        spacing: 10
                        Hint { width: 90; anchors.verticalCenter: parent.verticalCenter; text: "Strength " + Settings.micThreshold }
                        Slider {
                            width: parent.width - 100
                            anchors.verticalCenter: parent.verticalCenter
                            implicitHeight: 14
                            value: Settings.micThreshold / 95
                            onMoved: v => Settings.micThreshold = Math.round(Math.max(0, Math.min(95, v * 95)))
                            onNudged: d => Settings.micThreshold = Math.max(0, Math.min(95, Settings.micThreshold + d * 5))
                        }
                    }
                    Line { text: "EQ"; font.weight: Font.DemiBold }
                    Choice {
                        width: parent.width
                        options: [{ v: "off", t: "Off" }, { v: "clear", t: "Clear" }, { v: "warm", t: "Warm" }, { v: "radio", t: "Radio" }]
                        value: Settings.micEq
                        onChose: v => Settings.micEq = v
                    }
                    Row {
                        width: parent.width
                        spacing: 10
                        Hint { width: 90; anchors.verticalCenter: parent.verticalCenter; text: "Boost " + Math.round(Settings.micGain * 100) + "%" }
                        Slider {
                            width: parent.width - 100
                            anchors.verticalCenter: parent.verticalCenter
                            implicitHeight: 14
                            value: (Settings.micGain - 0.5) / 2
                            onMoved: v => Settings.micGain = Math.round((0.5 + v * 2) * 20) / 20
                            onNudged: d => Settings.micGain = Math.max(0.5, Math.min(2.5, Math.round((Settings.micGain + d * 0.05) * 20) / 20))
                        }
                    }
                }
                Pane {
                    Item {
                        width: parent.width; height: 30
                        Line { anchors.verticalCenter: parent.verticalCenter; text: "Hear yourself"; font.weight: Font.DemiBold }
                        Toggle {
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            checked: Settings.micMonitor
                            onToggled: AudioFx.setMonitor(!Settings.micMonitor)
                        }
                    }
                    Hint { width: parent.width; text: "Your mic (with its effects) in what you're listening on. Use headphones, or it'll echo." }
                    Strip { visible: !!AudioFx.monitorStream; node: AudioFx.monitorStream; glyph: "hearing"; name: "Monitor level" }
                }
            }
        }
    }
}
