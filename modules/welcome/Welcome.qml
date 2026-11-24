pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.config
import qs.services

// The welcome: shown once, the first time bead starts (until
// $XDG_STATE_HOME/bead/welcomed exists). Five steps on one card: hello, a
// wallpaper and how much colour to take from it (the card recolours as you
// pick), size, the keys, done. Enter / → next, ← back, Esc skips.
// `bead welcome` (IPC: welcome open) shows it again.
Scope {
    id: root

    property bool open: false
    property int step: 0
    readonly property int steps: 5
    property string size: String(Settings.scale) // applied at the end: it needs a restart
    property bool murmur: false
    property real ready: 1   // 0 → 1 as the intro hands over: the words and buttons come in

    readonly property string flag: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/bead/welcomed"
    FileView {
        path: root.flag
        printErrors: false
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) firstRun.start(); }
    }
    // let the shell settle (and the wallpaper list arrive) before saying hello
    Timer { id: firstRun; interval: 1400; onTriggered: root.show() }
    Process {
        id: hasMurmur
        command: ["test", "-f", Quickshell.env("HOME") + "/.local/share/bead-models/ggml-base.en.bin"]
        onExited: code => root.murmur = code === 0
    }

    function show(): void { step = 0; size = String(Settings.scale); hasMurmur.running = true; ready = 0; open = true; intro.restart(); }
    function finish(): void {
        open = false;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && : > "$1"', "sh", flag]);
        if (Number(size) !== Settings.scale) {
            Settings.scale = Number(size);
            Quickshell.execDetached(["setsid", "-f", "sh", "-c", 'sleep 0.8; exec "$1" restart', "sh", Quickshell.env("HOME") + "/.local/bin/bead"]);
        }
    }
    function next(): void {
        if (intro.running) { intro.complete(); return; } // a key during the intro: skip to its end
        if (step < steps - 1) step++; else finish();
    }
    function back(): void { if (step > 0) step--; }

    IpcHandler {
        target: "welcome"
        function open(): void { root.show(); }
        function close(): void { root.open = false; }   // without marking it seen
        function step(n: int): void { root.step = Math.max(0, Math.min(root.steps - 1, n)); }
    }

    PanelWindow {
        id: win
        visible: root.open || card.opacity > 0.01
        screen: Quickshell.screens.find(s => s.name === Settings.home) ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "bead-welcome"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle { // the room dims
            anchors.fill: parent
            color: Qt.alpha(Theme.frame, 0.75)
            opacity: root.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 640
            height: 430
            radius: 30
            color: Theme.fill
            border.width: 1
            border.color: Qt.alpha(Theme.text, 0.07)
            opacity: root.open ? 1 : 0
            scale: root.open ? 1 : 0.92
            Behavior on opacity { NumberAnimation { duration: 260 } }
            Behavior on scale { SpringAnimation { spring: 4; damping: 0.36; epsilon: 0.002 } }
            Behavior on color { ColorAnimation { duration: 500 } }

            // ── the backdrop (shaders/intro.frag) ──
            ShaderEffect {
                id: fx
                anchors.fill: parent
                anchors.margins: 1 // the card's border stays visible round it
                property size size: Qt.size(width, height)
                property real time: 0
                property real radius: card.radius - 1
                property real flood: 0
                property real phase: 0
                property color base: card.color
                property color c1: Theme.tone("action")
                property color c2: Theme.tone("info")
                property color c3: Theme.c("secondary", "#9a8fe0")
                fragmentShader: Qt.resolvedUrl("../../shaders/intro.frag.qsb")
                NumberAnimation on time { running: win.visible; from: 0; to: 1000; duration: 1000000; loops: Animation.Infinite }
            }
            // ── the title: "bead." written by hand ──
            Handwriting {
                id: hand
                property real cy: rest
                readonly property real rest: card.height / 2 - 62 // its place on the first step
                height: 84
                property real shift: 0 // sliding off with its page
                x: (card.width - width) / 2 + shift
                y: cy - height / 2
                z: 1
                from: Qt.lighter(Theme.tone("action"), 1.25)
                to: Qt.lighter(Theme.c("secondary", "#9a8fe0"), 1.2)
            }
            // first: the card fills with colour and "bead." is written across
            // its middle, the bead dropping in as the full stop; then the word
            // rises to its place as the title, the colour drains to a glow and
            // the rest comes in
            SequentialAnimation {
                id: intro
                ScriptAction { script: { fx.flood = 1; fx.phase = 0; hand.progress = 0; hand.dot = 0; hand.glow = 0; hand.opacity = 1; hand.shift = 0; hand.height = 150; hand.cy = card.height / 2; } }
                PauseAnimation { duration: 350 }
                NumberAnimation { target: hand; property: "progress"; to: 1; duration: 3000; easing.type: Easing.InOutSine }
                NumberAnimation { target: hand; property: "dot"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                PauseAnimation { duration: 350 }
                ParallelAnimation {
                    NumberAnimation { target: hand; property: "cy"; to: hand.rest; duration: 1000; easing.type: Easing.InOutCubic }
                    NumberAnimation { target: hand; property: "height"; to: 84; duration: 1000; easing.type: Easing.InOutCubic }
                    NumberAnimation { target: fx; property: "flood"; to: 0; duration: 1300; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: hand; property: "glow"; to: 1; duration: 1300; easing.type: Easing.InOutQuad }
                    SequentialAnimation {
                        PauseAnimation { duration: 700 } // the word clears the subtitle first
                        NumberAnimation { target: root; property: "ready"; to: 1; duration: 700; easing.type: Easing.OutCubic }
                    }
                }
            }
            // between steps: the title fades out (and back on the first step),
            // and the lights drift a little, so pages flow into one another
            Connections {
                target: root
                property int was: 0
                function onStepChanged(): void {
                    if (intro.running) intro.complete();
                    stepFx.dir = root.step > was ? 1 : -1;
                    was = root.step;
                    stepFx.restart();
                }
            }
            ParallelAnimation {
                id: stepFx
                property int dir: 1
                // leaving: off with its page, quickly; coming back: in from the side it went
                NumberAnimation { target: hand; property: "opacity"; to: root.step === 0 ? 1 : 0; duration: root.step === 0 ? 420 : 160; easing.type: root.step === 0 ? Easing.OutCubic : Easing.InQuad }
                NumberAnimation { target: hand; property: "shift"; from: root.step === 0 ? -60 * stepFx.dir : hand.shift; to: root.step === 0 ? 0 : -80 * stepFx.dir; duration: root.step === 0 ? 480 : 200; easing.type: root.step === 0 ? Easing.OutQuint : Easing.InQuad }
                NumberAnimation { target: fx; property: "phase"; to: root.step * 1.3; duration: 1100; easing.type: Easing.InOutSine }
            }

            focus: root.open
            Keys.onPressed: e => {
                if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Right) root.next();
                else if (e.key === Qt.Key_Left) root.back();
                else if (e.key === Qt.Key_Escape) root.finish();
                else return;
                e.accepted = true;
            }

            // the strand: a bead per step, the current one drawn out long
            Row {
                opacity: root.ready
                anchors.horizontalCenter: parent.horizontalCenter
                y: 22
                spacing: 6
                Repeater {
                    model: root.steps
                    Rectangle {
                        required property int index
                        width: index === root.step ? 22 : 7
                        height: 7
                        radius: 3.5
                        color: index <= root.step ? Theme.tone("action") : Qt.alpha(Theme.text, 0.15)
                        Behavior on width { SpringAnimation { spring: 5; damping: 0.34; epsilon: 0.2 } }
                        Behavior on color { ColorAnimation { duration: 250 } }
                    }
                }
            }

            // ── the steps: the same glide as the dashboard's tabs ──
            Item {
                id: pages
                x: 40
                y: 52
                width: parent.width - 80
                height: parent.height - 52 - 74
                clip: true

                property int cur: root.step
                property int prev: -1
                property int dir: 1
                property real t: 1
                property real outFrom: 1
                Connections {
                    target: root
                    function onStepChanged(): void {
                        if (root.step === pages.cur) return;
                        pages.outFrom = pages.t;
                        pages.prev = pages.cur;
                        pages.dir = root.step > pages.cur ? 1 : -1;
                        pages.cur = root.step;
                        swap.restart();
                    }
                    function onOpenChanged(): void { if (root.open) { pages.cur = 0; pages.prev = -1; pages.t = 1; } }
                }
                NumberAnimation { id: swap; target: pages; property: "t"; from: 0; to: 1; duration: 480; easing.type: Easing.OutQuint }

                component Page: Item {
                    property int index: 0
                    readonly property bool arriving: index === pages.cur
                    readonly property bool leaving: index === pages.prev && pages.t < 1 && !arriving
                    width: pages.width
                    height: pages.height
                    x: arriving ? pages.dir * 60 * (1 - pages.t) : leaving ? -pages.dir * 40 * pages.t : 0
                    opacity: arriving ? Math.min(1, pages.t * 1.25) : leaving ? pages.outFrom * Math.max(0, 1 - pages.t * 2.4) : 0
                    visible: opacity > 0.01
                    enabled: arriving
                }
                component Heading: Text {
                    width: parent?.width ?? 0
                    font.family: Theme.font
                    font.pixelSize: 24
                    font.weight: Font.DemiBold
                    color: Theme.text
                    wrapMode: Text.WordWrap
                }
                component Body: Text {
                    width: parent?.width ?? 0
                    font.family: Theme.font
                    font.pixelSize: 13
                    lineHeight: 1.25
                    color: Theme.subtext
                    wrapMode: Text.WordWrap
                }

                // 0 · hello
                Page {
                    index: 0
                    Column {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 52 // under the handwritten title
                        width: parent.width
                        spacing: 14
                        Body {
                            opacity: root.ready
                            horizontalAlignment: Text.AlignHCenter
                            text: "A shell for Hyprland, coloured by your wallpaper.\nA few quick choices and you're set: about a minute."
                        }
                    }
                }

                // 1 · wallpaper and colour
                Page {
                    index: 1
                    Column {
                        width: parent.width
                        spacing: 6
                        Heading { text: "Pick a wallpaper" }
                        Body { text: Wallpaper.stills.length ? "bead takes its colours from it: watch this card change." : "" }
                    }
                    Grid {
                        visible: Wallpaper.stills.length > 0
                        y: 74
                        columns: 4
                        spacing: 10
                        Repeater {
                            model: Wallpaper.stills.slice(0, 8)
                            Item {
                                id: thumb
                                required property var modelData
                                readonly property bool chosen: Wallpaper.isCurrent(modelData)
                                width: (pages.width - 30) / 4
                                height: 84
                                scale: tma.pressed ? 0.95 : tma.containsMouse ? 1.03 : 1
                                Behavior on scale { SpringAnimation { spring: 6; damping: 0.3; epsilon: 0.002 } }
                                Rectangle { // the picture, its corners rounded by a mask
                                    id: pic
                                    anchors.fill: parent
                                    anchors.margins: thumb.chosen ? 4 : 0
                                    Behavior on anchors.margins { NumberAnimation { duration: 160 } }
                                    radius: 12
                                    color: Qt.alpha(Theme.text, 0.05)
                                    layer.enabled: true
                                    layer.effect: MultiEffect { maskEnabled: true; maskSource: picMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
                                    Image {
                                        anchors.fill: parent
                                        source: Wallpaper.url(thumb.modelData.path)
                                        sourceSize.width: 240
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                }
                                Rectangle { id: picMask; anchors.fill: pic; radius: 12; visible: false; layer.enabled: true }
                                Rectangle { // the ring round the chosen one
                                    anchors.fill: parent
                                    radius: 15
                                    color: "transparent"
                                    border.width: 2
                                    border.color: Theme.tone("action")
                                    opacity: thumb.chosen ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 160 } }
                                }
                                MouseArea { id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Wallpaper.setStill(thumb.modelData.path) }
                            }
                        }
                    }
                    Column { // no wallpapers yet
                        visible: Wallpaper.stills.length === 0
                        anchors.centerIn: parent
                        spacing: 12
                        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "wallpaper"; size: 40; color: Theme.subtext }
                        Body { width: 380; horizontalAlignment: Text.AlignHCenter; text: "Put a few images in ~/Pictures/Wallpapers and bead will pick its colours from them." }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 8
                            Action { text: "Open the folder"; glyph: "folder_open"; onHit: Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && xdg-open "$1"', "sh", Wallpaper.stillDir]) }
                            Action { text: "Look again"; glyph: "refresh"; onHit: Wallpaper.refresh() }
                        }
                    }
                    Row {
                        anchors.bottom: parent.bottom
                        spacing: 14
                        Text { anchors.verticalCenter: parent.verticalCenter; font.family: Theme.font; font.pixelSize: 12; color: Theme.subtext; text: "Colour" }
                        Choice {
                            anchors.verticalCenter: parent.verticalCenter
                            options: [{ v: "vibrant", t: "Vibrant" }, { v: "muted", t: "Muted" }, { v: "mono", t: "Mono" }]
                            value: Settings.tint
                            onChose: v => Settings.tint = v
                        }
                        Row { // the palette, live
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Repeater {
                                model: [Theme.tone("action"), Theme.text, Theme.subtext, Theme.tone("success"), Theme.tone("warning"), Theme.tone("error")]
                                Rectangle {
                                    required property var modelData
                                    width: 18; height: 18; radius: 9
                                    color: modelData
                                    Behavior on color { ColorAnimation { duration: 500 } }
                                }
                            }
                        }
                    }
                }

                // 2 · size
                Page {
                    index: 2
                    Column {
                        width: parent.width
                        spacing: 6
                        Heading { text: "How big?" }
                        Body { text: "Everything in bead grows or shrinks together. bead restarts once at the end to apply it." }
                    }
                    Item { // a pill at the chosen size, next to the size now
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: 10
                        width: parent.width
                        height: 120
                        Rectangle {
                            anchors.centerIn: parent
                            width: 260; height: 44; radius: 22
                            color: Theme.frame
                            scale: Number(root.size) / Settings.scale
                            Behavior on scale { SpringAnimation { spring: 4; damping: 0.36; epsilon: 0.002 } }
                            Row {
                                anchors.centerIn: parent
                                spacing: 10
                                Icon { anchors.verticalCenter: parent.verticalCenter; name: "music_note"; size: 18; fill: 1; color: Theme.tone("action") }
                                Text { anchors.verticalCenter: parent.verticalCenter; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold; color: Theme.text; text: "The island, at this size" }
                            }
                        }
                    }
                    Choice {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        options: [{ v: "1", t: "100%" }, { v: "1.15", t: "115%" }, { v: "1.35", t: "135%" }, { v: "1.5", t: "150%" }]
                        value: root.size
                        onChose: v => root.size = v
                    }
                }

                // 3 · keys
                Page {
                    index: 3
                    Column {
                        width: parent.width
                        spacing: 6
                        Heading { text: "The keys" }
                        Body { text: "In the launcher, start with > for actions, ; clipboard, : emoji, / files, ? to ask Pearl." }
                    }
                    Grid {
                        y: 78
                        columns: 2
                        columnSpacing: 28
                        rowSpacing: 12
                        Repeater {
                            model: [
                                { k: ["Super"], t: "Launcher" },
                                { k: ["Super", "Tab"], t: "Overview" },
                                { k: ["Super", "K"], t: "Dashboard" },
                                { k: ["Super", "N"], t: "Notifications" },
                                { k: ["Super", "L"], t: "Lock" },
                                { k: ["Super", "V"], t: "Clipboard" },
                                { k: ["Super", "Shift", "S"], t: "Screenshot" },
                                { k: ["Super", "Space"], t: "Voice (hold)", voice: true }
                            ].filter(r => !r.voice || root.murmur)
                            Row {
                                id: keyRow
                                required property var modelData
                                width: (pages.width - 28) / 2
                                spacing: 4
                                Repeater {
                                    model: keyRow.modelData.k
                                    Key { required property string modelData; text: modelData }
                                }
                                Text {
                                    leftPadding: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.family: Theme.font; font.pixelSize: 13
                                    color: Theme.text
                                    text: keyRow.modelData.t
                                }
                            }
                        }
                    }
                }

                // 4 · done
                Page {
                    index: 4
                    Column {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: 12
                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: "check_circle"
                            size: 52
                            fill: root.step === 4 ? 1 : 0
                            color: Theme.tone("success")
                        }
                        Heading { horizontalAlignment: Text.AlignHCenter; text: "You're set" }
                        Body {
                            horizontalAlignment: Text.AlignHCenter
                            text: "Everything here lives in the dashboard's Settings tab, where you can also see this again."
                        }
                    }
                }
            }

            // ── buttons ──
            Item {
                opacity: root.ready
                enabled: root.ready > 0.5
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 24
                height: 30
                Action {
                    visible: root.step < root.steps - 1
                    text: "Skip"
                    onHit: root.finish()
                }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    Action { visible: root.step > 0; text: "Back"; glyph: "arrow_back"; onHit: root.back() }
                    Action {
                        accent: true
                        text: root.step === 0 ? "Let's go" : root.step === root.steps - 1 ? (Number(root.size) !== Settings.scale ? "Done · restart" : "Done") : "Next"
                        glyph: root.step === root.steps - 1 ? "check" : "arrow_forward"
                        onHit: root.next()
                    }
                }
            }
        }
    }
}
