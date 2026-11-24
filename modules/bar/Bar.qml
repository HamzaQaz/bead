pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import M3Shapes
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services

// The frame and side bar of every monitor. bead draws the whole frame itself
// (Caelestia's border is set to 0): one shape, the frame colour everywhere but
// a rounded hole for the windows, so every inner corner matches. Four
// invisible edge windows reserve the space. The bar lives in the frame's left
// side; top to bottom: logo (opens the launcher),
// workspaces (a glyph per window, like Caelestia's, a springy highlight on the active
// one; click or scroll to switch), the focused window's title, the tray,
// the clock, sound (scroll for volume, middle-click mutes; a red mic while
// something records), Wi-Fi and Bluetooth (each opens its panel), power (the session
// panel). The frame steps aside for fullscreen windows.
Scope {
    id: root

    function ipc(...args): void {
        Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", ...args]);
    }
    function go(ws: int): void { Hyprland.dispatch(`hl.dsp.focus({ workspace = ${Math.max(1, ws)} })`); }

    // ── window icons ──
    function appIcon(t: HyprlandToplevel): string {
        const id = t?.wayland?.appId || t?.lastIpcObject?.class || "";
        if (!id) return "";
        return Apps.iconFor(id);
    }

    // ── window glyphs: a Material Symbol from the app's category, like
    // Caelestia's bar (a few apps by name first) ──
    readonly property var byName: [
        [["discord", "vesktop", "telegram", "signal", "slack", "element"], "forum"],
        [["helium", "firefox", "chrom", "zen", "brave", "librewolf", "vivaldi"], "web"],
        [["spotify"], "music_note"],
        [["steam"], "sports_esports"],
        [["obsidian"], "book_2"],
        [["bitwarden", "keepass"], "key"],
        [["claude"], "auto_awesome"]
    ]
    readonly property var categoryGlyphs: ({
        WebBrowser: "web", Printing: "print", Security: "security", Network: "chat",
        Archiving: "archive", Compression: "archive", Development: "code", IDE: "code",
        TextEditor: "edit_note", Audio: "music_note", Music: "music_note", Player: "music_note",
        Recorder: "mic", Game: "sports_esports", FileTools: "files", FileManager: "files",
        Filesystem: "files", FileTransfer: "files", Settings: "settings", DesktopSettings: "settings",
        HardwareSettings: "settings", TerminalEmulator: "terminal", ConsoleOnly: "terminal",
        Utility: "build", Monitor: "monitor_heart", Midi: "graphic_eq", Mixer: "graphic_eq",
        AudioVideoEditing: "video_settings", AudioVideo: "music_video", Video: "videocam",
        Building: "construction", Graphics: "photo_library", "2DGraphics": "photo_library",
        RasterGraphics: "photo_library", TV: "tv", System: "host", Office: "content_paste"
    })
    function glyph(t: HyprlandToplevel): string {
        const id = (t?.wayland?.appId || t?.lastIpcObject?.class || "").toLowerCase();
        for (const [needles, g] of byName) if (needles.some(n => id.includes(n))) return g;
        const cats = DesktopEntries.heuristicLookup(id)?.categories ?? [];
        for (const [k, g] of Object.entries(categoryGlyphs)) if (cats.includes(k)) return g;
        return "web_asset";
    }

    // ── special workspaces (scratchpads, services/Specials.qml) ──
    readonly property var specials: [
        { name: "music", toggle: "music", glyph: "music_note", always: true },
        { name: "communication", toggle: "communication", glyph: "forum", always: true },
        { name: "todo", toggle: "todo", glyph: "checklist", always: true },
        { name: "sysmon", toggle: "sysmon", glyph: "monitor_heart", always: false },
        { name: "special", toggle: "specialws", glyph: "layers", always: false }
    ]
    // which special workspace each monitor shows ("" for none)
    property var specialOn: ({})
    Connections {
        target: Hyprland
        function onRawEvent(e: var) {
            if (e.name !== "activespecial") return;
            const [ws, mon] = e.data.split(",");
            const m = Object.assign({}, root.specialOn);
            m[mon] = (ws ?? "").replace(/^special:/, "");
            root.specialOn = m;
        }
    }

    // Caelestia's focused-workspace shapes: a new one each time it gets focus
    readonly property list<int> focusShapes: [MaterialShape.Slanted, MaterialShape.Oval, MaterialShape.Pill,
        MaterialShape.Triangle, MaterialShape.Arrow, MaterialShape.Diamond, MaterialShape.Pentagon, MaterialShape.Gem,
        MaterialShape.VerySunny, MaterialShape.Sunny, MaterialShape.Cookie4Sided, MaterialShape.Cookie6Sided,
        MaterialShape.Cookie7Sided, MaterialShape.Cookie9Sided, MaterialShape.Cookie12Sided, MaterialShape.Clover4Leaf,
        MaterialShape.SoftBurst, MaterialShape.Ghostish]

    function mix(a: color, b: color, t: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
    }

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // `qs ipc call bar panel wifi|bt|tray|sound|utils|power|battery|close` on the focused monitor
    signal panelRequested(string name, string screen)
    // Ctrl+Alt+Delete (bead:session): the power panel on the focused monitor
    GlobalShortcut {
        appid: "bead"
        name: "session"
        description: "Session menu"
        onPressed: root.panelRequested("power", Hyprland.focusedMonitor?.name ?? "")
    }
    IpcHandler {
        target: "bar"
        function panel(name: string): void { root.panelRequested(name, Hyprland.focusedMonitor?.name ?? ""); }
    }

    // window details (app ids) aren't pushed: refresh after window events
    Component.onCompleted: Hyprland.refreshToplevels()
    Connections {
        target: Hyprland
        function onRawEvent(e: var) {
            if (/^(openwindow|closewindow|movewindow|windowtitle|activewindow)/.test(e.name)) refresh.restart();
        }
    }
    Timer { id: refresh; interval: 100; onTriggered: Hyprland.refreshToplevels() }

    Variants {
        model: Quickshell.screens

        Scope {
            id: scope
            required property ShellScreen modelData
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(modelData)
            readonly property bool fullscreen: monitor?.activeWorkspace?.hasFullscreen ?? false

            // ── reserved space: one invisible strip per edge ──
            component Edge: PanelWindow {
                property real size: 0
                screen: scope.modelData
                implicitWidth: 1
                implicitHeight: 1
                color: "transparent"
                exclusiveZone: scope.fullscreen ? 0 : Math.ceil(size) // whole px, never less than the frame
                mask: Region {}
                WlrLayershell.layer: WlrLayer.Bottom
                WlrLayershell.namespace: "bead-exclusion"
            }
            Edge { anchors.top: true; size: win.wallW }
            Edge { anchors.right: true; size: win.wallW }
            Edge { anchors.bottom: true; size: win.wallW }
            Edge { anchors.left: true; size: win.fullW }

        PanelWindow {
            id: win
            screen: scope.modelData

            readonly property HyprlandMonitor monitor: scope.monitor
            readonly property bool fullscreen: scope.fullscreen
            readonly property int activeWs: monitor?.activeWorkspace?.id ?? 1

            readonly property real wallW: Theme.frameThickness / devicePixelRatio
            readonly property real barW: 40
            readonly property real fullW: wallW + barW
            readonly property real radius: 25 / devicePixelRatio // inner corners, 25 device px like Caelestia's

            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            visible: !fullscreen
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "bead-frame"
            // typing a Wi-Fi password needs the keyboard while a panel is open
            WlrLayershell.keyboardFocus: panel ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            // only the bar (and an open panel) takes input; the rest lets clicks through
            mask: Region { item: body; Region { item: popout } }

            // ── panels: Wi-Fi, Bluetooth, tray. One at a time; click outside closes ──
            property string panel: ""
            property string shownPanel: ""   // kept while the drawer closes
            property real panelY: 0
            onPanelChanged: {
                if (panel) shownPanel = panel;
                grabbing = false;
                if (panel) grabDelay.restart();
            }
            function toggle(name: string, from: Item): void {
                if (panel === name) { panel = ""; return; }
                panelY = from.mapToItem(win.contentItem, 0, from.height / 2).y;
                panel = name;
            }
            Connections {
                target: root
                function onPanelRequested(name, screen) {
                    if (screen !== scope.modelData.name) return;
                    const from = { wifi: wifiBtn, bt: btBtn, tray: trayBtn, power: powerBtn, sound: soundBtn, utils: utilsBtn, battery: batteryBtn, updates: updatesBtn }[name];
                    if (from) win.toggle(name, from); else win.panel = "";
                }
            }
            property bool grabbing: false
            Timer { id: grabDelay; interval: 120; onTriggered: win.grabbing = win.panel !== "" }
            HyprlandFocusGrab {
                windows: [win]
                active: win.grabbing
                onCleared: win.panel = ""
            }

            Popout {
                id: popout
                x: win.fullW
                open: win.panel !== ""
                anchorY: win.panelY
                frameTop: win.wallW
                frameBottom: win.height - win.wallW
                readonly property Item cur: ({ wifi: wifiPanel, bt: btPanel, tray: trayPanel, power: powerPanel, sound: soundPanel, utils: utilsPanel, battery: batteryPanel, updates: updatesPanel })[win.shownPanel] ?? trayPanel
                panel: cur
                contentW: cur.width
                contentH: cur.implicitHeight
                Keys.onEscapePressed: win.panel = ""

                WifiPanel { id: wifiPanel; visible: win.shownPanel === "wifi"; active: win.panel === "wifi" }
                BluetoothPanel { id: btPanel; visible: win.shownPanel === "bt"; active: win.panel === "bt" }
                SoundPanel { id: soundPanel; visible: win.shownPanel === "sound" }
                UtilitiesPanel { id: utilsPanel; visible: win.shownPanel === "utils"; active: win.panel === "utils"; onDone: win.panel = "" }
                PowerPanel { id: powerPanel; visible: win.shownPanel === "power"; active: win.panel === "power"; onDone: win.panel = "" }
                BatteryPanel { id: batteryPanel; visible: win.shownPanel === "battery" }
                UpdatesPanel { id: updatesPanel; visible: win.shownPanel === "updates"; active: win.panel === "updates"; onDone: win.panel = "" }
                TrayPanel {
                    id: trayPanel
                    visible: win.shownPanel === "tray"
                    onActivated: it => { win.panel = ""; it.activate(); }
                    onMenu: (it, at) => {
                        win.panel = "";
                        const p = at.mapToItem(win.contentItem, at.width + 8, 0);
                        it.display(win, p.x, p.y);
                    }
                }
            }

            // the frame: everything but a rounded hole where the windows go
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    fillColor: Theme.frame
                    // a new palette ripples out (config/Theme.qml): a ring of light
                    // crosses the frame, from the island at the top to the far corners
                    fillGradient: Theme.ripple < 1 ? ring : null
                    strokeColor: "transparent"
                    fillRule: ShapePath.OddEvenFill
                    PathSvg {
                        path: {
                            const W = win.width, H = win.height, r = win.radius;
                            const x0 = win.fullW, y0 = win.wallW, x1 = W - win.wallW, y1 = H - win.wallW;
                            return `M 0 0 H ${W} V ${H} H 0 Z `
                                + `M ${x0 + r} ${y0} H ${x1 - r} A ${r} ${r} 0 0 1 ${x1} ${y0 + r} V ${y1 - r} `
                                + `A ${r} ${r} 0 0 1 ${x1 - r} ${y1} H ${x0 + r} A ${r} ${r} 0 0 1 ${x0} ${y1 - r} `
                                + `V ${y0 + r} A ${r} ${r} 0 0 1 ${x0 + r} ${y0} Z`;
                        }
                    }
                }
            }

            RadialGradient {
                id: ring
                readonly property real at: Theme.ripple
                readonly property color glow: root.mix(Theme.frame, Theme.tone("action"), 0.5 * Math.sin(Math.PI * at))
                centerX: win.width / 2; centerY: 0
                focalX: centerX; focalY: centerY
                centerRadius: Math.hypot(win.width / 2, win.height)
                GradientStop { position: 0; color: Theme.frame }
                GradientStop { position: Math.max(0, ring.at - 0.09); color: Theme.frame }
                GradientStop { position: ring.at; color: ring.glow }
                GradientStop { position: Math.min(1, ring.at + 0.09); color: Theme.frame }
                GradientStop { position: 1; color: Theme.frame }
            }

            // the bar's strip (input region and layout anchor)
            Item {
                id: body
                width: win.fullW
                height: parent.height
            }

            // a round hover-lit button
            component BarButton: Rectangle {
                id: btn
                property string icon: ""
                property color tone: Theme.text
                property real iconFill: 0
                property bool lit: false
                property string iconRef: ""     // see Icon.ref
                property bool pulsing: false    // something's happening: breathe
                readonly property bool hovered: ma.containsMouse
                signal clicked()
                anchors.horizontalCenter: parent?.horizontalCenter
                width: 32; height: 32; radius: 16
                color: btn.lit ? Theme.tone("action") : Qt.alpha(Theme.text, ma.containsMouse ? 0.1 : 0)
                Behavior on color { ColorAnimation { duration: 150 } }
                Icon {
                    id: btnIcon
                    anchors.fill: parent
                    name: btn.icon
                    ref: btn.iconRef
                    size: 18
                    fill: btn.lit ? 1 : btn.iconFill
                    color: btn.lit ? Theme.frame : btn.tone
                    SequentialAnimation on opacity {
                        running: btn.pulsing
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) btnIcon.opacity = 1
                        NumberAnimation { to: 0.35; duration: 650; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
                    }
                }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
            }

            // ── top: logo + workspaces ──
            Column {
                id: top
                anchors.horizontalCenter: body.horizontalCenter
                y: win.wallW + 6
                spacing: 9

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 32; height: 32; radius: 16
                    color: Qt.alpha(Theme.text, logoMa.containsMouse ? 0.1 : 0)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    // bead's mark: "b" and a bead for the full stop
                    Row {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 1
                        spacing: 1
                        Text {
                            id: markB
                            text: "b"
                            font.family: Theme.font
                            font.pixelSize: 19
                            font.weight: Font.Black
                            color: Theme.tone("action")
                        }
                        // the bead comes alive while voice listens (with your voice)
                        // or thinks (breathing), so you can see it under fullscreen too
                        Item {
                            id: beadDot
                            width: 5; height: 5
                            y: markB.baselineOffset - height
                            readonly property bool listening: Voice.state === "listening" || Dictation.state === "listening"
                            readonly property bool busy: Voice.active || Dictation.active
                            readonly property real level: Voice.active ? Voice.level : Dictation.level
                            property real breath: 0
                            SequentialAnimation on breath {
                                running: beadDot.busy && !beadDot.listening
                                loops: Animation.Infinite
                                NumberAnimation { from: 0; to: 1; duration: 520; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 1; to: 0; duration: 520; easing.type: Easing.InOutSine }
                            }
                            Rectangle { // a soft halo
                                anchors.centerIn: parent
                                property real d: 5 * (1.6 + (parent.listening ? 1.8 * Math.min(1, parent.level * 1.3) : 1.2 * parent.breath))
                                width: d; height: d; radius: d / 2
                                color: Theme.tone("action")
                                opacity: parent.busy ? 0.28 : 0
                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                Behavior on d { NumberAnimation { duration: 90 } }
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: 5; height: 5; radius: 2.5
                                color: Theme.tone("action")
                                scale: !parent.busy ? 1 : parent.listening ? 1.15 + 0.5 * Math.min(1, parent.level * 1.3) : 1 + 0.3 * parent.breath
                                Behavior on scale { NumberAnimation { duration: 90 } }
                            }
                        }
                    }
                    MouseArea { id: logoMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.ipc("launcher", "toggle") }
                }

                // workspaces
                Rectangle {
                    id: wsBox
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 32
                    height: wsCol.height + 8
                    radius: 16
                    color: Qt.alpha(Theme.text, 0.05)
                    // blurred and dimmed behind the specials pill
                    property real veil: spBox.open ? 1 : 0
                    Behavior on veil { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                    opacity: 1 - veil * 0.45
                    layer.enabled: veil > 0
                    layer.effect: MultiEffect {
                        blurEnabled: true
                        blur: wsBox.veil * 0.6
                        blurMax: 20
                    }

                    // 1-5 always, plus any other workspace in use or active
                    readonly property list<int> ids: {
                        const set = [1, 2, 3, 4, 5];
                        for (const w of Hyprland.workspaces.values) if (w.id > 0 && !set.includes(w.id)) set.push(w.id);
                        if (win.activeWs > 0 && !set.includes(win.activeWs)) set.push(win.activeWs);
                        return set.sort((a, b) => a - b);
                    }
                    readonly property int activeIndex: ids.indexOf(win.activeWs)
                    // each workspace grows with its windows (up to three glyphs)
                    readonly property int glyphH: 20
                    function winsOf(id: int): list<var> { return Hyprland.toplevels.values.filter(t => t.workspace?.id === id); }
                    // the shape on top, then a glyph per window: the last glyph sits as far
                    // from the bottom as the shape does from the top (14px, the pill's
                    // radius), so the highlight's ends match
                    function heightOf(id: int): real { const n = Math.min(3, winsOf(id).length); return n ? 26 + n * glyphH + 4 : 28; }
                    readonly property var offsets: {
                        const out = [];
                        let y = 0;
                        for (const id of ids) { out.push(y); y += heightOf(id); }
                        return out;
                    }

                    // the highlight glides to the active workspace; retargeting
                    // mid-move carries on from where it is, so spamming stays smooth
                    Rectangle {
                        id: hl
                        x: 2
                        y: 4 + (wsBox.offsets[wsBox.activeIndex] ?? 0)
                        width: 28
                        height: wsBox.activeIndex >= 0 ? wsBox.heightOf(win.activeWs) : 28
                        radius: 14
                        visible: wsBox.activeIndex >= 0
                        color: Theme.tone("action")
                        Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                        Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    }

                    Column {
                        id: wsCol
                        y: 4
                        width: parent.width
                        Repeater {
                            id: wsRep
                            model: wsBox.ids
                            Item {
                                id: ws
                                required property int modelData
                                readonly property int num: modelData
                                readonly property bool active: num === win.activeWs
                                readonly property var wins: wsBox.winsOf(num)
                                width: wsBox.width
                                height: wsBox.heightOf(num)
                                Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                // how much of this workspace the highlight covers right now
                                // (0-1): colours and size follow the highlight itself, not
                                // the focus, so they never run ahead of it
                                readonly property real cover: {
                                    if (!hl.visible) return 0;
                                    const top = wsCol.y + ws.y, bot = top + ws.height;
                                    return Math.max(0, Math.min(hl.y + hl.height, bot) - Math.max(hl.y, top)) / ws.height;
                                }
                                // Caelestia's marker: dot when empty, square when occupied,
                                // a random shape (morphing in) when focused
                                MaterialShape {
                                    id: marker
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 4
                                    implicitSize: 20
                                    shape: MaterialShape.Circle
                                    readonly property real base: ws.wins.length ? 1 / 3 : 1 / 4
                                    color: root.mix(ws.wins.length ? Theme.text : Qt.alpha(Theme.text, 0.35), Theme.frame, ws.cover)
                                    scale: base + (2 / 3 - base) * ws.cover
                                    animationDuration: 400
                                    function reshape(): void {
                                        if (ws.active) shape = root.focusShapes[Math.floor(Math.random() * root.focusShapes.length)];
                                        else shape = Qt.binding(() => ws.wins.length ? MaterialShape.Square : MaterialShape.Circle);
                                    }
                                    Component.onCompleted: reshape()
                                    Connections { target: ws; function onActiveChanged() { marker.reshape(); } }
                                }
                                Column {
                                    y: 26
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    Repeater {
                                        model: ws.wins.slice(0, 3)
                                        Icon {
                                            required property var modelData
                                            width: wsBox.width
                                            height: wsBox.glyphH
                                            name: root.glyph(modelData)
                                            size: 16
                                            fill: ws.cover > 0.5 ? 1 : 0
                                            color: root.mix(Qt.alpha(Theme.text, 0.8), Theme.frame, ws.cover)
                                        }
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.go(ws.num)
                                }
                            }
                        }
                    }
                    WheelHandler {
                        onWheel: e => root.go(win.activeWs + (e.angleDelta.y < 0 ? 1 : -1))
                    }
                }

            }

            // special workspaces: while one is open here, this pill floats over
            // the top of the workspaces (which blur behind it), as in Caelestia.
            // Click switches or hides; the open one is lit.
            Rectangle {
                id: spBox
                anchors.horizontalCenter: body.horizontalCenter
                y: top.y + wsBox.y
                z: 2
                width: 32
                height: spCol.height + 8
                visible: opacity > 0.01
                opacity: open ? 1 : 0
                scale: open ? 1 : 0.85
                transformOrigin: Item.Top
                radius: 16
                color: Qt.alpha(Theme.frame, 0.9)
                border.width: 1
                border.color: Qt.alpha(Theme.text, 0.08)
                Behavior on opacity { NumberAnimation { duration: 220 } }
                Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                readonly property string open: root.specialOn[win.monitor?.name ?? ""] ?? ""
                readonly property var shown: root.specials.filter(sp => sp.always
                    || Hyprland.workspaces.values.some(w => w.name === "special:" + sp.name))
                Column {
                    id: spCol
                    spacing: 3
                    y: 4
                    width: parent.width
                    Repeater {
                        model: spBox.shown
                        Rectangle {
                            id: sp
                            required property var modelData
                            readonly property bool open: spBox.open === modelData.name
                            readonly property bool used: Hyprland.toplevels.values.some(t => t.workspace?.name === "special:" + sp.modelData.name)
                            x: 2
                            width: 28; height: 28; radius: 14
                            color: open ? Theme.tone("action") : Qt.alpha(Theme.text, spMa.containsMouse ? 0.1 : 0)
                            Behavior on color { ColorAnimation { duration: 180 } }
                            Icon {
                                anchors.centerIn: parent
                                name: sp.modelData.glyph
                                size: 16
                                fill: sp.open ? 1 : 0
                                color: sp.open ? Theme.frame : sp.used ? Theme.text : Qt.alpha(Theme.text, 0.4)
                            }
                            MouseArea {
                                id: spMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Specials.toggle(sp.modelData.toggle)
                            }
                        }
                    }
                }
            }

            // ── middle: the focused window's title, written downwards ──
            Item {
                x: 0
                anchors.top: top.bottom
                anchors.topMargin: 14
                anchors.bottom: bottom.top
                anchors.bottomMargin: 14
                width: win.fullW
                clip: true
                readonly property HyprlandToplevel t: Hyprland.activeToplevel
                readonly property bool here: (t?.workspace?.id ?? -999) === win.activeWs
                Text {
                    id: title
                    visible: Settings.showTitle && parent.here && !!parent.t
                    rotation: 90
                    transformOrigin: Item.TopLeft
                    x: (win.fullW + height) / 2
                    width: Math.min(implicitWidth, parent.height)
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: Theme.subtext
                    text: parent.t?.title ?? ""
                }
            }

            // ── bottom: tray, clock, status, power ──
            Column {
                id: bottom
                anchors.horizontalCenter: body.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: win.wallW + 6
                spacing: 6 // the pills sit together, one cluster above power

                // tools: utilities, the tray panel, pinned tray apps
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 32
                    height: toolsCol.height + 4
                    radius: 16
                    color: Qt.alpha(Theme.text, 0.05)
                Column {
                    id: toolsCol
                    y: 2
                    width: parent.width
                    spacing: 0
                    // utilities: screenshots, recording, quick toggles
                    BarButton {
                        id: utilsBtn
                        icon: Recorder.recording ? "radio_button_checked" : "widgets"
                        tone: Recorder.recording ? Theme.tone("error") : Theme.text
                        pulsing: Recorder.recording
                        lit: win.panel === "utils"
                        onClicked: win.toggle("utils", utilsBtn)
                    }
                    // updates waiting: only then, with how many
                    BarButton {
                        id: updatesBtn
                        visible: Updates.count > 0
                        icon: "system_update_alt"
                        tone: Updates.restart ? Theme.tone("warning") : Theme.text
                        lit: win.panel === "updates"
                        onClicked: win.toggle("updates", updatesBtn)
                        Rectangle {
                            x: parent.width - width + 1; y: -1
                            width: Math.max(14, n.implicitWidth + 6); height: 14; radius: 7
                            color: Updates.restart ? Theme.tone("warning") : Theme.tone("action")
                            Text { id: n; anchors.centerIn: parent; font.family: Theme.font; font.pixelSize: 8; font.weight: Font.Bold; color: Theme.frame; text: Updates.count > 99 ? "99+" : Updates.count }
                        }
                    }
                    // the tray panel: every app, pin some to the bar
                    BarButton {
                        id: trayBtn
                        visible: SystemTray.items.values.length > 0
                        icon: "apps"
                        lit: win.panel === "tray"
                        onClicked: win.toggle("tray", trayBtn)
                    }
                    Repeater {
                        model: SystemTray.items.values.filter(i => TrayPins.pinned.includes(i.id))
                        MouseArea {
                            id: tray
                            required property SystemTrayItem modelData
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 32; height: 32
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                            onClicked: e => {
                                if (e.button === Qt.RightButton || tray.modelData.onlyMenu) {
                                    const p = tray.mapToItem(null, tray.width + 6, 0);
                                    tray.modelData.display(win, p.x, p.y);
                                } else if (e.button === Qt.MiddleButton) tray.modelData.secondaryActivate();
                                else tray.modelData.activate();
                            }
                            onWheel: e => tray.modelData.scroll(e.angleDelta.y / 120, false)
                            Rectangle {
                                anchors.fill: parent
                                radius: 14
                                color: Qt.alpha(Theme.text, tray.containsMouse ? 0.1 : 0)
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            IconImage {
                                anchors.centerIn: parent
                                implicitSize: 16
                                source: tray.modelData.icon
                            }
                        }
                    }
                }
                }

                // clock: hours, a sideways colon that fades with the seconds, minutes
                Rectangle {
                    id: barClock
                    // where it is, for the lock's clock to fly to on unlock
                    Connections {
                        target: Lock
                        function onShownChanged(): void {
                            if (!Lock.shown) return;
                            const p = barClock.mapToItem(null, 0, 0);
                            const m = Object.assign({}, Lock.barClocks);
                            m[scope.modelData.name] = Qt.rect(p.x, p.y, barClock.width, barClock.height);
                            Lock.barClocks = m;
                        }
                    }
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 32
                    height: clockCol.height + 16
                    radius: 16
                    color: Qt.alpha(Theme.text, 0.05)
                Column {
                    id: clockCol
                    anchors.centerIn: parent
                    spacing: 2
                    component ClockText: Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        font.family: Theme.font
                        font.pixelSize: 14
                        font.features: { "tnum": 1 }
                    }
                    ClockText { font.weight: Font.Bold; color: Theme.text; text: Qt.formatTime(clock.date, "hh") }
                    // a sideways colon, fading with the seconds
                    Row {
                        id: tick
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 3
                        opacity: secs.date.getSeconds() % 2 ? 0.25 : 0.7
                        Behavior on opacity { NumberAnimation { duration: 450; easing.type: Easing.InOutSine } }
                        SystemClock { id: secs; precision: SystemClock.Seconds }
                        Repeater {
                            model: 2
                            Rectangle { width: 2.5; height: 2.5; radius: 1.25; color: Theme.text }
                        }
                    }
                    ClockText { font.weight: Font.Medium; color: Theme.subtext; text: Qt.formatTime(clock.date, "mm") }
                }
                }

                // status
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 32
                    height: statusCol.height
                    radius: 16
                    color: Qt.alpha(Theme.text, 0.05)
                    Column {
                        id: statusCol
                        width: parent.width
                        readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
                        readonly property var net: wifi?.networks?.values?.find(n => n.connected) ?? null
                        readonly property bool wired: Networking.devices.values.some(d => d.type === DeviceType.Wired && d.connected)
                        readonly property BluetoothAdapter bt: Bluetooth.defaultAdapter
                        readonly property bool btConnected: (bt?.devices?.values ?? []).some(d => d.connected)
                        readonly property bool btBusy: !!bt?.enabled && (bt.discovering || (bt.devices?.values ?? []).some(d =>
                            d.pairing || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting))
                        readonly property bool wifiConnecting: (wifi?.networks?.values ?? []).some(n => n.stateChanging || n.state === ConnectionState.Connecting)
                        readonly property bool wifiSearching: Networking.wifiEnabled && !!wifi && !net && !wired
                        // the bars fill up while connecting (slower while just looking)
                        Sweep {
                            id: wifiSweep
                            frames: ["wifi_1_bar", "wifi_2_bar", "wifi"]
                            running: statusCol.wifiConnecting || statusCol.wifiSearching
                            interval: statusCol.wifiConnecting ? 220 : 450
                        }
                        BarButton {
                            id: soundBtn
                            iconRef: "volume_up"
                            icon: Audio.levelGlyph(Audio.volume, Audio.muted)
                            tone: Audio.muted ? Theme.subtext : Theme.text
                            lit: win.panel === "sound"
                            onClicked: win.toggle("sound", soundBtn)
                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.MiddleButton
                                onClicked: Audio.toggleMute()
                                onWheel: e => Audio.setVolume(Audio.volume + (e.angleDelta.y > 0 ? 0.05 : -0.05))
                            }
                        }
                        // wireless devices' batteries: the lowest one's level (click for all)
                        BarButton {
                            id: batteryBtn
                            readonly property var d: Osd.lowest
                            readonly property int level: d ? Osd.pct(d) : 100
                            readonly property bool charging: !!d && Osd.charging(d)
                            visible: !!d
                            lit: win.panel === "battery"
                            icon: Osd.batteryGlyph(level, charging)
                            iconRef: "battery_full"
                            iconFill: 1
                            tone: level <= 10 && !charging ? Theme.tone("error") : level <= 20 && !charging ? Theme.tone("warning") : Theme.text
                            pulsing: level <= 10 && !charging
                            onClicked: win.toggle("battery", batteryBtn)
                        }
                        BarButton {
                            id: wifiBtn
                            iconFill: 1
                            lit: win.panel === "wifi"
                            onClicked: win.toggle("wifi", wifiBtn)
                            iconRef: "wifi"
                            icon: wifiSweep.running && !statusCol.wired ? wifiSweep.current
                                : statusCol.wired ? "lan"
                                : !statusCol.net ? "wifi_off"
                                : statusCol.net.signalStrength > 0.66 ? "wifi"
                                : statusCol.net.signalStrength > 0.33 ? "wifi_2_bar" : "wifi_1_bar"
                            tone: statusCol.net || statusCol.wired ? Theme.text : Theme.subtext
                        }
                        BarButton {
                            id: btBtn
                            lit: win.panel === "bt"
                            // only while it's on (Utilities has the switch), or its panel is open
                            visible: !!statusCol.bt && (statusCol.bt.enabled || win.panel === "bt")
                            icon: !statusCol.bt?.enabled ? "bluetooth_disabled" : statusCol.btBusy ? "bluetooth_searching"
                                : statusCol.btConnected ? "bluetooth_connected" : "bluetooth"
                            pulsing: statusCol.btBusy
                            tone: statusCol.bt?.enabled ? Theme.text : Theme.subtext
                            onClicked: win.toggle("bt", btBtn)
                        }
                    }
                }

                BarButton {
                    id: powerBtn
                    icon: "power_settings_new"
                    // quiet until you reach for it
                    tone: hovered || lit ? Theme.tone("error") : Theme.subtext
                    lit: win.panel === "power"
                    onClicked: win.toggle("power", powerBtn)
                }
            }
        }
        }
    }
}
