pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
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
    property string onScreen: ""
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

    // the intro sketches the real bar from a capture of it, so that's taken first,
    // before this covers the screen (a moment; without one it uses placeholders)
    function show(): void {
        onScreen = Hyprland.focusedMonitor?.name ?? "";
        tucked = IslandShape.tucked;   // as it is now, before this covers it
        grab.captureSource = null; grab.captureSource = win.screen; grab.captureFrame();
        grabWait.restart();
    }
    property bool tucked: false
    function begin(): void { grabWait.stop(); step = 0; size = String(Settings.scale); hasMurmur.running = true; ready = 0; bloomed = false; open = true; intro.restart(); }
    Timer { id: grabWait; interval: 250; onTriggered: root.begin() }
    Connections {
        target: grab
        function onHasContentChanged(): void { if (grab.hasContent && grabWait.running) root.begin(); }
    }
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
        // is the intro still playing (tools/reel.sh waits for it)
        function playing(): bool { return intro.running || !root.bloomed; }
    }

    PanelWindow {
        id: win
        visible: root.open || card.opacity > 0.01 || veil.opacity > 0.01
        // the monitor you're on when it opens (else the island's)
        screen: Quickshell.screens.find(s => s.name === root.onScreen) ?? Quickshell.screens.find(s => s.name === Settings.home) ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "bead-welcome"
        WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        ShaderEffect { // the room dims: inside the frame, round the island (shaders/veil.frag)
            id: veil
            anchors.fill: parent
            opacity: root.open ? 1 : 0
            // leaving: the room brightens a little after the card has gone
            Behavior on opacity { NumberAnimation { duration: root.open ? 320 : 620; easing.type: Easing.InOutCubic } }
            fragmentShader: Qt.resolvedUrl("../../shaders/veil.frag.qsb")
            property size size: Qt.size(width, height)
            property vector4d inner: Qt.vector4d(stage.leftW, stage.wallW, stage.sw - stage.leftW - stage.wallW, stage.sh - 2 * stage.wallW)
            property real radius: 25 / win.devicePixelRatio
            property vector4d island: Qt.vector4d(stage.cx - stage.islW / 2, stage.wallW - 17, stage.islW, 51)
            property real fillet: 17 * 0.75
            property color color: Qt.alpha(Theme.frame, 0.75)
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
            // while it glows, the bead is drawn by a shader (shaders/goo.frag): its
            // halo is worked out per pixel, where a layer effect would reallocate
            // its texture on every frame the bead changes size (a stutter)
            readonly property bool goo: morph.glow > 0.01
            // the rise (0 → 1): one value drives where it is, its size and its
            // roundness together, so it moves as one shape on one curve
            property real rise: 0
            property real wob: 0      // the settle: a little damped wobble once it's there
            property rect from: Qt.rect(0, 0, 0, 0)  // where the rise starts
            // the real island's resting width: the bead lands exactly on it
            // the real island's resting width; it can change under the intro (its
            // content does), so the pill glides to it rather than jumping
            property real islW: IslandShape.restW
            Behavior on islW { NumberAnimation { duration: 360; easing.type: Easing.InOutSine } }
            function mix(a: color, b: color, t: real): color { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1); }
            property real lift: 0     // 0 → 1: the dark lifts, a circle spreading from the island
            property real fade: 0     // 0 → 1: the frame's colour layer gives way to the real frame

            // the dark, the frame (bar included) filling with the island's colour
            // as it flows out from it, settling and fading into the real frame,
            // and the dark lifting (shaders/trace.frag): one pass
            ShaderEffect {
                id: traced
                anchors.fill: parent
                visible: stage.dark > 0.001
                fragmentShader: Qt.resolvedUrl("../../shaders/trace.frag.qsb")
                property size size: Qt.size(width, height)
                property vector4d inner: Qt.vector4d(stage.leftW, stage.wallW, stage.sw - stage.leftW - stage.wallW, stage.sh - 2 * stage.wallW)
                property real radius: 25 / win.devicePixelRatio // the frame's inner corners (Bar.qml)
                property real trace: stage.trace
                property real settle: stage.settle
                property real dark: stage.dark
                property real lift: stage.lift
                property real fade: stage.fade
                property point origin: Qt.point(stage.cx, stage.wallW + 17)
                property real span: stage.islW / 2 + 17 * 0.75
                property color accent: stage.accent
                property color frame: Theme.frame
            }

            // the real bar, captured as the intro starts: drawn by shaders/sketch.frag
            ScreencopyView {
                id: grab
                anchors.fill: parent
                live: false
                visible: false
            }
            ShaderEffect {
                anchors.fill: parent
                visible: grab.hasContent && stage.dark > 0.001
                z: 1 // over the bead's pill, which it takes over once it's landed
                fragmentShader: Qt.resolvedUrl("../../shaders/sketch.frag.qsb")
                property var src: ShaderEffectSource { sourceItem: grab; hideSource: true; textureSize: grab.sourceSize }
                property size size: Qt.size(width, height)
                property real barW: stage.leftW
                property real wallW: stage.wallW
                property real aL: sketch.aL
                property real trace: stage.trace
                property real settle: stage.settle
                property vector4d pill: Qt.vector4d(morph.x, morph.y, morph.width, morph.height)
                property real radius: morph.radius
                property real fillet: 17 * 0.75
                property real island: stage.trace > 0 && !root.tucked ? 1 : 0
                property color accent: stage.accent
                property color ink: sketch.ink0
                property color frame: Theme.frame
                property color text: Theme.text
            }

            // the bar, sketched (when there's no capture): placeholders the left comet draws in as it passes,
            // each giving way to the real bar as the lifting dark reaches it
            Item {
                id: sketch
                anchors.fill: parent
                opacity: grab.hasContent ? 0 : 1
                visible: stage.dark > 0.001
                readonly property real bx: 27 / win.devicePixelRatio   // the bar's middle
                readonly property real aL: Math.max(stage.cx - stage.leftW - stage.islW / 2 - 17 * 0.75, 1)
                readonly property real far: Math.hypot(stage.sw, stage.sh) * 1.1
                // where y is along the left comet's path (shaders/trace.frag: along())
                function at(y: real): real { return (aL + (y - stage.wallW)) / (2 * aL + stage.sh - 2 * stage.wallW); }
                // the bar's layout (Bar.qml), measured in screen pixels at 1080 high
                // (negative y counts from the bottom): [y, height, width, kind, glyph]
                // shapes are [top, h, w]; glyphs and text are [centre, size]
                readonly property real k: 1 / win.devicePixelRatio
                // the time, read again each time the intro starts (the dark comes on)
                readonly property string hh: stage.dark > 0.5 ? Qt.formatTime(new Date(), "HH") : ""
                readonly property string mm: stage.dark > 0.5 ? Qt.formatTime(new Date(), "mm") : ""
                readonly property var parts: [
                    [37, 24, 0, "logo"],
                    [65, 248, 37, "group"],
                    [85, 15, 0, "icon", "crop_square", "text"], [110, 15, 0, "icon", "web_asset", "text"], [142, 15, 0, "icon", "crop_square", "text"], [167, 15, 0, "icon", "build", "text"],
                    [182, 60, 31, "lit"], [200, 17, 0, "icon", "change_history", "dark"], [225, 17, 0, "icon", "terminal", "dark"],
                    [257, 6, 6, "dot"], [290, 6, 6, "dot"],
                    [-410, 155, 37, "group"],
                    [-389, 18, 0, "icon", "radio_button_checked", "error"], [-353, 18, 0, "icon", "apps"], [-315, 18, 0, "icon", "circle", "success"], [-277, 18, 0, "icon", "signal_wifi_off"],
                    [-248, 63, 37, "group"], [-230, 17, 0, "hh"], [-215, 3, 3, "dot", -3], [-215, 3, 3, "dot", 3], [-200, 17, 0, "mm"],
                    [-170, 105, 37, "group"],
                    [-155, 18, 0, "icon", "volume_up"], [-118, 18, 0, "icon", "wifi"], [-82, 18, 0, "icon", "bluetooth"],
                    [-35, 20, 0, "icon", "power_settings_new"]
                ]
                // ink: a deeper shade of the flowing colour, like the bead's face;
                // each piece turns into the bar's own colours as it settles
                readonly property color ink0: Qt.darker(stage.accent, 2.6)
                readonly property color ink: stage.mix(ink0, stage.mix(Theme.frame, Theme.text, 0.6), stage.settle)
                // what a piece settles into: the real bar's colour for it
                function settled(k: string): color {
                    return k === "text" ? Theme.text : k === "dark" ? Theme.frame
                        : k === "error" ? Theme.tone("error") : k === "success" ? stage.mix(Theme.frame, Theme.tone("success"), 0.45)
                        : stage.mix(Theme.frame, Theme.text, 0.75);
                }
                Repeater {
                    model: sketch.parts
                    Item {
                        id: piece
                        required property var modelData
                        readonly property string kind: modelData[3]
                        readonly property bool shape: kind === "group" || kind === "lit" || kind === "dot"
                        readonly property real at: modelData[0] >= 0 ? modelData[0] * sketch.k : stage.sh + modelData[0] * sketch.k
                        readonly property real cy: shape ? at + height / 2 : at
                        property real pop: stage.trace >= sketch.at(cy) ? 1 : 0
                        Behavior on pop { NumberAnimation { duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
                        width: shape ? modelData[2] * sketch.k : 30 * sketch.k
                        height: modelData[1] * sketch.k
                        // a dot's fifth entry nudges it sideways (the clock's two)
                        x: sketch.bx - width / 2 + (kind === "dot" ? (modelData[4] ?? 0) * sketch.k : 0)
                        y: shape ? at : at - height / 2
                        scale: 0.5 + 0.5 * Math.min(pop, 1.15)
                        opacity: Math.max(0, Math.min(1, pop)) * (1 - stage.fade)
                        Rectangle {
                            visible: piece.shape
                            anchors.fill: parent
                            radius: Math.min(width, height) / 2
                            color: piece.kind === "group" ? stage.mix(Qt.darker(stage.accent, 1.14), Qt.lighter(Theme.frame, 1.75), stage.settle)
                                : piece.kind === "lit" ? stage.mix(Qt.lighter(stage.accent, 1.18), stage.accent, stage.settle)
                                : sketch.ink
                        }
                        Icon {
                            visible: piece.kind === "icon"
                            anchors.centerIn: parent
                            name: piece.modelData[4] ?? ""
                            size: piece.height
                            fill: 1
                            color: stage.mix(sketch.ink0, sketch.settled(piece.modelData[5] ?? ""), stage.settle)
                        }
                        Text {
                            visible: piece.kind === "logo" || piece.kind === "hh" || piece.kind === "mm"
                            anchors.centerIn: parent
                            text: piece.kind === "logo" ? "b." : piece.kind === "hh" ? sketch.hh : sketch.mm
                            font.family: Theme.font
                            font.pixelSize: piece.height
                            font.weight: piece.kind === "logo" ? Font.Black : piece.kind === "hh" ? Font.Bold : Font.Normal
                            color: piece.kind === "logo" ? stage.mix(Qt.darker(stage.accent, 2.6), stage.accent, stage.settle) : sketch.ink
                        }
                    }
                }
            }

            ShaderEffect { // the bead and its halo, while it glows
                anchors.fill: parent
                visible: stage.goo && morph.width > 0
                opacity: morph.opacity
                // joins the frame's top edge like the island does (shaders/rise.frag)
                fragmentShader: Qt.resolvedUrl("../../shaders/rise.frag.qsb")
                property size size: Qt.size(width, height)
                property vector4d pill: Qt.vector4d(morph.x, morph.y, morph.width, morph.height)
                property real radius: morph.radius
                property real fillet: 17 * 0.75   // the island's (Island.qml: radius 17, fillets ¾ of it)
                property real wallH: stage.wallW
                property color fill: stage.mix(Theme.frame, stage.accent, morph.glow)
                property color glow: Qt.alpha(stage.accent, 0.6 * morph.glow)
            }

            Rectangle { // the bead, the pill, the card
                id: morph
                property real glow: 1  // 1 the accent, 0 the island's own colour
                property real toCard: 0 // 0 → 1: the island's colour → the card's
                color: stage.goo ? "transparent" : stage.mix(stage.mix(Theme.frame, stage.accent, glow), Theme.fill, toCard)
                border.width: 1
                border.color: Qt.alpha(Theme.text, 0.07 * toCard)
                antialiasing: true
                // (its halo while it glows: the ShaderEffect above)

                // its face: the bead is alive for a moment. Eyes and a smile in a
                // darker shade of its own colour; they part as it stretches into the pill
                Item {
                    id: face
                    anchors.fill: parent
                    opacity: 0
                    property real blink: 0   // 0 open, 1 shut
                    property real happy: 0   // 0 calm, 1 beaming (eyes squint, the smile widens)
                    property real sx: 0      // where it looks when your cursor isn't near (-1 … 1)
                    property real sy: 0      // and up or down
                    readonly property real u: Math.min(width, height)
                    readonly property real spread: Math.max(0, width - height) // wider than tall: the pill
                    readonly property color ink: Qt.darker(stage.accent, 2.8)
                    // it looks at your cursor, if you move it; else where the intro says
                    readonly property real cx: morph.x + morph.width / 2
                    readonly property real cy: morph.y + morph.height / 2
                    property real lx: look.hovered && look.moved ? Math.max(-1, Math.min(1, (look.point.position.x - cx) / 260)) : sx
                    property real ly: look.hovered && look.moved ? Math.max(-1, Math.min(1, (look.point.position.y - cy) / 260)) : sy
                    Behavior on lx { SmoothedAnimation { velocity: 7 } }
                    Behavior on ly { SmoothedAnimation { velocity: 7 } }

                    Repeater {
                        model: [-1, 1]
                        Rectangle {
                            required property int modelData
                            width: face.u * 0.13
                            height: Math.max(face.u * 0.025, face.u * 0.2 * (1 - face.blink) * (1 - face.happy * 0.6))
                            radius: width / 2
                            x: face.width / 2 + modelData * (face.u * 0.17 + face.spread * 0.3) - width / 2 + face.lx * face.u * 0.13
                            y: face.height * 0.42 - height / 2 + face.ly * face.u * 0.11
                            color: face.ink
                            antialiasing: true
                        }
                    }
                    Shape { // the smile
                        id: smile
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        readonly property real w: face.u * (0.13 + face.happy * 0.07) + face.spread * 0.08
                        readonly property real y0: face.height * 0.6 + face.ly * face.u * 0.06
                        readonly property real mx: face.width / 2 + face.lx * face.u * 0.09
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
            // the face follows your cursor, but only once you move it (else it
            // looks where the intro says: a pointer just resting there doesn't count)
            HoverHandler {
                id: look
                enabled: intro.running
                property bool moved: false
                property point from: Qt.point(-1, -1)
                onHoveredChanged: if (hovered && from.x < 0) from = point.position
                onPointChanged: if (from.x >= 0 && Math.hypot(point.position.x - from.x, point.position.y - from.y) > 12) moved = true
            }
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
            scale: root.open ? 1 : 0.95
            // leaving: an eased fade and a gentle shrink (no spring bounce on the way out)
            Behavior on opacity { NumberAnimation { duration: root.open ? 260 : 440; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: root.open ? 420 : 480; easing.type: root.open ? Easing.OutBack : Easing.OutCubic } }
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
                    stage.dark = 1; stage.trace = 0; stage.settle = 0; stage.lift = 0; stage.fade = 0; traced.opacity = 1;
                    morph.width = 0; morph.height = 0; morph.x = stage.cx; morph.y = stage.sh * 0.55;
                    morph.radius = 999; // round from the first frame (clamped to half its size)
                    stage.rise = 0; stage.wob = 0;
                    morph.glow = 1; morph.toCard = 0; morph.opacity = 1; morph.rotation = 0;
                    face.opacity = 0; face.blink = 0; face.happy = 0; face.sx = 0; face.sy = 0; look.moved = false; look.from = Qt.point(-1, -1);
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
                // looks around first, curious (at your cursor, if you move it): left,
                // leaning into it, then right, then up at the top edge, where it's
                // going, and back at you
                ParallelAnimation {
                    NumberAnimation { target: face; property: "sx"; to: -1; duration: 280; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: face; property: "sy"; to: 0.2; duration: 280; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: morph; property: "rotation"; to: -6; duration: 320; easing.type: Easing.InOutQuad }
                }
                PauseAnimation { duration: 420 }
                ParallelAnimation {
                    NumberAnimation { target: face; property: "sx"; to: 1; duration: 380; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: morph; property: "rotation"; to: 6; duration: 420; easing.type: Easing.InOutQuad }
                }
                PauseAnimation { duration: 260 }
                NumberAnimation { target: face; property: "blink"; to: 1; duration: 60; easing.type: Easing.InQuad }
                NumberAnimation { target: face; property: "blink"; to: 0; duration: 110; easing.type: Easing.OutQuad }
                PauseAnimation { duration: 160 }
                ParallelAnimation {
                    NumberAnimation { target: face; property: "sx"; to: 0.15; duration: 360; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: face; property: "sy"; to: -1; duration: 360; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: morph; property: "rotation"; to: 0; duration: 360; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: morph; property: "y"; to: stage.sh * 0.5 - 32 - 6; duration: 360; easing.type: Easing.InOutQuad }
                }
                PauseAnimation { duration: 520 }
                ParallelAnimation {
                    NumberAnimation { target: face; property: "sx"; to: 0; duration: 260; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: face; property: "sy"; to: 0; duration: 260; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: morph; property: "y"; to: stage.sh * 0.5 - 32; duration: 260; easing.type: Easing.InOutQuad }
                }
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
                // …and up it goes. One curve: it leaves gently, is quickest mid-way,
                // and eases into the top edge; a slim capsule on the way (moving
                // things stretch), it widens into the island's pill only as it
                // arrives, then settles with a small wobble. Light runs out of it
                // round the frame as it lands.
                ScriptAction { script: {
                    stage.from = Qt.rect(morph.x, morph.y, morph.width, morph.height);
                    stage.rise = 0; stage.wob = 0;
                    const lerp = (a, b, t) => a + (b - a) * t;
                    const ss = (a, b, t) => { const u = Math.max(0, Math.min(1, (t - a) / (b - a))); return u * u * (3 - 2 * u); };
                    morph.width = Qt.binding(() => lerp(lerp(stage.from.width, 40, ss(0, 0.45, stage.rise)), stage.islW, ss(0.55, 1, stage.rise)) + 10 * stage.wob);
                    morph.height = Qt.binding(() => lerp(lerp(stage.from.height, 64, ss(0, 0.45, stage.rise)), 34 + 17, ss(0.5, 1, stage.rise)) - 4 * stage.wob);
                    morph.x = Qt.binding(() => stage.cx - morph.width / 2);
                    // the top runs up into the frame (like the island's), so it lands 17px above the edge
                    morph.y = Qt.binding(() => lerp(stage.from.y, stage.wallW - 17, stage.rise));
                    morph.radius = Qt.binding(() => lerp(morph.height / 2, 17, ss(0.6, 1, stage.rise)));
                } }
                ParallelAnimation {
                    NumberAnimation { target: stage; property: "rise"; to: 1; duration: 720; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.55, 0, 0.2, 1, 1, 1] }
                    SequentialAnimation {
                        PauseAnimation { duration: 140 }
                        NumberAnimation { target: face; property: "opacity"; to: 0; duration: 260; easing.type: Easing.InOutQuad }
                    }
                    SequentialAnimation { // lands: a quick, damped wobble
                        PauseAnimation { duration: 600 }
                        NumberAnimation { target: stage; property: "wob"; to: 1; duration: 120; easing.type: Easing.OutQuad }
                        NumberAnimation { target: stage; property: "wob"; to: -0.45; duration: 170; easing.type: Easing.InOutSine }
                        NumberAnimation { target: stage; property: "wob"; to: 0.15; duration: 150; easing.type: Easing.InOutSine }
                        NumberAnimation { target: stage; property: "wob"; to: 0; duration: 140; easing.type: Easing.InOutSine }
                    }
                    SequentialAnimation {
                        PauseAnimation { duration: 560 }
                        NumberAnimation { target: stage; property: "trace"; to: 1; duration: 1100; easing.type: Easing.InOutSine }
                    }
                }
                // the bindings go: the pill stays put for what follows
                ScriptAction { script: {
                    morph.x = stage.cx - stage.islW / 2; morph.y = stage.wallW - 17; morph.width = stage.islW; morph.height = 34 + 17; morph.radius = 17;
                } }
                PauseAnimation { duration: 260 }   // the whole frame in the island's colour, for a moment
                // the colour settles into the frame's own (the island's pill with it),
                ParallelAnimation {
                    NumberAnimation { target: stage; property: "settle"; to: 1; duration: 520; easing.type: Easing.InOutSine }
                    NumberAnimation { target: morph; property: "glow"; to: 0; duration: 520; easing.type: Easing.InOutSine }
                    // the real island's tucked away (a window's near the top): the pill
                    // tucks into the frame the same way
                    NumberAnimation { target: morph; property: "y"; to: root.tucked ? stage.wallW - 17 - 52 : stage.wallW - 17; duration: 520; easing.type: Easing.InOutCubic }
                }
                // the dark lifts from the island while the sketch, now in the real
                // frame's colours, stays over the real one; then it simply goes
                NumberAnimation { target: stage; property: "lift"; to: 1; duration: 1250; easing.type: Easing.OutCubic }
                ParallelAnimation {
                    NumberAnimation { target: stage; property: "fade"; to: 1; duration: 300; easing.type: Easing.InOutSine }
                    NumberAnimation { target: morph; property: "opacity"; to: 0; duration: 300; easing.type: Easing.InOutSine }
                }
                ScriptAction { script: { stage.dark = 0; stage.lift = 0; stage.fade = 0; } }
                PauseAnimation { duration: 180 }
                // the card blooms out of the island
                ParallelAnimation {
                    NumberAnimation { target: morph; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutQuad }
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
