pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.config
import "../../services/doctor.js" as Doc
import qs.services

// The welcome: shown once, the first time bead starts (until
// $XDG_STATE_HOME/bead/welcomed exists). Six steps on one card: hello, a
// wallpaper and how much colour to take from it (the card recolours as you
// pick), a look (ready-made ones), size, the keys, done. Enter / → next, ← back, Esc skips.
// `bead welcome` (IPC: welcome open) shows it again.
Scope {
    id: root

    property bool open: false
    property int step: 0
    readonly property int steps: 6
    property string size: String(Settings.scale) // applied at the end: it needs a restart
    property bool murmur: false
    property real ready: 1   // 0 → 1 as the intro hands over: the words and buttons come in
    property bool bloomed: true // the intro's shape has become the card

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
        command: ["test", "-f", Paths.models + "/ggml-base.en.bin"]
        onExited: code => root.murmur = code === 0
    }

    function show(): void { step = 0; size = String(Settings.scale); hasMurmur.running = true; ready = 0; bloomed = false; open = true; intro.restart(); }
    function finish(): void {
        open = false;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$(dirname "$1")" && : > "$1"', "sh", flag]);
        if (Number(size) !== Settings.scale) {
            Settings.scale = Number(size);
            Quickshell.execDetached(["setsid", "-f", "sh", "-c", 'sleep 0.8; exec "$1" restart', "sh", Paths.cmd("bead")]);
        }
    }
    function next(): void {
        if (intro.running) { intro.complete(); return; } // a key during the intro: skip to its end
        if (step < steps - 1) step++; else finish();
    }
    function back(): void { if (step > 0) step--; }
    // where the intro ends, however it got there (played out, or skipped)
    function introEnd(): void {
        stage.dark = 0; traced.opacity = 0; morph.opacity = 0; morph.rotation = 0; face.opacity = 0;
        hand.reveal = 1; hand.born = 1; ready = 1; bloomed = true;
    }

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

        // ── the intro's stage (docs/ideas/welcome-intro.md): on black, a bead
        // rises to the top edge, becomes the island's pill, light runs out of it
        // round the screen's frame, the black lifts and the pill blooms into the card ──
        Item {
            id: stage
            anchors.fill: parent
            visible: intro.running || morph.opacity > 0.01
            readonly property real wallW: Theme.frameThickness / win.devicePixelRatio
            readonly property real leftW: wallW + 40 // the bar
            // from the screen, not this item: the window may not have its size
            // yet when the intro starts
            readonly property real sw: win.screen?.width ?? width
            readonly property real sh: win.screen?.height ?? height
            readonly property real cx: sw / 2
            readonly property color accent: Theme.tone("action")
            property real dark: 0     // the black
            property real trace: 0    // 0 → 1: the frame drawn, top, then sides, then bottom
            property real settle: 0   // 0 → 1: the traced light turns into the frame's colour
            function leg(a: real, b: real): real { return Math.max(0, Math.min(1, (trace - a) / (b - a))); }
            function mix(a: color, b: color, t: real): color { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1); }
            // the frame's own colour, with a hairline of light along its inner edge
            component Leg: Rectangle {
                id: leg
                property string inner: "bottom" // which edge faces the screen
                color: Theme.frame
                Rectangle {
                    color: stage.accent
                    opacity: 1 - stage.settle
                    width: leg.inner === "left" || leg.inner === "right" ? 2 : leg.width
                    height: leg.inner === "top" || leg.inner === "bottom" ? 2 : leg.height
                    x: leg.inner === "right" ? leg.width - 2 : 0
                    y: leg.inner === "bottom" ? leg.height - 2 : 0
                    layer.enabled: true
                    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: stage.accent; shadowBlur: 0.6; shadowHorizontalOffset: 0; shadowVerticalOffset: 0 }
                }
            }

            Rectangle { anchors.fill: parent; color: "black"; opacity: stage.dark }

            Item { // the frame, traced
                id: traced
                anchors.fill: parent
                readonly property real t1: stage.leg(0, 0.42)
                readonly property real t2: stage.leg(0.34, 0.76)
                readonly property real t3: stage.leg(0.68, 1)
                Leg { x: stage.cx - width; width: stage.cx * traced.t1; height: stage.wallW; inner: "bottom" }
                Leg { x: stage.cx; width: (stage.sw - stage.cx) * traced.t1; height: stage.wallW; inner: "bottom" }
                Leg { width: stage.leftW; height: stage.sh * traced.t2; inner: "right" }
                Leg { x: stage.sw - stage.wallW; width: stage.wallW; height: stage.sh * traced.t2; inner: "left" }
                Leg { y: stage.sh - stage.wallW; width: stage.cx * traced.t3; height: stage.wallW; inner: "top" }
                Leg { x: stage.sw - width; y: stage.sh - stage.wallW; width: (stage.sw - stage.cx) * traced.t3; height: stage.wallW; inner: "top" }
            }

            Rectangle { // the bead, the pill, the card
                id: morph
                property real glow: 1  // 1 the accent, 0 the island's own colour
                property real toCard: 0 // 0 → 1: the island's colour → the card's
                color: stage.mix(stage.mix(Theme.frame, stage.accent, glow), Theme.fill, toCard)
                border.width: 1
                border.color: Qt.alpha(Theme.text, 0.07 * toCard)
                antialiasing: true
                // a soft halo of its own light while it's the bead
                layer.enabled: glow > 0.01
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Qt.alpha(stage.accent, 0.9 * morph.glow)
                    shadowBlur: 1
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    autoPaddingEnabled: true
                }

                // its face: the bead is alive for a moment. Eyes and a smile in a
                // darker shade of its own colour; they part as it stretches into the pill
                Item {
                    id: face
                    anchors.fill: parent
                    opacity: 0
                    property real blink: 0   // 0 open, 1 shut
                    property real happy: 0   // 0 calm, 1 beaming (eyes squint, the smile widens)
                    property real sx: 0      // where it looks when your cursor isn't near (-1 … 1)
                    readonly property real u: Math.min(width, height)
                    readonly property real spread: Math.max(0, width - height) // wider than tall: the pill
                    readonly property color ink: Qt.darker(stage.accent, 2.8)
                    // it looks at your cursor, if you move it; else where the intro says
                    readonly property real cx: morph.x + morph.width / 2
                    readonly property real cy: morph.y + morph.height / 2
                    property real lx: look.hovered ? Math.max(-1, Math.min(1, (look.point.position.x - cx) / 260)) : sx
                    property real ly: look.hovered ? Math.max(-1, Math.min(1, (look.point.position.y - cy) / 260)) : 0
                    Behavior on lx { SmoothedAnimation { velocity: 7 } }
                    Behavior on ly { SmoothedAnimation { velocity: 7 } }

                    Repeater {
                        model: [-1, 1]
                        Rectangle {
                            required property int modelData
                            width: face.u * 0.13
                            height: Math.max(face.u * 0.025, face.u * 0.2 * (1 - face.blink) * (1 - face.happy * 0.6))
                            radius: width / 2
                            x: face.width / 2 + modelData * (face.u * 0.17 + face.spread * 0.3) - width / 2 + face.lx * face.u * 0.07
                            y: face.height * 0.42 - height / 2 + face.ly * face.u * 0.05
                            color: face.ink
                            antialiasing: true
                        }
                    }
                    Shape { // the smile
                        id: smile
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        readonly property real w: face.u * (0.13 + face.happy * 0.07) + face.spread * 0.08
                        readonly property real y0: face.height * 0.6 + face.ly * face.u * 0.03
                        readonly property real mx: face.width / 2 + face.lx * face.u * 0.05
                        ShapePath {
                            strokeColor: face.ink
                            strokeWidth: Math.max(1.5, face.u * 0.05)
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            startX: smile.mx - smile.w; startY: smile.y0
                            PathQuad { x: smile.mx + smile.w; y: smile.y0; controlX: smile.mx; controlY: smile.y0 + face.u * (0.12 + face.happy * 0.1) }
                        }
                    }
                }
            }
            HoverHandler { id: look; enabled: intro.running }
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
            opacity: root.open && root.bloomed ? 1 : 0
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
                property real gather: 0
                property point target: Qt.point(0.5, 0.5)
                // the intro: an aurora, and a field of dots spreading from the
                // title's full stop with a ripple of light running through it
                property point origin: Qt.point(hand.x - 1 + hand.stop.x, hand.y - 1 + hand.stop.y)
                property real aurora: 0
                property real grid: 0
                property real dots: 0
                property real wave: 0
                fragmentShader: Qt.resolvedUrl("../../shaders/intro.frag.qsb")
                NumberAnimation on time { running: win.visible; from: 0; to: 1000; duration: 1000000; loops: Animation.Infinite }
            }
            // ── the title: "bead." ──
            Wordmark {
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
            // the intro: see the stage above. Any key skips to its end (introEnd)
            SequentialAnimation {
                id: intro
                ScriptAction { script: {
                    fx.flood = 0; fx.gather = 0; fx.phase = 0; fx.aurora = 0; fx.grid = 0; fx.dots = 0; fx.wave = 0;
                    hand.reveal = 0; hand.born = 0; hand.shine = 0; hand.opacity = 1; hand.glow = 1; hand.shift = 0; hand.height = 84; hand.cy = hand.rest;
                    stage.dark = 1; stage.trace = 0; stage.settle = 0; traced.opacity = 1;
                    morph.width = 0; morph.height = 0; morph.radius = 999; // round from the first frame (clamped to half its size) morph.x = stage.cx; morph.y = stage.sh * 0.55;
                    morph.glow = 1; morph.toCard = 0; morph.opacity = 1; morph.rotation = 0;
                    face.opacity = 0; face.blink = 0; face.happy = 0; face.sx = 0;
                } }
                PauseAnimation { duration: 150 }
                // a bead pops into the dark, and it's alive
                ParallelAnimation {
                    NumberAnimation { target: morph; properties: "width,height"; to: 64; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                    NumberAnimation { target: morph; property: "radius"; to: 32; duration: 320 }
                    NumberAnimation { target: morph; property: "x"; to: stage.cx - 32; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                    NumberAnimation { target: morph; property: "y"; to: stage.sh * 0.5 - 32; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                    SequentialAnimation {
                        PauseAnimation { duration: 140 }
                        NumberAnimation { target: face; property: "opacity"; to: 1; duration: 200 }
                    }
                }
                PauseAnimation { duration: 280 }
                // blinks
                NumberAnimation { target: face; property: "blink"; to: 1; duration: 70; easing.type: Easing.InQuad }
                NumberAnimation { target: face; property: "blink"; to: 0; duration: 120; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 180 }
                // looks around (at your cursor, if you move it)
                NumberAnimation { target: face; property: "sx"; to: -1; duration: 240; easing.type: Easing.InOutQuad }
                PauseAnimation { duration: 360 }
                NumberAnimation { target: face; property: "sx"; to: 1; duration: 340; easing.type: Easing.InOutQuad }
                PauseAnimation { duration: 360 }
                NumberAnimation { target: face; property: "sx"; to: 0; duration: 220; easing.type: Easing.InOutQuad }
                NumberAnimation { target: face; property: "blink"; to: 1; duration: 70; easing.type: Easing.InQuad }
                NumberAnimation { target: face; property: "blink"; to: 0; duration: 120; easing.type: Easing.OutQuad }
                // happy: beams, wiggles and hops
                ParallelAnimation {
                    NumberAnimation { target: face; property: "happy"; to: 1; duration: 220; easing.type: Easing.OutBack }
                    SequentialAnimation {
                        NumberAnimation { target: morph; property: "rotation"; to: -14; duration: 110; easing.type: Easing.OutQuad }
                        NumberAnimation { target: morph; property: "rotation"; to: 12; duration: 150; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: morph; property: "rotation"; to: -8; duration: 130; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: morph; property: "rotation"; to: 4; duration: 110; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: morph; property: "rotation"; to: 0; duration: 120; easing.type: Easing.OutQuad }
                    }
                    SequentialAnimation {
                        PauseAnimation { duration: 260 }
                        NumberAnimation { target: morph; property: "y"; to: stage.sh * 0.5 - 32 - 34; duration: 190; easing.type: Easing.OutQuad }
                        NumberAnimation { target: morph; property: "y"; to: stage.sh * 0.5 - 32; duration: 260; easing.type: Easing.OutBounce }
                    }
                }
                PauseAnimation { duration: 140 }
                // a contented yawn: eyes shut, it stretches tall…
                ParallelAnimation {
                    NumberAnimation { target: face; property: "blink"; to: 1; duration: 200 }
                    NumberAnimation { target: face; property: "happy"; to: 0.4; duration: 200 }
                    NumberAnimation { target: morph; property: "height"; to: 84; duration: 300; easing.type: Easing.OutQuad }
                    NumberAnimation { target: morph; property: "width"; to: 54; duration: 300; easing.type: Easing.OutQuad }
                    NumberAnimation { target: morph; property: "x"; to: stage.cx - 27; duration: 300; easing.type: Easing.OutQuad }
                    NumberAnimation { target: morph; property: "y"; to: stage.sh * 0.5 - 52; duration: 300; easing.type: Easing.OutQuad }
                }
                // …and up it goes to the top edge, quicker as it goes, rounding again
                ParallelAnimation {
                    NumberAnimation { target: morph; property: "y"; to: stage.wallW; duration: 460; easing.type: Easing.InCubic }
                    NumberAnimation { target: morph; properties: "width,height"; to: 44; duration: 460; easing.type: Easing.InQuad }
                    NumberAnimation { target: morph; property: "radius"; to: 22; duration: 460 }
                    NumberAnimation { target: morph; property: "x"; to: stage.cx - 22; duration: 460; easing.type: Easing.InQuad }
                }
                // meets it: squashes flat against it
                ParallelAnimation {
                    NumberAnimation { target: morph; property: "height"; to: 24; duration: 110; easing.type: Easing.OutQuad }
                    NumberAnimation { target: morph; property: "width"; to: 50; duration: 110; easing.type: Easing.OutQuad }
                    NumberAnimation { target: morph; property: "x"; to: stage.cx - 25; duration: 110; easing.type: Easing.OutQuad }
                }
                // and spreads into the island's pill; light runs out of it round the frame
                ParallelAnimation {
                    NumberAnimation { target: morph; property: "width"; to: 160; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                    NumberAnimation { target: morph; property: "x"; to: stage.cx - 80; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
                    NumberAnimation { target: morph; property: "height"; to: 34; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                    NumberAnimation { target: morph; property: "radius"; to: 17; duration: 520 }
                    NumberAnimation { target: face; property: "opacity"; to: 0; duration: 380; easing.type: Easing.InQuad }
                    SequentialAnimation {
                        PauseAnimation { duration: 120 }
                        NumberAnimation { target: stage; property: "trace"; to: 1; duration: 820; easing.type: Easing.InOutCubic }
                    }
                }
                // the dark lifts; the light settles into the frame and gives way to it
                ParallelAnimation {
                    NumberAnimation { target: stage; property: "dark"; to: 0; duration: 560; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: stage; property: "settle"; to: 1; duration: 560; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: morph; property: "glow"; to: 0; duration: 560; easing.type: Easing.InOutQuad }
                    SequentialAnimation {
                        PauseAnimation { duration: 300 }
                        NumberAnimation { target: traced; property: "opacity"; to: 0; duration: 380 }
                    }
                }
                // the pill blooms down into the card
                ParallelAnimation {
                    NumberAnimation { target: morph; property: "x"; to: (stage.sw - card.width) / 2; duration: 560; easing.type: Easing.OutQuint }
                    NumberAnimation { target: morph; property: "y"; to: (stage.sh - card.height) / 2; duration: 560; easing.type: Easing.OutQuint }
                    NumberAnimation { target: morph; property: "width"; to: card.width; duration: 560; easing.type: Easing.OutQuint }
                    NumberAnimation { target: morph; property: "height"; to: card.height; duration: 560; easing.type: Easing.OutQuint }
                    NumberAnimation { target: morph; property: "radius"; to: card.radius; duration: 560; easing.type: Easing.OutQuint }
                    NumberAnimation { target: morph; property: "toCard"; to: 1; duration: 420 }
                }
                // the card takes over; "bead." comes into focus on it, then the rest
                ScriptAction { script: root.bloomed = true }
                ParallelAnimation {
                    NumberAnimation { target: morph; property: "opacity"; to: 0; duration: 260 }
                    NumberAnimation { target: hand; property: "reveal"; to: 1; duration: 700; easing.type: Easing.Linear }
                    SequentialAnimation {
                        PauseAnimation { duration: 450 }
                        NumberAnimation { target: hand; property: "born"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                    }
                    SequentialAnimation {
                        PauseAnimation { duration: 350 }
                        NumberAnimation { target: root; property: "ready"; to: 1; duration: 600; easing.type: Easing.OutCubic }
                    }
                }
                onStopped: root.introEnd()
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
                        Body { text: "One of bead's, or your own. bead takes its colours from it: watch this card change." }
                    }
                    // your own while you add them: look again every few seconds on this page
                    Timer { running: root.open && root.step === 1; interval: 3000; repeat: true; onTriggered: Wallpaper.refresh() }
                    Grid {
                        y: 74
                        columns: 4
                        spacing: 10
                        Repeater {
                            // yours first (up to four), then bead's, seven in all; then a way to add more
                            model: [...Wallpaper.own.slice(0, 4), ...Wallpaper.stills.filter(w => w.bead)].slice(0, 7).concat([{ add: true }])
                            Item {
                                id: thumb
                                required property var modelData
                                readonly property bool adder: !!modelData.add
                                readonly property bool chosen: !adder && Wallpaper.isCurrent(modelData)
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
                                        visible: !thumb.adder
                                        source: thumb.adder ? "" : Wallpaper.url(thumb.modelData.path)
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
                                Column { // "add your own": opens the folder; what you put there turns up here
                                    visible: thumb.adder
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "add_photo_alternate"; size: 22; color: Theme.subtext }
                                    Text { anchors.horizontalCenter: parent.horizontalCenter; font.family: Theme.font; font.pixelSize: 11; color: Theme.subtext; text: "Add your own" }
                                }
                                Rectangle { // a dashed-looking edge for the add tile
                                    visible: thumb.adder
                                    anchors.fill: parent
                                    radius: 12
                                    color: "transparent"
                                    border.width: 1
                                    border.color: Qt.alpha(Theme.text, tma.containsMouse ? 0.3 : 0.14)
                                }
                                MouseArea {
                                    id: tma
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (thumb.adder) Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && xdg-open "$1"', "sh", Wallpaper.stillDir]);
                                        else Wallpaper.setStill(thumb.modelData.path);
                                    }
                                }
                            }
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

                // 2 · a look: ready-made ones, applied as you pick (the card shows it)
                Page {
                    id: lookPage
                    index: 2
                    readonly property var looks: [
                        { name: "Vivid", hint: "Bold colour from your wallpaper", glyph: "palette", theme: "wallpaper", tint: "vibrant" },
                        { name: "Soft", hint: "A quieter tint of it", glyph: "water_drop", theme: "wallpaper", tint: "muted" },
                        { name: "Ink", hint: "Greys, with one accent", glyph: "ink_pen", theme: "wallpaper", tint: "mono" },
                        { name: "Sileo", hint: "sileo's own palette, any wallpaper", glyph: "contrast", theme: "sileo", tint: "" }
                    ]
                    Column {
                        width: parent.width
                        spacing: 6
                        Heading { text: "Pick a look" }
                        Body { text: "Each one applies as you tap it. Change it any time in Settings → Appearance." }
                    }
                    Grid {
                        id: lookGrid
                        y: 74
                        columns: 2
                        spacing: 10
                        Repeater {
                            model: lookPage.looks
                            Rectangle {
                                id: look
                                required property var modelData
                                readonly property bool chosen: Settings.theme === modelData.theme && (modelData.theme === "sileo" || Settings.tint === modelData.tint)
                                width: (pages.width - 10) / 2
                                height: 62
                                radius: 16
                                color: lma.containsMouse || chosen ? Qt.alpha(Theme.tone("action"), 0.12) : Qt.alpha(Theme.text, 0.05)
                                border.width: 2
                                border.color: chosen ? Theme.tone("action") : "transparent"
                                Behavior on color { ColorAnimation { duration: 200 } }
                                scale: lma.pressed ? 0.97 : 1
                                Behavior on scale { SpringAnimation { spring: 6; damping: 0.3; epsilon: 0.002 } }
                                Row {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 16
                                    spacing: 12
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 34; height: 34; radius: 17
                                        color: Qt.alpha(Theme.tone("action"), look.chosen ? 0.25 : 0.12)
                                        Icon { anchors.centerIn: parent; name: look.modelData.glyph; size: 18; fill: look.chosen ? 1 : 0; color: Theme.tone("action") }
                                    }
                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2
                                        Text { font.family: Theme.font; font.pixelSize: 14; font.weight: Font.DemiBold; color: Theme.text; text: look.modelData.name }
                                        Text { font.family: Theme.font; font.pixelSize: 11; color: Theme.subtext; text: look.modelData.hint }
                                    }
                                }
                                MouseArea {
                                    id: lma
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Settings.theme = look.modelData.theme;
                                        if (look.modelData.tint) Settings.tint = look.modelData.tint;
                                    }
                                }
                            }
                        }
                    }
                    Row { // the palette it gives, live
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
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

                // 3 · size
                Page {
                    index: 3
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

                // 4 · keys
                Page {
                    index: 4
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

                // 5 · done, after checking what bead needs (bin/bead-doctor)
                Page {
                    id: done
                    index: 5
                    readonly property var missing: Doctor.problems.filter(c => c.need === "core")
                    readonly property bool clear: Doctor.checks.length > 0 && missing.length === 0
                    Connections {
                        target: root
                        function onStepChanged(): void { if (root.step === 5) Doctor.check(); }
                    }
                    Column {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: 12
                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: done.clear ? "check_circle" : "health_and_safety"
                            size: 52
                            fill: root.step === 5 ? 1 : 0
                            color: done.clear ? Theme.tone("success") : Theme.tone("warning")
                        }
                        Heading {
                            horizontalAlignment: Text.AlignHCenter
                            text: !Doctor.checks.length ? "Checking…" : done.clear ? "You're set" : "Almost set"
                        }
                        Body {
                            horizontalAlignment: Text.AlignHCenter
                            text: done.clear
                                ? "Everything here lives in Settings (the launcher, or the dashboard), where you can also see this again."
                                    + (Doctor.problems.length ? " " + Doctor.summary.replace("All set · ", "").replace(/^./, c => c.toUpperCase()) + ": see Settings → About bead." : "")
                                : Doctor.checks.length ? "bead needs a few things this machine doesn't have yet:" : ""
                        }
                        // what's missing, a few by name, and the fix
                        Column {
                            visible: !done.clear && done.missing.length > 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 4
                            Repeater {
                                model: done.missing.slice(0, 4)
                                Text {
                                    required property var modelData
                                    font.family: Theme.font; font.pixelSize: 12
                                    color: Theme.subtext
                                    text: "· " + modelData.what + "  →  " + modelData.fix
                                }
                            }
                            Text {
                                visible: done.missing.length > 4
                                font.family: Theme.font; font.pixelSize: 12
                                color: Theme.subtext
                                text: "and " + (done.missing.length - 4) + " more (bead doctor lists them all)"
                            }
                        }
                        Action {
                            readonly property var pkgs: Doc.packages(Doctor.checks, true)
                            visible: !done.clear && pkgs.length > 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            accent: true
                            text: Doctor.installing ? "Installing…" : "Install " + pkgs.length + (pkgs.length === 1 ? " package" : " packages")
                            glyph: "download"
                            onHit: Doctor.install(pkgs)
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
