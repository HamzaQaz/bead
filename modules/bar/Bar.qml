pragma ComponentBehavior: Bound

import QtQuick
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
// the clock, Wi-Fi and Bluetooth (click toggles Bluetooth), power (opens the
// launcher's > actions). The frame steps aside for fullscreen windows.
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
        const e = DesktopEntries.heuristicLookup(id);
        return Quickshell.iconPath(e?.icon || id.toLowerCase(), true);
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

    // ── special workspaces (scratchpads toggled with `caelestia toggle`) ──
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

    SystemClock { id: clock; precision: SystemClock.Minutes }

    // `qs ipc call bar panel wifi|bt|tray|close` on the focused monitor
    signal panelRequested(string name, string screen)
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
            readonly property real barW: 34
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
                    const from = { wifi: wifiBtn, bt: btBtn, tray: trayBtn }[name];
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
                readonly property Item cur: win.shownPanel === "wifi" ? wifiPanel : win.shownPanel === "bt" ? btPanel : trayPanel
                contentW: cur.width
                contentH: cur.implicitHeight
                Keys.onEscapePressed: win.panel = ""

                WifiPanel { id: wifiPanel; visible: win.shownPanel === "wifi"; active: win.panel === "wifi" }
                BluetoothPanel { id: btPanel; visible: win.shownPanel === "bt"; active: win.panel === "bt" }
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
                signal clicked()
                anchors.horizontalCenter: parent?.horizontalCenter
                width: 28; height: 28; radius: 14
                color: btn.lit ? Theme.tone("action") : Qt.alpha(Theme.text, ma.containsMouse ? 0.1 : 0)
                Behavior on color { ColorAnimation { duration: 150 } }
                Icon { anchors.fill: parent; name: btn.icon; size: 17; fill: btn.lit ? 1 : btn.iconFill; color: btn.lit ? Theme.frame : btn.tone }
                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
            }

            // ── top: logo + workspaces ──
            Column {
                id: top
                anchors.horizontalCenter: body.horizontalCenter
                y: win.wallW + 6
                spacing: 8

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 28; height: 28; radius: 14
                    color: Qt.alpha(Theme.text, logoMa.containsMouse ? 0.1 : 0)
                    Behavior on color { ColorAnimation { duration: 150 } }
                    IconImage {
                        id: logo
                        anchors.centerIn: parent
                        implicitSize: 18
                        source: Quickshell.iconPath("cachyos-pi", true)
                        visible: status === Image.Ready
                    }
                    Icon { anchors.centerIn: parent; visible: !logo.visible; name: "deployed_code"; size: 19; fill: 1 }
                    MouseArea { id: logoMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.ipc("launcher", "toggle") }
                }

                // workspaces
                Rectangle {
                    id: wsBox
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 28
                    height: wsCol.height + 6
                    radius: 14
                    color: Qt.alpha(Theme.text, 0.05)

                    // 1-5 always, plus any other workspace in use or active
                    readonly property list<int> ids: {
                        const set = [1, 2, 3, 4, 5];
                        for (const w of Hyprland.workspaces.values) if (w.id > 0 && !set.includes(w.id)) set.push(w.id);
                        if (win.activeWs > 0 && !set.includes(win.activeWs)) set.push(win.activeWs);
                        return set.sort((a, b) => a - b);
                    }
                    readonly property int activeIndex: ids.indexOf(win.activeWs)
                    // each workspace grows with its windows (up to three glyphs)
                    readonly property int glyphH: 18
                    function winsOf(id: int): list<var> { return Hyprland.toplevels.values.filter(t => t.workspace?.id === id); }
                    // the shape on top, then a glyph per window
                    function heightOf(id: int): real { const n = Math.min(3, winsOf(id).length); return 24 + (n ? n * glyphH + 2 : 0); }
                    readonly property var offsets: {
                        const out = [];
                        let y = 0;
                        for (const id of ids) { out.push(y); y += heightOf(id); }
                        return out;
                    }

                    // the highlight springs to the active workspace
                    Rectangle {
                        x: 2
                        y: 3 + (wsBox.offsets[wsBox.activeIndex] ?? 0)
                        width: 24
                        height: wsBox.activeIndex >= 0 ? wsBox.heightOf(win.activeWs) : 24
                        radius: 12
                        visible: wsBox.activeIndex >= 0
                        color: Theme.tone("action")
                        Behavior on y { SpringAnimation { spring: 4.5; damping: 0.32; epsilon: 0.2 } }
                        Behavior on height { SpringAnimation { spring: 4.5; damping: 0.32; epsilon: 0.2 } }
                    }

                    Column {
                        id: wsCol
                        y: 3
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
                                Behavior on height { SpringAnimation { spring: 4.5; damping: 0.32; epsilon: 0.2 } }
                                // Caelestia's marker: dot when empty, square when occupied,
                                // a random shape (morphing in) when focused
                                MaterialShape {
                                    id: marker
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 2
                                    implicitSize: 20
                                    shape: MaterialShape.Circle
                                    color: ws.active ? Theme.frame : ws.wins.length ? Theme.text : Qt.alpha(Theme.text, 0.35)
                                    scale: ws.active ? 2 / 3 : ws.wins.length ? 1 / 3 : 1 / 4
                                    animationDuration: 500
                                    Behavior on scale { SpringAnimation { spring: 4; damping: 0.3; epsilon: 0.005 } }
                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    function reshape(): void {
                                        if (ws.active) shape = root.focusShapes[Math.floor(Math.random() * root.focusShapes.length)];
                                        else shape = Qt.binding(() => ws.wins.length ? MaterialShape.Square : MaterialShape.Circle);
                                    }
                                    Component.onCompleted: reshape()
                                    Connections { target: ws; function onActiveChanged() { marker.reshape(); } }
                                }
                                Column {
                                    y: 24
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    Repeater {
                                        model: ws.wins.slice(0, 3)
                                        Icon {
                                            required property var modelData
                                            width: wsBox.width
                                            height: wsBox.glyphH
                                            name: root.glyph(modelData)
                                            size: 15
                                            fill: ws.active ? 1 : 0
                                            color: ws.active ? Theme.frame : Qt.alpha(Theme.text, 0.8)
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                        }
                                    }
                                }
                                Rectangle { // empty
                                    anchors.centerIn: parent
                                    visible: ws.wins.length === 0
                                    width: 6; height: 6; radius: 3
                                    color: ws.active ? Theme.frame : Qt.alpha(Theme.text, 0.3)
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

                // special workspaces: click toggles, the one open here is lit
                Rectangle {
                    id: spBox
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 28
                    height: spCol.height + 6
                    radius: 14
                    color: Qt.alpha(Theme.text, 0.05)
                    readonly property string open: root.specialOn[win.monitor?.name ?? ""] ?? ""
                    readonly property var shown: root.specials.filter(sp => sp.always
                        || Hyprland.workspaces.values.some(w => w.name === "special:" + sp.name))
                    Column {
                        id: spCol
                        y: 3
                        width: parent.width
                        Repeater {
                            model: spBox.shown
                            Rectangle {
                                id: sp
                                required property var modelData
                                readonly property bool open: spBox.open === modelData.name
                                readonly property bool used: Hyprland.toplevels.values.some(t => t.workspace?.name === "special:" + sp.modelData.name)
                                x: 2
                                width: 24; height: 24; radius: 12
                                color: open ? Theme.tone("action") : Qt.alpha(Theme.text, spMa.containsMouse ? 0.1 : 0)
                                Behavior on color { ColorAnimation { duration: 180 } }
                                Icon {
                                    anchors.centerIn: parent
                                    name: sp.modelData.glyph
                                    size: 15
                                    fill: sp.open ? 1 : 0
                                    color: sp.open ? Theme.frame : sp.used ? Theme.text : Qt.alpha(Theme.text, 0.4)
                                }
                                MouseArea {
                                    id: spMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.execDetached(["caelestia", "toggle", sp.modelData.toggle])
                                }
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
                    visible: parent.here && !!parent.t
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
                spacing: 6

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 2
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
                            width: 28; height: 28
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

                // clock: hours over minutes
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: -3
                    Repeater {
                        model: [Qt.formatTime(clock.date, "hh"), Qt.formatTime(clock.date, "mm")]
                        Text {
                            required property string modelData
                            required property int index
                            anchors.horizontalCenter: parent.horizontalCenter
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: index === 0 ? Font.Bold : Font.Medium
                            font.features: { "tnum": 1 }
                            color: index === 0 ? Theme.text : Theme.subtext
                            text: modelData
                        }
                    }
                }

                // status
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 28
                    height: statusCol.height
                    radius: 14
                    color: Qt.alpha(Theme.text, 0.05)
                    Column {
                        id: statusCol
                        width: parent.width
                        readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
                        readonly property var net: wifi?.networks?.values?.find(n => n.connected) ?? null
                        readonly property bool wired: Networking.devices.values.some(d => d.type === DeviceType.Wired && d.connected)
                        readonly property BluetoothAdapter bt: Bluetooth.defaultAdapter
                        readonly property bool btConnected: (bt?.devices?.values ?? []).some(d => d.connected)
                        BarButton {
                            id: wifiBtn
                            iconFill: 1
                            lit: win.panel === "wifi"
                            onClicked: win.toggle("wifi", wifiBtn)
                            icon: statusCol.wired ? "lan"
                                : !statusCol.net ? "wifi_off"
                                : statusCol.net.signalStrength > 0.66 ? "wifi"
                                : statusCol.net.signalStrength > 0.33 ? "wifi_2_bar" : "wifi_1_bar"
                            tone: statusCol.net || statusCol.wired ? Theme.text : Theme.subtext
                        }
                        BarButton {
                            id: btBtn
                            lit: win.panel === "bt"
                            visible: !!statusCol.bt
                            icon: !statusCol.bt?.enabled ? "bluetooth_disabled" : statusCol.btConnected ? "bluetooth_connected" : "bluetooth"
                            tone: statusCol.bt?.enabled ? Theme.text : Theme.subtext
                            onClicked: win.toggle("bt", btBtn)
                        }
                    }
                }

                BarButton {
                    icon: "power_settings_new"
                    tone: Theme.tone("error")
                    onClicked: root.ipc("launcher", "search", ">")
                }
            }
        }
        }
    }
}
