pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.config
import qs.services

// Settings (config/Settings.qml, saved to ~/.config/bead/settings.json):
// idle timings, looks, and a few odds and ends. Changes apply at once.
Row {
    id: root
    spacing: 12

    readonly property real colW: (width - 2 * spacing) / 3

    // ── pieces ──
    component Card: Rectangle {
        id: card
        property string title: ""
        property string glyph: ""
        default property alias content: body.data
        width: root.colW
        height: root.height
        radius: 18
        color: Qt.alpha(Theme.text, 0.04)
        Row {
            x: 16; y: 14
            spacing: 8
            Icon { anchors.verticalCenter: parent.verticalCenter; name: card.glyph; size: 18; fill: 1; color: Theme.tone("action") }
            Text { anchors.verticalCenter: parent.verticalCenter; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; text: card.title }
        }
        Column {
            id: body
            x: 16; y: 48
            width: parent.width - 32
            spacing: 4
        }
    }
    // a labelled row with something on the right
    component Line: Item {
        id: line
        property string label: ""
        property string hint: ""
        default property alias trailing: slot.data
        width: parent?.width ?? 0
        height: 38
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - slot.width - 8
            Text { width: parent.width; elide: Text.ElideRight; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium; color: Theme.text; text: line.label }
            Label { visible: line.hint !== ""; width: parent.width; elide: Text.ElideRight; font.pixelSize: 10; text: line.hint }
        }
        Item {
            id: slot
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: childrenRect.width
            height: childrenRect.height
        }
    }
    component Btn: Rectangle {
        id: b
        property string glyph: ""
        signal hit()
        width: 24; height: 24; radius: 12
        color: Qt.alpha(Theme.text, bma.pressed ? 0.16 : bma.containsMouse ? 0.11 : 0.06)
        Icon { anchors.centerIn: parent; name: b.glyph; size: 15; color: Theme.text }
        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.hit() }
    }
    // minutes: −  value  +  (0 shows "Never")
    component Minutes: Row {
        id: mins
        property real value: 0
        signal chose(real v)
        readonly property list<real> stops: [0, 1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120]
        // to the next stop up or down (a value between stops snaps to one)
        function step(d: int): void {
            const next = d > 0 ? stops.find(x => x > value) : [...stops].reverse().find(x => x < value);
            if (next !== undefined) chose(next);
        }
        spacing: 2
        Btn { glyph: "remove"; onHit: mins.step(-1) }
        Text {
            width: 52
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            color: mins.value > 0 ? Theme.text : Theme.subtext
            text: mins.value <= 0 ? "Never" : mins.value < 60 ? mins.value + " min" : (mins.value / 60) + " h"
        }
        Btn { glyph: "add"; onHit: mins.step(1) }
        WheelHandler { onWheel: e => mins.step(e.angleDelta.y > 0 ? 1 : -1) }
    }
    // a segmented choice
    component Choice: Rectangle {
        id: ch
        property list<var> options: []   // { v, t }
        property string value: ""
        signal chose(string v)
        width: seg.width + 4
        height: 26
        radius: 13
        color: Qt.alpha(Theme.text, 0.06)
        Rectangle { // the pill slides to the chosen one
            readonly property Item at: seg.children[ch.options.findIndex(o => o.v === ch.value)] ?? null
            visible: !!at
            x: 2 + (at?.x ?? 0)
            y: 2
            width: at?.width ?? 0
            height: 22
            radius: 11
            color: Theme.tone("action")
            Behavior on x { SpringAnimation { spring: 5; damping: 0.34; epsilon: 0.2 } }
            Behavior on width { SpringAnimation { spring: 5; damping: 0.34; epsilon: 0.2 } }
        }
        Row {
            id: seg
            x: 2; y: 2
            Repeater {
                model: ch.options
                Item {
                    id: opt
                    required property var modelData
                    width: optText.implicitWidth + 18
                    height: 22
                    Text {
                        id: optText
                        anchors.centerIn: parent
                        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                        color: ch.value === opt.modelData.v ? Theme.frame : Theme.text
                        Behavior on color { ColorAnimation { duration: 150 } }
                        text: opt.modelData.t
                    }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ch.chose(opt.modelData.v) }
                }
            }
        }
    }

    // ── idle ──
    Card {
        title: "Idle"
        glyph: "bedtime"
        Line { label: "Lock the screen"; Minutes { value: Settings.lockAfter; onChose: v => Settings.lockAfter = v } }
        Line { label: "Turn the screen off"; Minutes { value: Settings.screenOffAfter; onChose: v => Settings.screenOffAfter = v } }
        Line { label: "Suspend"; Minutes { value: Settings.suspendAfter; onChose: v => Settings.suspendAfter = v } }
        Line {
            label: "Stay awake for media"
            hint: "Nothing happens while audio plays"
            Toggle { checked: Settings.pauseForMedia; onToggled: Settings.pauseForMedia = !Settings.pauseForMedia }
        }
    }

    // ── looks ──
    Card {
        title: "Looks"
        glyph: "palette"
        Line {
            label: "Colours"
            hint: Settings.theme === "sileo" ? "sileo's own palette" : "From the wallpaper"
            Choice {
                options: [{ v: "wallpaper", t: "Wallpaper" }, { v: "sileo", t: "Sileo" }]
                value: Settings.theme
                onChose: v => Settings.theme = v
            }
        }
        Line {
            label: "Window title in the bar"
            Toggle { checked: Settings.showTitle; onToggled: Settings.showTitle = !Settings.showTitle }
        }
        Line {
            label: "Main monitor"
            hint: "Island and lock screen"
            Choice {
                options: Quickshell.screens.map(s => ({ v: s.name, t: s.name }))
                value: Settings.home
                onChose: v => Settings.islandScreen = v
            }
        }
        Line {
            label: "Wallpaper"
            hint: "Pick on the Wallpapers tab"
            Choice {
                options: [{ v: "shuffle", t: "Shuffle" }]
                value: ""
                onChose: Wallpaper.random("all")
            }
        }
    }

    // ── other ──
    Card {
        title: "Other"
        glyph: "tune"
        Line {
            label: "Weather units"
            Choice {
                options: [{ v: "auto", t: "Auto" }, { v: "celsius", t: "°C" }, { v: "fahrenheit", t: "°F" }]
                value: Settings.units
                onChose: v => Settings.units = v
            }
        }
        Line {
            label: "Claude model"
            hint: "Launcher ? asks"
            Choice {
                options: [{ v: "haiku", t: "Haiku" }, { v: "sonnet", t: "Sonnet" }, { v: "opus", t: "Opus" }]
                value: Settings.askModel
                onChose: v => Settings.askModel = v
            }
        }
        Line {
            label: "Keep awake"
            hint: "Never lock, blank or sleep"
            Toggle { checked: Idle.keepAwake; onToggled: Idle.keepAwake = !Idle.keepAwake }
        }
        Line {
            label: "Settings file"
            hint: "~/.config/bead/settings.json"
            Choice {
                options: [{ v: "open", t: "Open" }]
                value: ""
                onChose: Quickshell.execDetached(["xdg-open", (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/bead/settings.json"])
            }
        }
    }
}
