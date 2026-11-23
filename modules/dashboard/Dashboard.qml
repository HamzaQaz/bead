pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import qs.components
import qs.config
import qs.services

// Dashboard: hover the top edge of the screen and it drops out of the top
// frame at top-center (clean rounded joints; it slides, it never stretches).
// Tabs like Caelestia's: Dashboard, Media, Performance, Weather. Click a tab or
// scroll over the tab bar to switch; content slides between tabs.
// Leaving it closes it. IPC target "dashboard": toggle | open | close | tab <n>.
Scope {
    id: root

    property bool pinned: false            // opened from IPC: stays until closed
    property int tab: 0
    readonly property var tabs: [
        { name: "Dashboard", icon: "dashboard" },
        { name: "Media", icon: "queue_music" },
        { name: "Performance", icon: "monitoring" },
        { name: "Weather", icon: "partly_cloudy_day" }
    ]

    IpcHandler {
        target: "dashboard"
        function toggle(): void { root.pinned = !root.pinned; }
        function open(): void { root.pinned = true; }
        function close(): void { root.pinned = false; }
        function tab(n: int): void { root.tab = Math.max(0, Math.min(root.tabs.length - 1, n)); root.pinned = true; }
    }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    // the playing player, or the one picked on the Media tab
    property MprisPlayer picked: null
    readonly property MprisPlayer player: (picked && Mpris.players.values.includes(picked) ? picked : null)
        ?? Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null

    // live data only while it is visible
    Binding { target: SysStats; property: "active"; value: win.open }
    Connections { target: win; function onOpenChanged() { if (win.open) Weather.refresh(); } }
    // MPRIS doesn't push positions: ask for it while it is visible
    Timer {
        interval: 1000
        repeat: true
        running: win.open && (root.player?.isPlaying ?? false)
        onTriggered: root.player?.positionChanged()
    }

    PanelWindow {
        id: win

        readonly property ShellScreen focused: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        property ShellScreen held: focused
        screen: held

        property bool hovered: false
        readonly property bool open: hovered || root.pinned
        onOpenChanged: if (open && !hovered) held = focused

        readonly property real wallW: Theme.frameThickness / devicePixelRatio
        anchors.top: true // the real top edge, over the frame
        implicitWidth: panel.w + 80
        implicitHeight: panel.h + wallW + 60
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "bead-dashboard"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // closed: only the top frame strip listens (hover opens it)
        mask: Region { item: win.open ? hit : edge }

        Timer { id: leaveTimer; interval: 300; onTriggered: win.hovered = false }

        Item {
            id: edge
            x: panel.x
            width: panel.w
            height: win.wallW
            HoverHandler {
                onHoveredChanged: if (hovered) { leaveTimer.stop(); win.hovered = true; }
            }
        }

        Spring { id: enter; to: win.open ? 1 : 0; duration: Motion.dur * 0.8 }

        Item {
            id: panel
            readonly property real w: 900
            readonly property real h: 340
            readonly property real r: 28
            readonly property real pad: 24
            readonly property real slide: -(1 - enter.value) * (h + win.wallW + r)
            readonly property real textIn: Math.max(0, Math.min(1, (enter.value - 0.5) / 0.5))

            x: (win.width - w) / 2
            y: win.wallW
            width: w
            height: h
            visible: enter.value > 0.001

            ShaderEffect {
                x: -panel.pad
                y: -panel.pad - win.wallW
                width: panel.w + panel.pad * 2
                height: panel.h + win.wallW + panel.pad * 2
                fragmentShader: Qt.resolvedUrl("../../shaders/goo.frag.qsb")
                property size size: Qt.size(width, height)
                property vector4d pill: Qt.vector4d(panel.pad, panel.pad + panel.slide - panel.r, panel.w, panel.h + win.wallW + panel.r)
                property vector4d body: Qt.vector4d(0, 0, 0, 0)
                property vector4d wall: Qt.vector4d(0, 0, width, panel.pad + win.wallW)
                property real radius: panel.r
                property real goo: 16
                property color fill: Theme.frame
                property color shadow: "transparent"
            }

            Item {
                id: hit
                y: -win.wallW
                width: panel.w
                height: panel.h + win.wallW + panel.slide
                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) { leaveTimer.stop(); win.hovered = true; }
                        else leaveTimer.restart();
                    }
                }
            }

            // content: clipped to the panel, so nothing draws over the frame
            Item {
                width: panel.w
                height: panel.h
                clip: true

                Item {
                    y: panel.slide
                    width: panel.w
                    height: panel.h
                    opacity: panel.textIn

                    // ── tab bar ──
                    Item {
                        id: bar
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 12
                        width: tabRow.width
                        height: 38

                        // the highlight pill springs to the current tab
                        Rectangle {
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
                                    width: tbRow.implicitWidth + 32
                                    height: parent.height
                                    Row {
                                        id: tbRow
                                        anchors.centerIn: parent
                                        spacing: 7
                                        Icon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: tb.modelData.icon
                                            size: 19
                                            fill: tb.current ? 1 : 0
                                            color: tb.current ? Theme.text : Theme.subtext
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            font.family: Theme.font
                                            font.pixelSize: 13
                                            font.weight: tb.current ? Font.DemiBold : Font.Medium
                                            color: tb.current ? Theme.text : Theme.subtext
                                            text: tb.modelData.name
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.tab = tb.index
                                    }
                                }
                            }
                        }
                        WheelHandler {
                            onWheel: e => root.tab = Math.max(0, Math.min(root.tabs.length - 1, root.tab + (e.angleDelta.y < 0 ? 1 : -1)))
                        }
                    }

                    // ── pages: each slides in from the side of its tab ──
                    Item {
                        id: pages
                        x: 20
                        y: 64
                        width: panel.w - 40
                        height: panel.h - 64 - 20

                        property real at: root.tab
                        Behavior on at { SpringAnimation { spring: 3.2; damping: 0.34; epsilon: 0.001 } }

                        component Page: Item {
                            id: page
                            property int index: 0
                            readonly property real d: index - pages.at
                            width: pages.width
                            height: pages.height
                            x: d * 70
                            opacity: Math.max(0, 1 - Math.abs(d) * 1.6)
                            scale: 1 - Math.min(0.04, Math.abs(d) * 0.04)
                            visible: opacity > 0.01
                            enabled: Math.abs(d) < 0.5
                        }

                        Page {
                            index: 0
                            DashTab { anchors.fill: parent; clock: clock; player: root.player }
                        }
                        Page {
                            index: 1
                            MediaTab { anchors.fill: parent; player: root.player; onPick: p => root.picked = p }
                        }
                        Page {
                            index: 2
                            PerfTab { anchors.fill: parent }
                        }
                        Page {
                            index: 3
                            WeatherTab { anchors.fill: parent }
                        }
                    }
                }
            }
        }
    }
}
