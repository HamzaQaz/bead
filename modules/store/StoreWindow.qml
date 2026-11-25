pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// The App Store (services/Store.qml): search by name or by what you need
// ("screen recorder"), one result per app with why it's here; with nothing
// typed, bead's picks by category. Install shows on the island's update card;
// an AUR app shows its build file first.
FloatingWindow {
    id: win
    title: "App Store"
    implicitWidth: 900
    implicitHeight: 680
    color: Theme.frame
    visible: true
    onVisibleChanged: if (!visible) Store.open = false

    readonly property bool searching: Store.query.trim().length >= 2
    property string confirmAur: ""   // an AUR app's key, asking first
    property string riskyOk: ""      // a risky AUR app, pressed once more
    property var picked: ({})        // app key → the source chosen (default: its best)
    function srcOf(app: var): var { if (!app?.sources?.length) return ({}); return app.sources.find(s => s.source + ":" + s.name === picked[app.key]) ?? app.best; }
    function pick(app: var, s: var): void { const p = Object.assign({}, picked); p[app.key] = s.source + ":" + s.name; picked = p; }
    function go(app: var): void {
        if (app.installed) { Store.openInstalled(app); return; }
        const s = srcOf(app);
        if (s.source === "aur" && confirmAur !== app.key) { confirmAur = app.key; Store.checkAur(s.name); return; }
        // the check still running, or it found something risky: not on the first press
        const t = s.source === "aur" ? Store.trust[s.name] : null;
        if (t === "checking") return;
        if (t?.level === "danger" && riskyOk !== app.key) { riskyOk = app.key; return; }
        riskyOk = "";
        confirmAur = "";
        Store.install(app, s);
    }
    readonly property var sourceName: ({ repo: "Repos", flathub: "Flathub", aur: "AUR" })
    // the details sheet: which app (null: closed)
    property var detail: null
    Connections { target: Store; function onShowApp(app: var): void { win.show(app); } }
    function show(app: var): void { if (!app) return; detail = app; Store.details(app); }

    component Txt: Text { font.family: Theme.font; color: Theme.text; elide: Text.ElideRight }
    component Sub: Txt { font.pixelSize: 12; color: Theme.subtext }

    // Install / Open / the install's progress
    component Go: Rectangle {
        id: g
        property var app
        readonly property bool mine: Store.installing !== "" && g.app.sources.some(s => s.name === Store.installing)
        readonly property bool busy: Store.installing !== "" && !mine
        width: mine ? 86 : gt.implicitWidth + 28
        height: 32; radius: 16
        clip: true
        readonly property bool risky: win.confirmAur === g.app.key && Store.trust[win.srcOf(g.app).name]?.level === "danger"
        color: g.risky ? Theme.tone("error") : g.app.installed ? Qt.alpha(Theme.text, gma.containsMouse ? 0.12 : 0.07)
            : Qt.alpha(Theme.tone("action"), g.mine ? 0.15 : gma.containsMouse ? 1 : 0.9)
        opacity: g.busy ? 0.4 : 1
        scale: gma.pressed ? 0.93 : 1
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack; easing.overshoot: 3 } }
        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 160 } }
        // the progress, filling the pill
        Rectangle {
            visible: g.mine
            height: parent.height; radius: parent.radius
            width: Math.max(height, parent.width * Updates.progress)
            color: Qt.alpha(Theme.tone("action"), 0.35)
            Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
        // a soft lift of light on hover
        Rectangle {
            anchors.fill: parent; radius: parent.radius
            color: Qt.alpha("white", gma.containsMouse && !g.mine ? 0.1 : 0)
            Behavior on color { ColorAnimation { duration: 160 } }
        }
        Txt {
            id: gt
            anchors.centerIn: parent
            font.pixelSize: 12; font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            color: g.app.installed || g.mine ? Theme.text : Theme.frame
            text: g.mine ? (Updates.inst.phase === "auth" ? "Password…" : Math.round(Updates.progress * 100) + "%")
                : g.app.installed ? "Open"
            : win.confirmAur !== g.app.key ? "Install"
            : Store.trust[win.srcOf(g.app).name] === "checking" ? "Checking…"
            : Store.trust[win.srcOf(g.app).name]?.level === "danger" ? (win.riskyOk === g.app.key ? "Sure? Build" : "Build anyway")
            : "Build it"
        }
        MouseArea { id: gma; anchors.fill: parent; hoverEnabled: true; enabled: !g.busy && !g.mine; cursorShape: Qt.PointingHandCursor; onClicked: win.go(g.app) }
    }
    // an app's icon, or a glyph tile
    component AppIcon: Item {
        id: ai
        property var app
        property int size: 44
        width: size; height: size
        readonly property string src: Store.icon(ai.app)
        // every icon sits on the same soft tile, so odd shapes and sizes line up
        Rectangle {
            anchors.fill: parent; radius: ai.size * 0.3
            color: im.visible ? Qt.alpha(Theme.text, 0.05) : Qt.alpha(Theme.tone("action"), 0.14)
            border.width: 1
            border.color: Qt.alpha(Theme.text, 0.06)
            Txt { anchors.centerIn: parent; visible: !im.visible; font.pixelSize: ai.size * 0.4; font.weight: Font.Bold; color: Theme.tone("action"); text: (ai.app ? Store.title(ai.app) : "?").charAt(0).toUpperCase() }
        }
        IconImage { id: im; anchors.centerIn: parent; width: ai.size * 0.72; height: width; source: ai.src; visible: !!ai.src && status === Image.Ready; asynchronous: true }
    }
    // the icon's own colours as a soft glow behind it (a blurred, larger copy)
    component Glow: Item {
        id: gl
        property var app
        property real strength: 0.55
        property real spread: 1.7
        IconImage { id: gsrc; anchors.fill: parent; source: Store.icon(gl.app); visible: false; asynchronous: true }
        MultiEffect {
            anchors.fill: parent
            scale: gl.spread
            autoPaddingEnabled: true   // the blur runs past the icon's box, so no hard edge
            source: gsrc
            visible: gsrc.status === Image.Ready
            blurEnabled: true; blur: 1; blurMax: 64
            saturation: 0.4
            opacity: gl.strength
            Behavior on opacity { NumberAnimation { duration: 300 } }
        }
    }
    // a soft light that follows the pointer across a card (after reactbits.dev's
    // Spotlight Card): a radial gradient centred on the mouse, faded in on hover
    component Spotlight: Shape {
        id: sp
        preferredRendererType: Shape.CurveRenderer
        property real mx: 0
        property real my: 0
        property bool on: false
        property color tint: Theme.tone("action")
        property real reach: 240
        property real power: 1     // how bright its middle is
        property real rTop: 0      // the corners it lights up to (match the card's)
        property real rBottom: 0
        anchors.fill: parent
        opacity: on ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        // it trails the pointer a little, so it feels like light, not a cursor
        property real cx: mx
        property real cy: my
        Behavior on cx { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on cy { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillGradient: RadialGradient {
                centerX: sp.cx; centerY: sp.cy; centerRadius: sp.reach
                focalX: sp.cx; focalY: sp.cy
                GradientStop { position: 0; color: Qt.alpha(sp.tint, Math.min(1, 0.17 * sp.power)) }
                GradientStop { position: 0.55; color: Qt.alpha(sp.tint, Math.min(1, 0.05 * sp.power)) }
                GradientStop { position: 1; color: Qt.alpha(sp.tint, 0) }
            }
            PathRectangle {
                width: sp.width; height: sp.height
                topLeftRadius: sp.rTop; topRightRadius: sp.rTop
                bottomLeftRadius: sp.rBottom; bottomRightRadius: sp.rBottom
            }
        }
    }
    // a title whose letters rise in one after another (after reactbits.dev's
    // Split Text): each new text plays it again
    component SplitTitle: Row {
        id: st
        property string text: ""
        property int pixelSize: 30
        property int stagger: 26
        Repeater {
            model: st.text.split("")
            Text {
                id: ch
                required property string modelData
                required property int index
                text: modelData === " " ? "\u00a0" : modelData
                font.family: Theme.font; font.pixelSize: st.pixelSize; font.weight: Font.Black; font.letterSpacing: -0.4
                color: Theme.text
                opacity: 0
                transform: Translate { id: chUp; y: st.pixelSize * 0.6 }
                Component.onCompleted: rise.start()
                ParallelAnimation {
                    id: rise
                    SequentialAnimation { PauseAnimation { duration: ch.index * st.stagger } NumberAnimation { target: ch; property: "opacity"; to: 1; duration: 380; easing.type: Easing.OutCubic } }
                    SequentialAnimation { PauseAnimation { duration: ch.index * st.stagger } NumberAnimation { target: chUp; property: "y"; to: 0; duration: 620; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                }
            }
        }
    }
    // smooth scrolling for a Flickable: the wheel and touchpad move a target and
    // the view eases toward it every frame, so notches blend into one glide.
    // It lies over the Flickable (which ignores the wheel itself: interactive: false)
    component SmoothScroll: Item {
        id: ss
        required property Flickable view
        property real speed: 1.25     // pixels per wheel unit (a notch is 120)
        property real ty: 0
        readonly property real maxY: Math.max(0, view.contentHeight - view.height)
        anchors.fill: view
        function clamp(y: real): real { return Math.max(0, Math.min(y, maxY)); }
        function go(y: real): void { ty = clamp(y); ease.running = true; }
        function jump(y: real): void { ease.running = false; ty = clamp(y); view.contentY = ty; }
        function ease_running(): bool { return ease.running; }
        onMaxYChanged: if (view.contentY > maxY) jump(maxY)
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: e => {
                const from = ease.running ? ss.ty : ss.view.contentY;
                // a touchpad says pixels; a wheel says notches
                const d = e.pixelDelta.y !== 0 ? e.pixelDelta.y : e.angleDelta.y * ss.speed;
                ss.go(from - d);
            }
        }
        FrameAnimation {
            id: ease
            onTriggered: {
                const c = ss.view.contentY, d = ss.ty - c;
                if (Math.abs(d) < 0.4) { ss.view.contentY = ss.ty; running = false; return; }
                ss.view.contentY = c + d * (1 - Math.exp(-frameTime * 13));
            }
        }
    }
    // clips what's inside to rounded corners (clip: true only cuts a square box)
    component RoundClip: Item {
        id: rcl
        property real radius: 20
        default property alias content: holder.data
        Item {
            id: holder
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: rclMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
        }
        Item { id: rclMask; anchors.fill: parent; layer.enabled: true; visible: false; Rectangle { anchors.fill: parent; radius: rcl.radius } }
    }
    // where it comes from: a chip per source, the chosen one lit
    component Sources: Row {
        id: sr
        property var app
        spacing: 5
        Repeater {
            model: sr.app.sources.filter((s, i, a) => a.findIndex(x => x.source === s.source) === i)
            Rectangle {
                id: chip
                required property var modelData
                readonly property bool on: win.srcOf(sr.app).source === chip.modelData.source
                width: ct.implicitWidth + 14; height: 20; radius: 10
                color: on ? Qt.alpha(Theme.tone(chip.modelData.source === "aur" ? "warning" : "action"), 0.18) : Qt.alpha(Theme.text, cma.containsMouse ? 0.1 : 0.05)
                Txt { id: ct; anchors.centerIn: parent; font.pixelSize: 10; font.weight: Font.DemiBold; color: chip.on ? Theme.text : Theme.subtext; text: win.sourceName[chip.modelData.source] + (chip.modelData.installed ? " ✓" : "") }
                MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; enabled: sr.app.sources.length > 1; cursorShape: Qt.PointingHandCursor; onClicked: win.pick(sr.app, chip.modelData) }
            }
        }
    }
    // the AUR, asking first: what that means, and its build file
    component AurNote: Rectangle {
        id: an
        property var app
        visible: win.confirmAur === an.app.key
        width: parent?.width ?? 0
        height: visible ? anCol.implicitHeight + 16 : 0
        radius: 10
        readonly property var t: Store.trust[win.srcOf(an.app).name]
        readonly property string level: an.t && an.t !== "checking" ? an.t.level : ""
        color: Qt.alpha(Theme.tone(an.level === "danger" ? "error" : an.level === "ok" ? "success" : "warning"), 0.1)
        Column {
            id: anCol
            x: 12; y: 8; width: parent.width - 24; spacing: 6
            Text {
                width: parent.width; wrapMode: Text.Wrap
                font.family: Theme.font; font.pixelSize: 12; color: Theme.text
                text: "Built on your computer from a recipe anyone can upload to the AUR."
                    + (an.t === "checking" ? " Checking it…"
                       : an.level === "ok" ? " bead's check found nothing worrying."
                       : an.level === "caution" ? " Worth a look first:"
                       : an.level === "danger" ? " bead's check found something risky:" : "")
            }
            // what the check found (trust.js): each reason on its own line
            Repeater {
                model: an.level && an.level !== "ok" ? an.t.reasons.slice(0, 4) : []
                Text {
                    required property string modelData
                    width: anCol.width; wrapMode: Text.Wrap
                    font.family: Theme.font; font.pixelSize: 12
                    color: an.level === "danger" ? Theme.tone("error") : Theme.text
                    text: "• " + modelData
                }
            }
            Row {
                spacing: 12
                Txt { font.pixelSize: 12; font.weight: Font.DemiBold; color: Theme.tone("action"); text: "Build file ↗"; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Store.buildFile(win.srcOf(an.app).name) } }
                Txt { font.pixelSize: 12; color: Theme.subtext; text: "Cancel"; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.confirmAur = "" } }
            }
        }
    }

    // ── the title, and the search ──
    Column {
        id: head
        x: 26; y: 20
        spacing: 2
        Txt { font.pixelSize: 26; font.weight: Font.Black; font.letterSpacing: -0.5; text: "App Store" }
        Sub { font.pixelSize: 13; text: "The repos, Flathub and the AUR in one place: one result per app, the repos first." }
    }
    Rectangle {
        id: bar
        x: 24; y: head.y + head.height + 14
        width: parent.width - 48; height: 46; radius: 23
        color: Theme.fill
        border.width: 1
        border.color: Qt.alpha(Theme.tone("action"), field.activeFocus ? 0.5 : 0.08)
        Behavior on border.color { ColorAnimation { duration: 200 } }
        Icon { x: 16; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 20; color: Theme.subtext }
        TextInput {
            TextMenu {}   // right-click: cut, copy, paste
            id: field
            x: 46; width: parent.width - 46 - 46
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.font; font.pixelSize: 15
            color: Theme.text
            selectionColor: Qt.alpha(Theme.tone("action"), 0.4)
            clip: true
            text: Store.pending
            focus: true
            Component.onCompleted: forceActiveFocus()
            onTextEdited: { win.confirmAur = ""; Store.search(text); }
            Keys.onEscapePressed: { if (win.detail) win.detail = null; else if (text) { text = ""; Store.search(""); } else win.visible = false; }
            Txt {
                visible: !field.text
                anchors.verticalCenter: parent.verticalCenter
                font.pixelSize: 15; color: Theme.subtext
                text: "Search apps, or what you need: \"screen recorder\", \"notes\"…"
            }
        }
        Icon {
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            visible: Store.searching
            name: "progress_activity"; size: 18; color: Theme.subtext
            RotationAnimation on rotation { running: Store.searching; loops: Animation.Infinite; from: 0; to: 360; duration: 900 }
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.topMargin: bar.y + bar.height + 18
        anchors.leftMargin: 24; anchors.rightMargin: 24
        contentHeight: (win.searching ? list.implicitHeight : frontCol.implicitHeight) + 24
        clip: true
        interactive: false          // SmoothScroll moves it
        boundsBehavior: Flickable.StopAtBounds

        // ── nothing typed: bead's picks ──
        Column {
            id: frontCol
            opacity: win.searching ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            width: flick.width
            spacing: 22
            // ── featured: a pick at a time, its icon's glow behind it ──
            Rectangle {
                id: hero
                width: frontCol.width; height: 196
                radius: 24
                color: Theme.fill
                border.width: 1
                border.color: Qt.alpha(Theme.text, 0.05)
                clip: true
                readonly property var all: { const o = []; for (const c of Store.front) for (const a of c.apps) if (!a.installed) o.push(a); return o.slice(0, 8); }
                property int at: 0
                readonly property var app: all.length ? all[at % all.length] : null
                visible: !!app
                Timer { running: win.visible && !win.searching && hero.all.length > 1 && !heroMa.containsMouse; interval: 6000; repeat: true; onTriggered: hero.show((hero.at + 1) % hero.all.length) }
                // the next pick: text slides out and the icon shrinks away, then they come back in
                function show(i: int): void { heroFade.next = i; heroFade.restart(); }
                SequentialAnimation {
                    id: heroFade
                    property int next: 0
                    ParallelAnimation {
                        NumberAnimation { target: heroBody; property: "opacity"; to: 0; duration: 240; easing.type: Easing.InCubic }
                        NumberAnimation { target: heroText; property: "x"; to: -16; duration: 240; easing.type: Easing.InCubic }
                        NumberAnimation { target: heroIcon; property: "scale"; to: 0.8; duration: 240; easing.type: Easing.InCubic }
                    }
                    ScriptAction { script: { hero.at = heroFade.next; heroText.x = 24; } }
                    ParallelAnimation {
                        NumberAnimation { target: heroBody; property: "opacity"; to: 1; duration: 460; easing.type: Easing.OutCubic }
                        NumberAnimation { target: heroText; property: "x"; to: 0; duration: 560; easing.type: Easing.OutCubic }
                        NumberAnimation { target: heroIcon; property: "scale"; to: 1; duration: 620; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                    }
                }
                MouseArea { id: heroMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.show(hero.app) }
                Item {
                    id: heroBody
                    anchors.fill: parent
                    // a light gliding along the rim (after reactbits.dev's Star Border):
                    // one along the top, one along the bottom, going opposite ways and
                    // turning before the corners; a fill 1.5px in covers all but the rim
                    Item {
                        id: rimLight
                        anchors.fill: parent
                        readonly property real reach: 120
                        readonly property real lo: hero.radius + reach
                        readonly property real hi: hero.width - hero.radius - reach
                        property real t: 0
                        SequentialAnimation on t {
                            loops: Animation.Infinite; running: win.visible && !win.searching
                            NumberAnimation { from: 0; to: 1; duration: 4200; easing.type: Easing.InOutSine }
                            NumberAnimation { from: 1; to: 0; duration: 4200; easing.type: Easing.InOutSine }
                        }
                        Spotlight { on: true; reach: rimLight.reach; power: 5.5; my: 0; mx: rimLight.lo + (rimLight.hi - rimLight.lo) * rimLight.t }
                        Spotlight { on: true; reach: rimLight.reach; power: 5.5; my: hero.height; mx: rimLight.hi - (rimLight.hi - rimLight.lo) * rimLight.t }
                        Rectangle { anchors.fill: parent; anchors.margins: 1.5; radius: hero.radius - 1.5; color: Theme.fill }
                    }
                    // the glow fills the right side, inside the rim
                    RoundClip {
                        anchors.fill: parent
                        anchors.margins: 1.5
                        radius: hero.radius - 1.5
                        // the icon's glow, breathing slowly: the whole layer's opacity moves,
                        // so the blur is drawn once, not every frame
                        SequentialAnimation on opacity { loops: Animation.Infinite; running: win.visible && !win.searching
                            NumberAnimation { to: 1; duration: 2400; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 0.72; duration: 2400; easing.type: Easing.InOutSine } }
                        Glow {
                            id: heroGlow
                            app: hero.app; width: 200; height: 200; x: parent.width - 240; anchors.verticalCenter: parent.verticalCenter; spread: 2.6
                            strength: 0.75
                        }
                        // and fades out towards the text
                        Rectangle {
                            anchors.fill: parent
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.3; color: Theme.fill }
                                GradientStop { position: 0.72; color: Qt.alpha(Theme.fill, 0) }
                            }
                        }
                    }
                    // sparkles drifting up out of the glow (after reactbits.dev's Particles),
                    // outside the layer so they don't redraw it; they stay clear of the corners
                    Repeater {
                        model: 14
                        Rectangle {
                            id: mote
                            required property int index
                            readonly property real seed: (index * 7919 % 97) / 97
                            width: 2 + seed * 3; height: width; radius: width / 2
                            color: Theme.tone("action")
                            x: hero.width - 270 + ((index * 53) % 200)
                            y: hero.height
                            opacity: 0
                            SequentialAnimation {
                                loops: Animation.Infinite; running: win.visible && !win.searching
                                PauseAnimation { duration: mote.index * 420 }
                                ParallelAnimation {
                                    NumberAnimation { target: mote; property: "y"; from: hero.height * (0.62 + mote.seed * 0.22); to: 20 + hero.height * 0.1 * mote.seed; duration: 3800 + mote.seed * 2600; easing.type: Easing.OutSine }
                                    SequentialAnimation {
                                        NumberAnimation { target: mote; property: "opacity"; to: 0.35 + mote.seed * 0.45; duration: 900 }
                                        PauseAnimation { duration: 1400 + mote.seed * 1200 }
                                        NumberAnimation { target: mote; property: "opacity"; to: 0; duration: 1500 + mote.seed * 1400 }
                                    }
                                    NumberAnimation { target: mote; property: "x"; from: hero.width - 270 + ((mote.index * 53) % 200); to: hero.width - 270 + ((mote.index * 53) % 200) + (mote.seed - 0.5) * 50; duration: 3800 + mote.seed * 2600; easing.type: Easing.InOutSine }
                                }
                            }
                        }
                    }
                    AppIcon {
                        id: heroIcon
                        app: hero.app; size: 112
                        x: parent.width - 196; anchors.verticalCenter: parent.verticalCenter
                        rotation: -6
                        // leans towards the pointer in 3D (after reactbits.dev's Tilted Card)
                        readonly property real tx: heroMa.containsMouse ? Math.max(-1, Math.min(1, (heroMa.mouseY - hero.height / 2) / (hero.height / 2))) : 0
                        readonly property real ty: heroMa.containsMouse ? Math.max(-1, Math.min(1, (heroMa.mouseX - (x + width / 2)) / 300)) : 0
                        property real ax: -tx * 16
                        property real ay: ty * 18
                        Behavior on ax { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        Behavior on ay { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                        transform: [
                            Rotation { origin.x: 56; origin.y: 56; axis { x: 1; y: 0; z: 0 } angle: heroIcon.ax },
                            Rotation { origin.x: 56; origin.y: 56; axis { x: 0; y: 1; z: 0 } angle: heroIcon.ay }
                        ]
                        SequentialAnimation on y {
                            loops: Animation.Infinite; running: win.visible
                            NumberAnimation { to: (hero.height - 112) / 2 - 6; duration: 2600; easing.type: Easing.InOutSine }
                            NumberAnimation { to: (hero.height - 112) / 2 + 6; duration: 2600; easing.type: Easing.InOutSine }
                        }
                    }
                    Item {
                        id: heroText
                        width: parent.width; height: parent.height
                    Column {
                        x: 28; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 300
                        spacing: 6
                        Txt { font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1.2; color: Theme.tone("action"); text: "FEATURED" }
                        SplitTitle { pixelSize: 30; text: hero.app ? Store.title(hero.app) : "" }
                        Text { width: parent.width; wrapMode: Text.Wrap; maximumLineCount: 2; font.family: Theme.font; font.pixelSize: 14; color: Theme.subtext; text: hero.app ? Store.reason(hero.app) : "" }
                        Item { width: 1; height: 6 }
                        Row {
                            spacing: 10
                            Go { app: hero.app ?? ({ sources: [], installed: false, key: "" }) }
                            Sub { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 11; text: hero.app ? "From " + { repo: "the repos", flathub: "Flathub", aur: "the AUR" }[win.srcOf(hero.app).source] : "" }
                        }
                    }
                    }
                }
                // which one: dots, click to jump
                Row {
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 14
                    x: 28
                    spacing: 6
                    Repeater {
                        model: hero.all.length
                        Rectangle {
                            id: dot
                            required property int index
                            readonly property bool cur: index === hero.at
                            width: cur ? 26 : 6; height: 6; radius: 3
                            color: Qt.alpha(Theme.text, cur ? 0.14 : 0.2)
                            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                            // counts down to the next pick (holds while you point at the banner)
                            Rectangle {
                                height: parent.height; radius: 3
                                color: Theme.tone("action")
                                width: 0
                                NumberAnimation on width {
                                    id: fillUp
                                    running: dot.cur && win.visible && !win.searching
                                    paused: running && heroMa.containsMouse
                                    from: 6; to: 26; duration: 6000
                                }
                                visible: dot.cur
                            }
                            MouseArea { anchors.fill: parent; anchors.margins: -4; cursorShape: Qt.PointingHandCursor; onClicked: if (parent.index !== hero.at) hero.show(parent.index) }
                        }
                    }
                }
            }
            // ── editor's choice: bead's notes on a few picks ──
            Column {
                visible: Store.editors.length > 0
                width: frontCol.width
                spacing: 10
                Row {
                    spacing: 8
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "workspace_premium"; size: 18; fill: 1; color: Theme.tone("warning") }
                    Txt { font.pixelSize: 15; font.weight: Font.Bold; text: "Editor's choice" }
                }
                Flow {
                    width: parent.width
                    spacing: 12
                    Repeater {
                        model: Store.editors
                        Rectangle {
                            id: ed
                            required property var modelData
                            required property int index
                            width: (frontCol.width - 12) / 2
                            height: 128
                            radius: 22
                            color: Theme.fill
                            border.width: 1
                            border.color: Qt.alpha(ema.containsMouse ? Theme.tone("warning") : Theme.text, ema.containsMouse ? 0.35 : 0.05)
                            Behavior on border.color { ColorAnimation { duration: 200 } }
                            RoundClip {
                                anchors.fill: parent; radius: ed.radius
                                Glow { app: ed.modelData.app; width: 64; height: 64; x: 20; anchors.verticalCenter: parent.verticalCenter; spread: 3.2; strength: ema.containsMouse ? 0.7 : 0.4 }
                                Spotlight { mx: ema.mouseX; my: ema.mouseY; on: ema.containsMouse; tint: Theme.tone("warning"); reach: 280 }
                            }
                            MouseArea { id: ema; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.show(ed.modelData.app) }
                            opacity: 0
                            transform: [Translate { id: edIn; x: ed.index % 2 ? 24 : -24 }, Translate { y: ema.containsMouse ? -3 : 0; Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } } }]
                            Component.onCompleted: edAppear.start()
                            ParallelAnimation {
                                id: edAppear
                                SequentialAnimation { PauseAnimation { duration: 120 + ed.index * 70 } NumberAnimation { target: ed; property: "opacity"; to: 1; duration: 360; easing.type: Easing.OutCubic } }
                                SequentialAnimation { PauseAnimation { duration: 120 + ed.index * 70 } NumberAnimation { target: edIn; property: "x"; to: 0; duration: 520; easing.type: Easing.OutCubic } }
                            }
                            AppIcon {
                                app: ed.modelData.app; size: 64
                                x: 20; anchors.verticalCenter: parent.verticalCenter
                                scale: ema.containsMouse ? 1.06 : 1
                                rotation: ema.containsMouse ? -4 : 0
                                Behavior on scale { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
                                Behavior on rotation { NumberAnimation { duration: 320; easing.type: Easing.OutBack } }
                            }
                            Column {
                                x: 100; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 100 - 20
                                spacing: 4
                                Row {
                                    width: parent.width
                                    Txt { width: parent.width - edGo.width; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 16; font.weight: Font.Bold; text: Store.title(ed.modelData.app) }
                                    Go { id: edGo; app: ed.modelData.app }
                                }
                                Text {
                                    width: parent.width
                                    wrapMode: Text.Wrap; maximumLineCount: 3; elide: Text.ElideRight
                                    font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.15; color: Theme.subtext
                                    text: ed.modelData.note
                                }
                            }
                        }
                    }
                }
            }
            // ── categories: jump to one ──
            Flow {
                width: frontCol.width
                spacing: 8
                Repeater {
                    model: Store.front
                    Rectangle {
                        id: jump
                        required property var modelData
                        required property int index
                        width: jr.implicitWidth + 26; height: 34; radius: 17
                        color: jma.containsMouse ? Qt.alpha(Theme.tone("action"), 0.2) : Theme.fill
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Row {
                            id: jr
                            anchors.centerIn: parent
                            spacing: 6
                            Icon { anchors.verticalCenter: parent.verticalCenter; name: jump.modelData.icon; size: 16; color: Theme.tone("action") }
                            Txt { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12; font.weight: Font.DemiBold; text: jump.modelData.title }
                        }
                        MouseArea {
                            id: jma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { const target = cats.itemAt(jump.index); if (target) scroller.go(target.y - 8); }
                        }
                    }
                }
            }
            Repeater {
                id: cats
                model: Store.front
                Column {
                    id: cat
                    required property var modelData
                    width: frontCol.width
                    spacing: 10
                    visible: cat.modelData.apps.length > 0
                    Row {
                        spacing: 8
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: cat.modelData.icon; size: 18; color: Theme.tone("action") }
                        Txt { font.pixelSize: 15; font.weight: Font.Bold; text: cat.modelData.title }
                    }
                    Flow {
                        width: parent.width
                        spacing: 12
                        Repeater {
                            model: cat.modelData.apps
                            Rectangle {
                                id: card
                                required property var modelData
                                required property int index
                                width: (frontCol.width - 24) / 3
                                height: Math.max(176, cc.implicitHeight + 36)
                                radius: 20
                                color: Theme.fill
                                border.width: 1
                                border.color: Qt.alpha(cma2.containsMouse ? Theme.tone("action") : Theme.text, cma2.containsMouse ? 0.3 : 0.05)
                                Behavior on border.color { ColorAnimation { duration: 180 } }
                                // its icon's colours, glowing from the top corner (inside the rounded corners)
                                RoundClip {
                                    anchors.fill: parent; radius: card.radius
                                    Glow { app: card.modelData; width: 52; height: 52; x: 18; y: 18; spread: 3; strength: cma2.containsMouse ? 0.5 : 0.22 }
                                    Spotlight { mx: cma2.mouseX; my: cma2.mouseY; on: cma2.containsMouse }
                                    Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.text, cma2.containsMouse ? 0.025 : 0); Behavior on color { ColorAnimation { duration: 180 } } }
                                }
                                MouseArea { id: cma2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.show(card.modelData) }
                                // in, one after another; up a little under the pointer
                                opacity: 0
                                transform: [Translate { id: cardIn; y: 10 }, Translate { y: cma2.containsMouse ? -3 : 0; Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } } }]
                                Component.onCompleted: cardAppear.start()
                                ParallelAnimation {
                                    id: cardAppear
                                    SequentialAnimation { PauseAnimation { duration: card.index * 40 } NumberAnimation { target: card; property: "opacity"; to: 1; duration: 300; easing.type: Easing.OutCubic } }
                                    SequentialAnimation { PauseAnimation { duration: card.index * 40 } NumberAnimation { target: cardIn; property: "y"; to: 0; duration: 380; easing.type: Easing.OutCubic } }
                                }
                                Column {
                                    id: cc
                                    x: 18; y: 18; width: parent.width - 36; spacing: 12
                                    // the icon, and its button across from it
                                    Item {
                                        width: parent.width; height: 52
                                        AppIcon { app: card.modelData; size: 52 }
                                        Go { app: card.modelData; anchors.right: parent.right; anchors.top: parent.top }
                                    }
                                    Column {
                                        width: parent.width; spacing: 4
                                        Txt { width: parent.width; font.pixelSize: 15; font.weight: Font.DemiBold; text: Store.title(card.modelData) }
                                        Text {
                                            width: parent.width
                                            wrapMode: Text.Wrap; maximumLineCount: 2; elide: Text.ElideRight
                                            font.family: Theme.font; font.pixelSize: 12; lineHeight: 1.15; color: Theme.subtext
                                            text: Store.reason(card.modelData)
                                        }
                                    }
                                    Row {
                                        spacing: 6
                                        Rectangle {
                                            width: srcT.implicitWidth + 14; height: 20; radius: 10
                                            color: Qt.alpha(Theme.text, 0.06)
                                            Txt { id: srcT; anchors.centerIn: parent; font.pixelSize: 10; font.weight: Font.DemiBold; color: Theme.subtext; text: win.sourceName[win.srcOf(card.modelData).source] }
                                        }
                                        Rectangle {
                                            visible: card.modelData.installed
                                            width: insT.implicitWidth + 28; height: 20; radius: 10
                                            color: Qt.alpha(Theme.tone("success"), 0.14)
                                            Icon { x: 7; anchors.verticalCenter: parent.verticalCenter; name: "check"; size: 12; color: Theme.tone("success") }
                                            Txt { id: insT; x: 21; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 10; font.weight: Font.DemiBold; color: Theme.tone("success"); text: "Installed" }
                                        }
                                    }
                                    AurNote { app: card.modelData }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── a search: one row per app ──
        Column {
            id: list
            opacity: win.searching ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            width: flick.width
            spacing: 10
            Sub {
                visible: !Store.searching && Store.results.length === 0
                text: "Nothing found for \"" + Store.query + "\"."
            }
            // one grouped list, rows split by hairlines
            Rectangle {
                visible: Store.results.length > 0
                width: list.width
                height: rows.implicitHeight
                radius: 20
                color: Theme.fill
                border.width: 1
                border.color: Qt.alpha(Theme.text, 0.05)
                Column {
                    id: rows
                    width: parent.width
                    // 30 rows made once; each shows whichever app is at its place now,
                    // so new results swap in without rebuilding the list
                    Repeater {
                        model: 30
                        Item {
                            id: row
                            required property int index
                            readonly property var modelData: Store.results[index] ?? null
                            readonly property bool first: index === 0
                            readonly property bool last: index === Store.results.length - 1
                            visible: !!modelData
                            width: rows.width
                            height: visible ? rc.implicitHeight + 24 : 0
                            Rectangle {
                                anchors.fill: parent
                                topLeftRadius: row.first ? 20 : 0; topRightRadius: row.first ? 20 : 0
                                bottomLeftRadius: row.last ? 20 : 0; bottomRightRadius: row.last ? 20 : 0
                                color: Qt.alpha(Theme.text, rma.containsMouse ? 0.035 : 0)
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            Glow { app: row.modelData; width: 46; height: 46; x: 16; y: 12; spread: 1.6; strength: rma.containsMouse ? 0.45 : 0.15 }
                            Spotlight { mx: rma.mouseX; my: rma.mouseY; on: rma.containsMouse; reach: 320; rTop: row.first ? 20 : 0; rBottom: row.last ? 20 : 0 }
                            Rectangle { visible: row.index > 0; x: 76; width: parent.width - 76 - 16; height: 1; color: Qt.alpha(Theme.text, 0.06) }
                            MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.show(row.modelData) }
                            // a different app here: it fades and slides in (a little later further down)
                            readonly property string key: modelData?.key ?? ""
                            onKeyChanged: if (key) { appear.restart(); }
                            transform: Translate { id: rowIn; y: 0 }
                            SequentialAnimation {
                                id: appear
                                ScriptAction { script: { row.opacity = 0.0; rowIn.y = 6; } }
                                PauseAnimation { duration: Math.min(row.index, 10) * 18 }
                                ParallelAnimation {
                                    NumberAnimation { target: row; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: rowIn; property: "y"; to: 0; duration: 300; easing.type: Easing.OutCubic }
                                }
                            }
                            Column {
                                id: rc
                                x: 16; y: 12; width: parent.width - 32; spacing: 8
                                Row {
                                    width: parent.width; spacing: 14
                                    AppIcon { app: row.modelData; size: 46; anchors.verticalCenter: parent.verticalCenter }
                                    Column {
                                        width: parent.width - 46 - 14 - rgo.width - 14
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 4
                                        Row {
                                            spacing: 8
                                            Txt { font.pixelSize: 14; font.weight: Font.DemiBold; text: row.modelData ? Store.title(row.modelData) : "" }
                                            Sources { app: row.modelData ?? ({ sources: [] }); anchors.verticalCenter: parent.verticalCenter }
                                        }
                                        Sub { width: parent.width; text: row.modelData ? (Store.reason(row.modelData) || row.modelData.best.name) : "" }
                                    }
                                    Go { id: rgo; app: row.modelData ?? ({ sources: [], installed: false, key: "" }); anchors.verticalCenter: parent.verticalCenter }
                                }
                                AurNote { app: row.modelData ?? ({ key: "", sources: [], best: {} }) }
                            }
                        }
                    }
                }
            }
        }
    }

    SmoothScroll { id: scroller; view: flick; enabled: !win.detail }
    // a new search starts at the top
    Connections {
        target: Store
        function onQueryChanged(): void { scroller.jump(0); }
        function onScrollBy(px: real): void { const sc = win.detail ? sheetScroll : scroller; sc.go((sc.ease_running() ? sc.ty : sc.view.contentY) + px); }
    }
    // ── an app's details: slides in from the right over a dimmed store ──
    Rectangle {
        id: dim
        anchors.fill: parent
        color: Qt.alpha("black", win.detail ? 0.45 : 0)
        visible: color.a > 0.01
        Behavior on color { ColorAnimation { duration: 280; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent; enabled: !!win.detail; onClicked: win.detail = null }
    }
    // the app shown stays while the sheet slides away
    property var shown: null
    onDetailChanged: if (detail) { shown = detail; sheetScroll.jump(0); }
    Rectangle {
        id: sheet
        readonly property var app: win.shown
        readonly property var d: app ? Store.info[app.key] : null
        readonly property bool ready: !!d && typeof d === "object"
        width: Math.min(500, win.width - 60)
        height: win.height - 24
        y: 12
        x: win.detail ? win.width - width - 12 : win.width + 20
        Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        radius: 26
        color: Theme.fill
        border.width: 1
        border.color: Qt.alpha(Theme.text, 0.07)
        visible: x < win.width
        MouseArea { anchors.fill: parent }   // clicks stay in the sheet
        // the icon's glow across the top, inside the corners
        RoundClip {
            anchors.fill: parent; radius: sheet.radius
            Glow { app: sheet.app; width: 96; height: 96; x: 28; y: 28; spread: 4; strength: 0.55 }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.12; color: Qt.alpha(Theme.fill, 0) }
                    GradientStop { position: 0.4; color: Theme.fill }
                }
            }
        }
        // close (above the sheet's scroller)
        Rectangle {
            anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 16
            width: 34; height: 34; radius: 17
            z: 2
            color: Qt.alpha(Theme.text, xma.containsMouse ? 0.14 : 0.07)
            Icon { anchors.centerIn: parent; name: "close"; size: 18; color: Theme.text }
            MouseArea { id: xma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.detail = null }
        }
        Flickable {
            id: sf
            anchors.fill: parent
            anchors.margins: 28
            contentHeight: sc.implicitHeight
            clip: true
            interactive: false
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: sc
                width: sf.width
                spacing: 18
                // who it is
                Row {
                    spacing: 18
                    AppIcon { app: sheet.app; size: 96 }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: sc.width - 96 - 18 - 30
                        spacing: 6
                        SplitTitle { pixelSize: 26; stagger: 18; text: win.detail && sheet.app ? Store.title(sheet.app) : "" }
                        Sub { width: parent.width; font.pixelSize: 13; visible: text !== ""; text: sheet.ready ? sheet.d.developer : "" }
                        Sources { app: sheet.app ?? ({ sources: [] }) }
                    }
                }
                Row {
                    spacing: 10
                    Go { app: sheet.app ?? ({ sources: [], installed: false, key: "" }) }
                    Sub { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12; text: sheet.app ? "From " + { repo: "the repos", flathub: "Flathub", aur: "the AUR" }[win.srcOf(sheet.app).source] : "" }
                }
                AurNote { app: sheet.app ?? ({ key: "", sources: [], best: {} }) }
                // Editor's choice: only for bead's maintainer (Store.maintainer)
                Rectangle {
                    id: edBox
                    visible: Store.maintainer && !Demo.on && !!sheet.app   // never in demo mode (screenshots, videos)
                    readonly property var pick: Store.pickOf(sheet.app)
                    readonly property string note: Store.editorNote(sheet.app)
                    width: sc.width
                    height: visible ? edCol.implicitHeight + 28 : 0
                    radius: 16
                    color: Qt.alpha(Theme.tone("warning"), 0.08)
                    border.width: 1
                    border.color: Qt.alpha(Theme.tone("warning"), 0.22)
                    Column {
                        id: edCol
                        x: 14; y: 14; width: parent.width - 28; spacing: 10
                        Row {
                            spacing: 8
                            Icon { anchors.verticalCenter: parent.verticalCenter; name: "workspace_premium"; size: 18; fill: 1; color: Theme.tone("warning") }
                            Txt { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 13; font.weight: Font.Bold; text: edBox.note ? "In Editor's choice" : "Editor's choice" }
                            Sub { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 11; text: "· only you see this" }
                        }
                        Sub {
                            visible: !edBox.pick
                            width: parent.width; wrapMode: Text.Wrap
                            text: "Only apps in one of the store's categories can be featured: add it to data/apps.json first."
                        }
                        // the note: what you'd say about it
                        Rectangle {
                            visible: !!edBox.pick
                            width: parent.width; height: 38; radius: 12
                            color: Qt.alpha(Theme.text, 0.06)
                            border.width: 1
                            border.color: Qt.alpha(Theme.tone("warning"), noteIn.activeFocus ? 0.5 : 0)
                            TextInput {
                                TextMenu {}   // right-click: cut, copy, paste
                                id: noteIn
                                anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 44
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: Theme.font; font.pixelSize: 13
                                color: Theme.text; clip: true
                                maximumLength: 109
                                selectionColor: Qt.alpha(Theme.tone("warning"), 0.4)
                                text: edBox.note || (sheet.app ? Store.reason(sheet.app) : "")
                                onTextChanged: if (!activeFocus) cursorPosition = 0
                                Keys.onReturnPressed: Store.setEditor(sheet.app, text, true)
                                Keys.onEscapePressed: win.detail = null
                            }
                            Sub { anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 10; text: 109 - noteIn.text.length }
                        }
                        Row {
                            visible: !!edBox.pick
                            spacing: 8
                            Action { text: edBox.note ? "Save note" : "Add to Editor's choice"; glyph: "workspace_premium"; accent: true; onHit: Store.setEditor(sheet.app, noteIn.text, true) }
                            Action { visible: !!edBox.note; text: "Remove"; glyph: "remove"; onHit: Store.setEditor(sheet.app, "", false) }
                        }
                        Sub {
                            width: parent.width; wrapMode: Text.Wrap
                            color: Store.editorError ? Theme.tone("error") : Theme.subtext
                            text: Store.editorError || "Saved to your bead checkout's data/apps.json: commit and push it to show everyone."
                        }
                    }
                }
                // a screenshot, when Flathub has one: fades in once it's loaded
                RoundClip {
                    visible: sheet.ready && !!sheet.d.screenshot
                    width: sc.width
                    height: visible ? Math.round(width * 0.62) : 0
                    radius: 16
                    Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.text, 0.05) }
                    Image {
                        id: shot
                        anchors.fill: parent
                        source: sheet.ready ? sheet.d.screenshot : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        opacity: status === Image.Ready ? 1 : 0
                        scale: status === Image.Ready ? 1 : 1.04
                        Behavior on opacity { NumberAnimation { duration: 400 } }
                        Behavior on scale { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }
                    }
                }
                // loading: a few soft bars
                Column {
                    visible: !sheet.ready
                    width: sc.width; spacing: 10
                    Repeater {
                        model: [1, 0.92, 0.8, 0.6]
                        Rectangle {
                            required property real modelData
                            width: sc.width * modelData; height: 12; radius: 6
                            color: Qt.alpha(Theme.text, 0.07)
                            SequentialAnimation on opacity { loops: Animation.Infinite; running: !sheet.ready
                                NumberAnimation { to: 0.4; duration: 700; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine } }
                        }
                    }
                }
                Txt {
                    visible: sheet.d === "failed"
                    width: sc.width; wrapMode: Text.Wrap
                    font.pixelSize: 13; color: Theme.subtext
                    text: "Couldn't load the details. " + (sheet.app ? Store.reason(sheet.app) : "")
                }
                // what it is
                Text {
                    visible: sheet.ready
                    width: sc.width
                    wrapMode: Text.Wrap
                    font.family: Theme.font; font.pixelSize: 14; lineHeight: 1.3
                    color: Theme.text
                    text: sheet.ready ? sheet.d.description : ""
                }
                // links: website, source code, bugs, its page
                Flow {
                    visible: sheet.ready && sheet.d.links.length > 0
                    width: sc.width
                    spacing: 8
                    Repeater {
                        model: sheet.ready ? sheet.d.links : []
                        Rectangle {
                            id: lk
                            required property var modelData
                            width: lkr.implicitWidth + 26; height: 34; radius: 17
                            color: lma.containsMouse ? Qt.alpha(Theme.tone("action"), 0.2) : Qt.alpha(Theme.text, 0.06)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            scale: lma.pressed ? 0.95 : 1
                            Behavior on scale { NumberAnimation { duration: 140 } }
                            Row {
                                id: lkr
                                anchors.centerIn: parent
                                spacing: 6
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter; size: 16; color: Theme.tone("action")
                                    name: ({ "Website": "public", "Source code": "code", "Report a bug": "bug_report", "Flathub": "storefront", "AUR page": "construction" })[lk.modelData.label] ?? "open_in_new"
                                }
                                Txt { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12; font.weight: Font.DemiBold; text: lk.modelData.label }
                            }
                            MouseArea { id: lma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Store.openLink(lk.modelData.url) }
                        }
                    }
                }
                // the facts: version, license, size, votes…
                Grid {
                    visible: sheet.ready && sheet.d.facts.length > 0
                    width: sc.width
                    columns: 2
                    rowSpacing: 10; columnSpacing: 12
                    Repeater {
                        model: sheet.ready ? sheet.d.facts : []
                        Rectangle {
                            id: ft
                            required property var modelData
                            width: (sc.width - 12) / 2; height: 54; radius: 14
                            color: Qt.alpha(Theme.text, 0.04)
                            Column {
                                x: 14; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 28; spacing: 2
                                Sub { font.pixelSize: 11; text: ft.modelData.label }
                                Txt { width: parent.width; font.pixelSize: 13; font.weight: Font.DemiBold; text: ft.modelData.value }
                            }
                        }
                    }
                }
                Item { width: 1; height: 8 }
            }
        }
        SmoothScroll { id: sheetScroll; view: sf }
    }
}
