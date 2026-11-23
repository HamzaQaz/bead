pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.components
import qs.config
import qs.services

// The dashboard's insides: a tab bar (springy highlight pill, scroll to switch)
// flanked by volume and brightness sliders, and pages that slide between tabs:
// Dashboard, Media, Performance, Weather, Timers, Wallpapers, Settings.
Item {
    id: root

    required property var clock            // SystemClock
    required property MprisPlayer player
    required property ShellScreen screen   // for its brightness
    property int tab: 0                    // shown tab (owner keeps it)
    signal pick(MprisPlayer p)
    signal select(int tab)

    readonly property var tabs: [
        { name: "Dashboard", icon: "dashboard" },
        { name: "Media", icon: "queue_music" },
        { name: "Performance", icon: "monitoring" },
        { name: "Weather", icon: "partly_cloudy_day" },
        { name: "Timers", icon: "timer" },
        { name: "Wallpapers", icon: "wallpaper" },
        { name: "Settings", icon: "settings" }
    ]

    // ── a small horizontal slider: icon (click) + track (drag / scroll) + value ──
    component QuickSlider: Row {
        id: qs
        property string icon: ""
        property real value: 0
        property bool dim: false
        signal moved(real v)
        signal nudged(int dir)
        signal iconClicked()
        spacing: 8
        height: 38
        readonly property color tone: dim ? Theme.neutral : Theme.tone("action")

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 15
            color: Qt.alpha(qs.tone, iconMa.containsMouse ? 0.22 : 0.12)
            Behavior on color { ColorAnimation { duration: 150 } }
            Icon { anchors.centerIn: parent; name: qs.icon; size: 17; fill: 1; color: qs.tone }
            MouseArea { id: iconMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: qs.iconClicked() }
        }
        Item {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: 110; height: 20
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: area.containsMouse || area.pressed ? 8 : 6
                radius: height / 2
                color: Qt.alpha(qs.tone, 0.16)
                Behavior on height { NumberAnimation { duration: 150 } }
                Rectangle {
                    height: parent.height
                    radius: height / 2
                    width: Math.max(height, parent.width * Math.max(0, Math.min(1, qs.value)))
                    color: qs.tone
                    Behavior on width { SpringAnimation { spring: area.pressed ? 9 : 4.5; damping: area.pressed ? 0.45 : 0.28; epsilon: 0.2 } }
                }
            }
            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                function at(x: real): real { return Math.max(0, Math.min(1, x / width)); }
                onPressed: e => qs.moved(at(e.x))
                onPositionChanged: e => { if (pressed) qs.moved(at(e.x)); }
                onWheel: e => qs.nudged(e.angleDelta.y > 0 ? 1 : -1)
            }
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            font.pixelSize: 11
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
            color: Theme.text
            text: qs.dim ? "off" : Math.round(qs.value * 100)
        }
    }

    // volume, left of the tabs
    QuickSlider {
        x: 22
        y: 12
        icon: Audio.muted || Audio.volume <= 0 ? "volume_off" : Audio.volume < 0.5 ? "volume_down" : "volume_up"
        value: Audio.muted ? 0 : Audio.volume
        dim: Audio.muted
        onMoved: v => Audio.setVolume(v)
        onNudged: dir => Audio.setVolume(Audio.volume + dir * 0.05)
        onIconClicked: Audio.toggleMute()
    }
    // brightness, right of the tabs
    QuickSlider {
        anchors.right: parent.right
        anchors.rightMargin: 22
        y: 12
        visible: Brightness.has(root.screen)
        icon: "light_mode"
        value: Brightness.values[root.screen?.name ?? ""] ?? 0.5
        onMoved: v => Brightness.set(root.screen, v)
        onNudged: dir => Brightness.change(root.screen, dir * 5)
    }

    // ── tab bar ──
    Item {
        id: bar
        anchors.horizontalCenter: parent.horizontalCenter
        y: 12
        width: tabRow.width
        height: 38

        Rectangle { // the highlight pill springs to the current tab
            readonly property Item target: tabRow.children[root.tab] ?? null
            x: target?.x ?? 0
            width: target?.width ?? 0
            height: parent.height
            radius: height / 2
            color: Qt.alpha(Theme.text, 0.09)
            Behavior on x { SpringAnimation { spring: 4; damping: 0.32; epsilon: 0.2 } }
            Behavior on width { SpringAnimation { spring: 4; damping: 0.32; epsilon: 0.2 } }
        }

        Row {
            id: tabRow
            height: parent.height
            Repeater {
                model: root.tabs
                Item {
                    id: tb
                    required property var modelData
                    required property int index
                    readonly property bool current: root.tab === index
                    // only the current tab shows its name; it slides open as you switch
                    width: tbRow.implicitWidth + 24
                    height: parent.height
                    Row {
                        id: tbRow
                        anchors.centerIn: parent
                        spacing: tb.current ? 7 : 0
                        Behavior on spacing { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: tb.modelData.icon
                            size: 19
                            fill: tb.current ? 1 : 0
                            color: tb.current ? Theme.text : Theme.subtext
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        Text {
                            id: tbName
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: Theme.text
                            text: tb.modelData.name
                            clip: true
                            width: tb.current ? implicitWidth : 0
                            opacity: tb.current ? 1 : 0
                            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.select(tb.index)
                    }
                }
            }
        }
        WheelHandler {
            onWheel: e => root.select(Math.max(0, Math.min(root.tabs.length - 1, root.tab + (e.angleDelta.y < 0 ? 1 : -1))))
        }
    }

    // ── pages: only two ever move. Switching tabs, the new page glides in
    // from the side of its tab while the old one drifts the other way and
    // fades out early, however far apart the tabs are (no pages in between
    // flash past). A switch mid-way (scrolling through tabs) takes over from
    // wherever the outgoing page had got to. ──
    Item {
        id: pages
        x: 20
        y: 64
        width: root.width - 40
        height: root.height - 64 - 20

        property int cur: root.tab   // the page arriving (or shown)
        property int prev: -1        // the page leaving
        property int dir: 1          // +1: the new tab is to the right
        property real t: 1           // 0 → 1 over a switch
        property real outFrom: 1     // how visible the leaving page was when it started leaving

        Connections {
            target: root
            function onTabChanged(): void {
                if (root.tab === pages.cur) return;
                pages.outFrom = pages.t;
                pages.prev = pages.cur;
                pages.dir = root.tab > pages.cur ? 1 : -1;
                pages.cur = root.tab;
                swap.restart();
            }
        }
        NumberAnimation { id: swap; target: pages; property: "t"; from: 0; to: 1; duration: 520; easing.type: Easing.OutQuint }

        component Page: Item {
            property int index: 0
            readonly property bool arriving: index === pages.cur
            readonly property bool leaving: index === pages.prev && pages.t < 1 && !arriving
            width: pages.width
            height: pages.height
            x: arriving ? pages.dir * 64 * (1 - pages.t) : leaving ? -pages.dir * 40 * pages.t : 0
            opacity: arriving ? Math.min(1, pages.t * 1.25) : leaving ? pages.outFrom * Math.max(0, 1 - pages.t * 2.4) : 0
            scale: arriving ? 0.975 + 0.025 * pages.t : leaving ? 1 - 0.03 * pages.t : 1
            z: arriving ? 1 : 0
            visible: opacity > 0.01
            enabled: arriving
        }

        Page {
            index: 0
            DashTab { anchors.fill: parent; clock: root.clock; player: root.player }
        }
        Page {
            index: 1
            MediaTab { anchors.fill: parent; player: root.player; onPick: p => root.pick(p) }
        }
        Page {
            index: 2
            PerfTab { anchors.fill: parent }
        }
        Page {
            index: 3
            WeatherTab { anchors.fill: parent }
        }
        Page {
            index: 4
            TimersTab { anchors.fill: parent }
        }
        Page {
            index: 5
            WallpapersTab { anchors.fill: parent }
        }
        Page {
            index: 6
            SettingsTab { anchors.fill: parent }
        }
    }
}
