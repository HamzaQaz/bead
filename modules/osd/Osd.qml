pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs.components
import qs.config
import qs.services

// Volume + brightness panel: a small vertical panel that slides out of the
// right edge of the screen frame (vertically centred) with two sliders side by
// side. It opens when you hover that edge, and on the focused monitor whenever
// volume, mute or brightness changes. Drag or scroll a slider to change it;
// click the speaker to mute.
//
// Volume and mute come from PipeWire (keys, wpctl, apps all show it).
// Brightness is DDC via the Brightness service: `bead brightness up|down`.
Scope {
    id: root

    // ── change-triggered showing (hover is per monitor, below) ──
    property string flashScreen: ""       // monitor that shows it after a change
    property string flashWhat: ""         // volume | brightness | mic: highlighted
    function flash(screenName: string, what: string): void {
        flashScreen = screenName;
        flashWhat = what;
        flashTimer.restart();
    }
    Timer { id: flashTimer; interval: 1600; onTriggered: root.flashScreen = "" }

    readonly property string focusedName: Hyprland.focusedMonitor?.name ?? ""

    // ── audio ──
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.sink, root.source] }
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property bool micMuted: source?.audio?.muted ?? false

    // ignore the initial values PipeWire reports at startup
    property bool ready: false
    Timer { interval: 1500; running: true; onTriggered: root.ready = true }
    onVolumeChanged: if (ready) flash(focusedName, "volume")
    onMutedChanged: if (ready) flash(focusedName, "volume")
    onMicMutedChanged: if (ready) flash(focusedName, "mic")

    function setVolume(v: real): void {
        if (!sink?.audio) return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1.5, Math.round(v * 100) / 100));
    }
    function toggleMute(): void { if (sink?.audio) sink.audio.muted = !sink.audio.muted; }

    // ── brightness ──
    Connections {
        target: Brightness
        function onChanged(screenName: string, value: real) { root.flash(screenName, "brightness"); }
    }
    IpcHandler {
        target: "osd"
        function brightnessUp(): void { Brightness.change(Quickshell.screens.find(s => s.name === root.focusedName), 5); }
        function brightnessDown(): void { Brightness.change(Quickshell.screens.find(s => s.name === root.focusedName), -5); }
    }

    // ── icons (Lucide) ──
    readonly property string speaker: "M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z"
    readonly property string speakerIcon: muted || volume <= 0 ? speaker + " M22 9l-6 6 M16 9l6 6"
        : volume < 0.5 ? speaker + " M16 9a5 5 0 0 1 0 6"
        : speaker + " M16 9a5 5 0 0 1 0 6 M19.364 18.364a9 9 0 0 0 0-12.728"
    readonly property string micOffIcon: "M2 2l20 20 M18.89 13.23A7 7 0 0 0 19 12v-2 M5 10v2a7 7 0 0 0 12 5 M15 9.34V5a3 3 0 0 0-5.68-1.33 M9 9v3a3 3 0 0 0 5.12 2.12 M12 19v3"
    readonly property string sunIcon: "M16 12a4 4 0 1 1-8 0a4 4 0 1 1 8 0 M12 2v2 M12 20v2 M4.93 4.93l1.41 1.41 M17.66 17.66l1.41 1.41 M2 12h2 M20 12h2 M6.34 17.66l-1.41 1.41 M19.07 4.93l-1.41 1.41"

    // ── one vertical slider: a rounded track filling from the bottom, the icon
    // sitting inside the fill, the value shown at the top while it is in focus ──
    component Slider: Item {
        id: sl
        property real value: 0             // 0..1 shown (clamped)
        property string label: ""
        property string icon: ""
        property bool dim: false
        property bool lit: false           // the one that just changed
        signal moved(real v)
        signal nudged(int dir)
        signal iconClicked()

        readonly property color tone: dim ? Theme.neutral : Theme.tone("action")
        readonly property real v: Math.max(0, Math.min(1, value))
        width: 32
        height: 120

        Rectangle { // track
            anchors.fill: parent
            radius: width / 2
            color: Qt.alpha(sl.tone, 0.16)
            Behavior on color { ColorAnimation { duration: 200 } }
        }
        Rectangle { // fill (never smaller than the icon circle)
            anchors.bottom: parent.bottom
            width: parent.width
            radius: width / 2
            height: Math.max(width, parent.height * sl.v)
            color: Qt.alpha(sl.tone, sl.dim ? 0.35 : 1)
            // a real spring: glides after the finger while dragging, overshoots a
            // little and settles when the value jumps (keys, scroll)
            Behavior on height { SpringAnimation { spring: area.pressed ? 9 : 4.5; damping: area.pressed ? 0.45 : 0.26; epsilon: 0.2 } }
            Behavior on color { ColorAnimation { duration: 200 } }
        }
        Text { // value, while it changes or is hovered
            anchors.horizontalCenter: parent.horizontalCenter
            y: 10
            font.family: Theme.font
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            color: sl.v > 0.86 ? Theme.frame : sl.tone
            text: sl.label
            opacity: sl.lit || area.containsMouse || area.pressed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 180 } }
        }
        Shape { // icon, inside the fill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 9
            width: 14; height: 14
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: sl.dim ? sl.tone : Theme.frame
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                scale: Qt.size(14 / 24, 14 / 24)
                PathSvg { path: sl.icon }
            }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            property bool onIcon: false
            function at(y: real): real { return 1 - Math.max(0, Math.min(sl.height, y)) / sl.height; }
            // the bottom circle (the icon) toggles; anywhere else drags
            onPressed: e => { onIcon = e.y > sl.height - sl.width; if (!onIcon) sl.moved(at(e.y)); }
            onPositionChanged: e => { if (pressed && !onIcon) sl.moved(at(e.y)); }
            onReleased: e => { if (onIcon && e.y > sl.height - sl.width) sl.iconClicked(); }
            onWheel: e => sl.nudged(e.angleDelta.y > 0 ? 1 : -1)
        }
    }

    // ── one panel per monitor ──
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData

            readonly property real wallW: Theme.frameThickness / devicePixelRatio
            readonly property bool hasBrightness: Brightness.has(modelData)
            // open: hovered (edge or panel), or this monitor just changed
            property bool hovered: false
            readonly property bool open: hovered || root.flashScreen === modelData.name

            anchors.right: true // vertically centred on the right edge
            implicitWidth: panel.w + wallW + 40
            implicitHeight: panel.h + 60
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "bead-osd"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            // closed: only the frame strip at the edge listens (to open on hover)
            mask: Region { item: win.open ? hit : edge }

            Timer { id: leaveTimer; interval: 350; onTriggered: win.hovered = false }

            Item {
                id: edge
                x: win.width - win.wallW
                y: panel.y
                width: win.wallW
                height: panel.h
                HoverHandler {
                    onHoveredChanged: if (hovered) { leaveTimer.stop(); win.hovered = true; }
                }
            }

            Item {
                id: panel
                readonly property real w: 52
                readonly property real h: win.hasBrightness ? 120 * 2 + 10 + 20 : 120 + 20
                readonly property real r: 22
                readonly property real pad: 24

                Spring { id: enter; to: win.open ? 1 : 0; duration: Motion.dur * 0.7 }
                // how far it is pushed back into the frame (it slides; it never stretches)
                readonly property real slide: (1 - enter.value) * (w + r + 8)
                readonly property real textIn: Math.max(0, Math.min(1, (enter.value - 0.55) / 0.45))

                x: win.width - win.wallW - w
                y: (win.height - h) / 2
                width: w
                height: h
                visible: enter.value > 0.001

                ShaderEffect {
                    x: -panel.pad; y: -panel.pad
                    width: panel.w + win.wallW + panel.pad * 2
                    height: panel.h + panel.pad * 2
                    fragmentShader: Qt.resolvedUrl("../../shaders/goo.frag.qsb")
                    property size size: Qt.size(width, height)
                    // the panel runs into the frame (its right side is hidden there)
                    property vector4d pill: Qt.vector4d(panel.pad + panel.slide, panel.pad, panel.w + panel.r + win.wallW, panel.h)
                    property vector4d body: Qt.vector4d(0, 0, 0, 0)
                    property vector4d wall: Qt.vector4d(panel.pad + panel.w, 0, win.wallW, height)
                    property real radius: panel.r
                    property real goo: 16
                    property color fill: Theme.frame
                    property color shadow: "transparent"
                }

                Item {
                    id: hit
                    x: panel.slide
                    width: panel.w + win.wallW
                    height: panel.h
                    HoverHandler {
                        onHoveredChanged: {
                            if (hovered) { leaveTimer.stop(); win.hovered = true; }
                            else leaveTimer.restart();
                        }
                    }
                }

                Column { // volume on top, brightness below
                    x: (panel.w - width) / 2 + panel.slide
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    opacity: panel.textIn

                    Slider {
                        value: root.muted ? 0 : root.volume
                        label: root.muted ? "off" : Math.round(root.volume * 100)
                        icon: root.flashWhat === "mic" && root.flashScreen === win.modelData.name
                            ? (root.micMuted ? root.micOffIcon : "M12 19v3 M19 10v2a7 7 0 0 1-14 0v-2 M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z")
                            : root.speakerIcon
                        dim: root.muted
                        lit: root.flashScreen === win.modelData.name && root.flashWhat !== "brightness"
                        onMoved: v => root.setVolume(v)
                        onNudged: dir => root.setVolume(root.volume + dir * 0.05)
                        onIconClicked: root.toggleMute()
                    }
                    Slider {
                        visible: win.hasBrightness
                        value: Brightness.values[win.modelData.name] ?? 0.5
                        label: Math.round((Brightness.values[win.modelData.name] ?? 0.5) * 100)
                        icon: root.sunIcon
                        lit: root.flashScreen === win.modelData.name && root.flashWhat === "brightness"
                        onMoved: v => Brightness.set(win.modelData, v)
                        onNudged: dir => Brightness.change(win.modelData, dir * 5)
                    }
                }
            }
        }
    }
}
