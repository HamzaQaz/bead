pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Wayland
import qs.components
import qs.config
import qs.modules.dashboard
import qs.services

// The island: one shape hanging from the top-center of the screen frame (clean
// rounded joints) that morphs between three states:
//   rest      a slim pill: the time and weather, or what is playing
//   activity  volume / mute / mic / brightness changed: icon, level, value
//             (scroll on it or drag the bar to adjust); workspace switched:
//             a dot per workspace, the current one long; a new notification;
//             a timer finishing; a screen recording starting
//   live      a running timer / stopwatch or screen recording rides on the pill
//             (click: pause / stop)
//   passkey   keyhold asks to approve a passkey: the island becomes the prompt
//             (services/Passkey.qml)
//   launcher  tap Super (global shortcut bead:launcher) or IPC "launcher":
//             apps, maths, > actions (LauncherView.qml); click outside closes
//   open      hover it (or the top edge) a moment: it grows into the dashboard
// It lives on one monitor ($BEAD_ISLAND_SCREEN, default DP-1). Hidden (IPC
// "island", saved across restarts), when a window on that monitor reaches up
// under it (so it never covers a URL bar), or under a fullscreen window, the
// resting pill tucks into the frame; activities still show, and hovering the top edge
// still opens the dashboard (not under fullscreen).
// IPC targets: "island" (toggle | show | hide), "dashboard" (toggle | open |
// close | tab N), "osd" (brightnessUp/Down).
Scope {
    id: root

    // the island's monitor
    readonly property string homeName: Settings.home
    readonly property ShellScreen home: Quickshell.screens.find(s => s.name === homeName) ?? Quickshell.screens[0]

    // ── hidden (keybind), saved in $XDG_STATE_HOME/bead/island.json ──
    property bool hidden: false
    IpcHandler {
        target: "island"
        function toggle(): void { root.hidden = !root.hidden; }
        function show(): void { root.hidden = false; }
        function hide(): void { root.hidden = true; }
    }
    property bool hiddenLoaded: false
    onHiddenChanged: if (hiddenLoaded) hiddenStore.setText(JSON.stringify({ hidden: hidden }))
    FileView {
        id: hiddenStore
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/bead/island.json"
        blockLoading: true
        printErrors: false
        atomicWrites: true
        onLoaded: { try { root.hidden = !!JSON.parse(text()).hidden; } catch (e) {} root.hiddenLoaded = true; }
        onLoadFailed: root.hiddenLoaded = true
    }

    // ── window manager ──
    readonly property HyprlandMonitor homeMonitor: Hyprland.monitors.values.find(m => m.name === home?.name) ?? null
    readonly property bool fullscreen: homeMonitor?.activeWorkspace?.hasFullscreen ?? false
    readonly property HyprlandWorkspace workspace: Hyprland.focusedWorkspace
    readonly property bool special: (workspace?.id ?? 1) < 0
    // existing normal workspaces (Hyprland drops empty ones) plus the current
    readonly property list<int> workspaceIds: {
        const ids = Hyprland.workspaces.values.map(w => w.id).filter(id => id > 0);
        if (workspace && workspace.id > 0 && !ids.includes(workspace.id)) ids.push(workspace.id);
        return ids.sort((a, b) => a - b).slice(0, 12);
    }
    onWorkspaceChanged: if (ready) flash("workspace", "")
    Connections {
        target: Hyprland
        function onRawEvent(e: var) {
            // special workspaces (SUPER+S…) toggle without changing the focused one
            if (root.ready && e.name === "activespecial") root.flash("workspace", "");
            if (/^(openwindow|closewindow|movewindow|changefloatingmode|fullscreen|workspace|activespecial|activewindow|focusedmon|moveworkspace|togglegroup|minimized)/.test(e.name))
                geometryTimer.restart();
        }
    }

    // ── windows under the island ──
    // the island's footprint in compositor pixels, below the frame: the resting
    // pill's height and a generous width (it grows with what it shows)
    readonly property real uiScale: parseFloat(Quickshell.env("QT_SCALE_FACTOR") || "1") || 1
    readonly property real zoneHalfW: 170 * uiScale
    readonly property real zoneBottom: Theme.frameThickness + 34 * uiScale + 4
    property bool covered: false
    function checkCovered(): void {
        const m = homeMonitor;
        if (!m) { covered = false; return; }
        const mo = m.lastIpcObject ?? {};
        const scale = mo.scale ?? 1;
        const mx = mo.x ?? 0, my = mo.y ?? 0, mw = (mo.width ?? 1920) / scale;
        const cx = mx + mw / 2;
        const ws = m.activeWorkspace?.id;
        const special = mo.specialWorkspace?.name ?? "";
        covered = Hyprland.toplevels.values.some(t => {
            const o = t.lastIpcObject;
            if (!o?.mapped || o.hidden || !o.at || !o.size) return false;
            if (o.workspace?.id !== ws && !(special && o.workspace?.name === special)) return false;
            const x = o.at[0], y = o.at[1], w = o.size[0];
            return y - my < root.zoneBottom && x < cx + root.zoneHalfW && x + w > cx - root.zoneHalfW;
        });
    }
    // geometry isn't pushed: refresh after window events (debounced), and poll
    // slowly for floating windows being dragged around
    Timer {
        id: geometryTimer
        interval: 80
        onTriggered: { Hyprland.refreshMonitors(); Hyprland.refreshToplevels(); settleTimer.restart(); }
    }
    Timer { id: settleTimer; interval: 120; onTriggered: root.checkCovered() }
    Timer { interval: 1500; repeat: true; running: true; onTriggered: geometryTimer.restart() }

    // ── launcher ──
    property bool launcherOpen: false
    property string launcherMode: ""
    onLauncherOpenChanged: if (!launcherOpen) { Ask.clear(); launcherMode = ""; } // closing stops a question in flight
    IpcHandler {
        target: "launcher"
        function toggle(): void { root.launcherOpen = !root.launcherOpen; }
        function open(): void { root.launcherOpen = true; }
        function close(): void { root.launcherOpen = false; }
        // open asking Claude straight away
        function ask(question: string): void {
            search("?" + question);
            Ask.ask(question);
        }
        // open in a mode (";" clipboard, ":" emoji); again closes it
        function mode(prefix: string): void {
            if (root.launcherOpen && root.launcherMode === prefix) { root.launcherOpen = false; return; }
            search(prefix);
            root.launcherMode = prefix;
        }
        // open with text already typed
        function search(text: string): void {
            root.launcherSeed = text;
            if (root.launcherOpen) root.launcherSeedChanged();
            root.launcherOpen = true;
        }
    }
    property string launcherSeed: ""
    property real lastTap: 0
    function launcherTap(): void {
        const now = Date.now();
        if (now - lastTap < 300) return;
        lastTap = now;
        launcherOpen = !launcherOpen;
    }
    // bound in Hyprland as hl.dsp.global("bead:launcher") on a Super tap
    GlobalShortcut {
        appid: "bead"
        name: "launcher"
        description: "Toggle the launcher"
        // a real Super tap (a release bind) arrives as "released" only, a
        // dispatched one as "pressed" only: either toggles, a pair counts once
        onPressed: root.launcherTap()
        onReleased: root.launcherTap()
    }

    // ── dashboard ──
    readonly property ShellScreen focused: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    property string pinnedOn: ""           // screen opened from IPC (stays until closed)
    property int tab: 0
    property int openCount: 0              // islands currently open
    IpcHandler {
        target: "dashboard"
        function toggle(): void { root.pinnedOn = root.pinnedOn ? "" : root.home.name; }
        function open(): void { root.pinnedOn = root.home.name; }
        function close(): void { root.pinnedOn = ""; }
        function tab(n: int): void { root.tab = Math.max(0, Math.min(6, n)); root.pinnedOn = root.home.name; }
    }

    SystemClock { id: clock; precision: SystemClock.Seconds }

    property MprisPlayer picked: null
    // media keys (bead:mediaToggle/Next/Prev/Stop): the player the island shows
    GlobalShortcut { appid: "bead"; name: "mediaToggle"; description: "Play / pause"; onPressed: if (root.player?.canTogglePlaying) root.player.togglePlaying() }
    GlobalShortcut { appid: "bead"; name: "mediaNext"; description: "Next track"; onPressed: if (root.player?.canGoNext) root.player.next() }
    GlobalShortcut { appid: "bead"; name: "mediaPrev"; description: "Previous track"; onPressed: if (root.player?.canGoPrevious) root.player.previous() }
    GlobalShortcut { appid: "bead"; name: "mediaStop"; description: "Stop playback"; onPressed: if (root.player?.canControl) root.player.stop() }

    readonly property MprisPlayer player: (picked && Mpris.players.values.includes(picked) ? picked : null)
        ?? Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property bool playing: player?.isPlaying ?? false

    // the pill shows the track briefly when a song starts or changes (or while
    // hovered), then goes back to the time; a tiny equaliser stays while playing
    property bool peek: false
    function peekMedia(): void { if (playing) { peek = true; peekTimer.restart(); } }
    Timer { id: peekTimer; interval: 5000; onTriggered: root.peek = false }
    onPlayingChanged: playing ? peekMedia() : peek = false
    Connections {
        target: root.player
        function onTrackTitleChanged() { root.peekMedia(); }
    }

    Binding { target: SysStats; property: "active"; value: root.openCount > 0 }
    onOpenCountChanged: if (openCount > 0) Weather.refresh()
    Component.onCompleted: Weather.refresh()
    Timer { interval: 20 * 60 * 1000; repeat: true; running: true; onTriggered: Weather.refresh() }
    Timer { // MPRIS doesn't push positions
        interval: 1000
        repeat: true
        running: root.openCount > 0 && root.playing
        onTriggered: root.player?.positionChanged()
    }

    // ── activity (volume / mic / brightness) ──
    property string activity: ""       // "" | volume | mic | brightness | workspace
    property string activityOn: ""     // the screen it is about (brightness)
    // what (volume|mic|brightness|workspace|notif|timerdone|recstart),
    // the screen it is about (brightness), how long to show it (ms)
    function flash(what, screenName, ms) {
        if (openCount > 0 && what !== "workspace") return; // the dashboard shows it already
        activityOn = screenName || focused.name;
        activity = what;
        activityTimer.interval = ms || 1600;
        activityTimer.restart();
    }
    property var peekEntry: null
    // notifications arriving while one shows wait their turn (the newest 5),
    // each shown a little shorter while more are waiting
    property list<var> peekQueue: []
    function peekAt(e: var): void {
        if (openCount > 0) { peekQueue = []; return; } // the dashboard lists them already
        peekEntry = e;
        flash("notif", "", peekQueue.length ? 2200 : 3500);
    }
    Connections {
        target: Notifs
        function onPosted(e: var) {
            if (root.activity === "timerdone") return; // its own alarm is showing
            if (root.activity === "notif") root.peekQueue = [...root.peekQueue, e].slice(-5);
            else root.peekAt(e);
        }
    }
    property real doneTotal: 0

    // ── toasts: a short line with an icon (Caps Lock, config reload, `bead toast`) ──
    property string toastIcon: ""
    property string toastText: ""
    property string toastTone: "info"
    function toast(icon: string, text: string, tone: string, ms: int): void {
        if (activity === "timerdone") return; // its own alarm is showing
        toastIcon = icon;
        toastText = text;
        toastTone = tone || "info";
        flash("toast", "", ms || 1600);
    }
    Connections {
        target: CapsLock
        function onToggled(on: bool) {
            root.toast("keyboard_capslock", on ? "Caps Lock on" : "Caps Lock off", on ? "action" : "loading", 1300);
        }
    }
    Connections {
        target: Discord
        function onJoined(name: string) { root.toast("headset_mic", "Joined " + name, "action", 1800); }
        function onLeft() { root.toast("call_end", "Left the call", "loading", 1500); }
        function onMuteToggled(mute: bool) { root.toast(mute ? "mic_off" : "mic", mute ? "Discord muted" : "Discord unmuted", mute ? "error" : "action", 1300); }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") configErrors.running = true;
        }
    }
    Process {
        id: configErrors
        command: ["hyprctl", "configerrors"]
        stdout: StdioCollector {
            onStreamFinished: {
                const errs = text.split("\n").map(l => l.trim()).filter(l => l);
                if (errs.length)
                    root.toast("error", errs.length === 1 ? "Config error: " + errs[0].slice(0, 60) : errs.length + " config errors", "error", 4000);
                else
                    root.toast("check_circle", "Config reloaded", "success", 1800);
            }
        }
    }
    Connections {
        target: Countdown
        function onFinished(t: real) { root.doneTotal = t; root.flash("timerdone", "", 5000); }
    }
    Connections {
        target: Recorder
        function onRecordingChanged() { if (Recorder.recording && root.ready) root.flash("recstart", "", 2200); }
    }
    Timer {
        id: activityTimer
        interval: 1600
        onTriggered: {
            if (root.peekQueue.length) { // the next waiting notification
                const next = root.peekQueue[0];
                root.peekQueue = root.peekQueue.slice(1);
                root.peekAt(next);
                return;
            }
            root.activity = "";
        }
    }

    property bool ready: false // ignore what PipeWire reports at startup
    Timer { interval: 1500; running: true; onTriggered: root.ready = true }
    Connections {
        target: Audio
        function onVolumeChanged() { if (root.ready) root.flash("volume", ""); }
        function onMutedChanged() { if (root.ready) root.flash("volume", ""); }
        function onMicMutedChanged() { if (root.ready) root.flash("mic", ""); }
    }
    Connections {
        target: Brightness
        function onChanged(screenName: string, value: real) {
            if (root.ready) root.flash("brightness", screenName);
        }
    }
    IpcHandler {
        target: "osd"
        function brightnessUp(): void { Brightness.change(root.focused, 5); }
        function brightnessDown(): void { Brightness.change(root.focused, -5); }
        // a one-line toast in the island: `bead toast TEXT [ICON] [TONE]`
        function toast(text: string, icon: string, tone: string): void { root.toast(icon || "info", text, tone || "info", 2200); }
    }

    // which level the pill shows, kept while it fades out (activity is "" by then)
    property string levelKind: "volume"
    onActivityChanged: if (["volume", "mic", "brightness"].includes(activity)) levelKind = activity
    readonly property real activityLevel: levelKind === "brightness" ? (Brightness.values[activityOn] ?? 0.5)
        : levelKind === "mic" ? (Audio.micMuted ? 0 : 1)
        : (Audio.muted ? 0 : Audio.volume)
    readonly property bool activityDim: levelKind === "mic" ? Audio.micMuted : levelKind === "volume" && Audio.muted
    readonly property string activityIcon: levelKind === "brightness" ? "light_mode"
        : levelKind === "mic" ? (Audio.micMuted ? "mic_off" : "mic")
        : Audio.muted || Audio.volume <= 0 ? "volume_off" : Audio.volume < 0.5 ? "volume_down" : "volume_up"

    readonly property ShellScreen activityScreen: Quickshell.screens.find(s => s.name === activityOn) ?? home
    function nudge(dir: int): void {
        if (activity === "brightness") Brightness.change(activityScreen, dir * 5);
        else Audio.setVolume(Audio.volume + dir * 0.05);
    }

    Variants {
        model: root.home ? [root.home] : []

        PanelWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData

            property bool hovered: false
            property bool expanded: false       // hovered long enough
            readonly property bool open: expanded || root.pinnedOn === modelData.name
            readonly property bool showsActivity: root.activity !== ""
            readonly property bool tucked: root.hidden || root.fullscreen || root.covered
            readonly property string state: Passkey.active ? "passkey" : root.launcherOpen ? "launcher" : open ? "open" : showsActivity ? "activity" : tucked ? "tucked" : "rest"
            onStateChanged: {
                if (state === "launcher") { launcherView.reset(root.launcherSeed); root.launcherSeed = ""; grabTimer.restart(); }
                else { grabTimer.stop(); grabbing = false; }
                if (state === "passkey" || state === "launcher") focusTimer.restart();
            }
            // the layer gets keyboard focus a moment after it asks for it
            Timer {
                id: focusTimer
                interval: 120
                onTriggered: win.state === "passkey" ? passkeyView.focusField() : launcherView.focusField()
            }
            Connections {
                target: root
                function onLauncherSeedChanged() {
                    if (win.state === "launcher" && root.launcherSeed) { launcherView.reset(root.launcherSeed); root.launcherSeed = ""; }
                }
            }
            // a click anywhere else closes the launcher. The grab starts once the
            // launcher has grown: started while the island is tucked (no input
            // region yet) Hyprland clears it at once
            property bool grabbing: false
            Timer { id: grabTimer; interval: 250; onTriggered: win.grabbing = win.state === "launcher" }
            HyprlandFocusGrab {
                windows: [win]
                active: win.grabbing
                onCleared: if (win.grabbing) { win.grabbing = false; root.launcherOpen = false; }
            }
            readonly property bool showMedia: root.playing && (root.peek || hovered)
            onOpenChanged: root.openCount += open ? 1 : -1

            // hover a moment before it grows (passing by doesn't open it)
            Timer { id: openTimer; interval: 220; onTriggered: win.expanded = true }
            Timer {
                id: leaveTimer
                interval: 300
                onTriggered: {
                    win.hovered = false;
                    win.expanded = false;
                    if (!activityTimer.running && win.showsActivity) root.activity = "";
                }
            }
            // one state for the edge strip and the island together: moving from
            // one to the other must not count as leaving
            readonly property bool pointerIn: edgeHover.hovered || boxHover.hovered
            onPointerInChanged: pointerIn ? enterHover() : leaveHover()
            function enterHover(): void {
                if (root.fullscreen && !open) return;
                leaveTimer.stop();
                hovered = true;
                if (!expanded) openTimer.restart();
            }
            function leaveHover(): void {
                openTimer.stop();
                leaveTimer.restart();
            }

            readonly property real wallW: Theme.frameThickness / devicePixelRatio
            readonly property real openW: 900
            readonly property real openH: 340
            anchors.top: true
            implicitWidth: openW + 80
            implicitHeight: openH + wallW + 60
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "bead-island"
            WlrLayershell.keyboardFocus: Passkey.asking || root.launcherOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            // input: the island itself, plus the top frame strip (hover opens it)
            mask: Region {
                item: win.state === "tucked" ? null : hit
                Region { item: root.fullscreen ? null : edge }
            }

            // ── size, springing between the states ──
            readonly property real restW: Math.max(132, restRow.implicitWidth + 36)
            readonly property real activityW: root.activity === "workspace" ? Math.max(120, wsRow.implicitWidth + 44)
                : root.activity === "notif" ? 400
                : root.activity === "timerdone" || root.activity === "recstart" || root.activity === "toast" ? eventRow.implicitWidth + 48
                : 330
            Spring {
                id: sw
                to: win.state === "passkey" ? passkeyView.wantW : win.state === "launcher" ? launcherView.wantW : win.state === "open" ? win.openW : win.state === "activity" ? win.activityW : win.restW
                settleWhenShrinking: true
                duration: Motion.dur * 0.9
            }
            Spring {
                id: sh
                to: win.state === "passkey" ? passkeyView.wantH : win.state === "launcher" ? launcherView.wantH : win.state === "open" ? win.openH
                    : win.state === "activity" ? (root.activity === "notif" ? 58 : 46) : win.state === "tucked" ? 0 : 34
                settleWhenShrinking: true
                duration: Motion.dur * 0.9
            }
            readonly property real radius: Math.min(28, sh.value / 2)

            // the shape: island + the frame's top edge, joined by rounded fillets
            ShaderEffect {
                anchors.fill: parent
                visible: sh.value > 0.5
                fragmentShader: Qt.resolvedUrl("../../shaders/goo.frag.qsb")
                property size size: Qt.size(width, height)
                // the top runs up into the frame (hidden there), so only the
                // bottom corners are rounded
                property vector4d pill: Qt.vector4d((width - sw.value) / 2, win.wallW - win.radius, sw.value, sh.value + win.radius)
                property vector4d body: Qt.vector4d(0, 0, 0, 0)
                property vector4d wall: Qt.vector4d(0, 0, width, win.wallW)
                property real radius: win.radius
                property real goo: 16
                property color fill: Theme.frame
                property color shadow: "transparent"
            }

            Item {
                id: edge
                x: (win.width - win.openW) / 2
                width: win.openW
                height: win.wallW
                HoverHandler { id: edgeHover }
            }

            // the island's box: content is clipped to it, so it is revealed as it grows
            Item {
                id: box
                x: (win.width - sw.value) / 2
                y: win.wallW
                width: sw.value
                height: Math.max(0, sh.value)
                clip: true
                // on the box, not a child: hover-enabled controls inside (sliders,
                // buttons) would otherwise steal it and the island would close
                HoverHandler { id: boxHover }

                Item {
                    id: hit
                    anchors.fill: parent
                    WheelHandler {
                        enabled: !win.open
                        onWheel: e => {
                            if (!win.showsActivity || root.activity === "workspace") root.flash("volume", "");
                            root.nudge(e.angleDelta.y > 0 ? 1 : -1);
                        }
                    }
                }

                // ── rest ──
                Row {
                    id: restRow
                    anchors.centerIn: parent
                    spacing: 10
                    opacity: win.state === "rest" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    // live: Discord call (click mutes, right-click deafens); who's talking
                    Row {
                        visible: Discord.inCall
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: Discord.deaf ? "headset_off" : Discord.mute ? "mic_off" : "headset_mic"
                            size: 17
                            fill: 1
                            color: Discord.mute || Discord.deaf ? Theme.tone("error") : Theme.tone("action")
                        }
                        Row { // the speakers' faces, else how many are in the call
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: -6
                            visible: Discord.speaking.length > 0
                            Repeater {
                                model: Discord.speaking.slice(0, 3)
                                Item {
                                    id: face
                                    required property var modelData
                                    width: 20; height: 20
                                    Rectangle { anchors.fill: parent; radius: 10; color: Theme.tone("success") }
                                    Image {
                                        id: faceImg
                                        anchors.fill: parent
                                        anchors.margins: 1.5
                                        source: face.modelData.avatar
                                        sourceSize: Qt.size(40, 40)
                                        visible: false
                                    }
                                    Rectangle { id: faceMask; anchors.fill: faceImg; radius: width / 2; visible: false; layer.enabled: true }
                                    MultiEffect { anchors.fill: faceImg; source: faceImg; maskEnabled: true; maskSource: faceMask }
                                }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: Discord.speaking.length === 0
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: Theme.text
                            text: Discord.members.length
                        }
                        TapHandler { acceptedButtons: Qt.LeftButton; onTapped: Discord.toggleMute() }
                        TapHandler { acceptedButtons: Qt.RightButton; onTapped: Discord.toggleDeaf() }
                    }
                    // live: screen recording (click stops it)
                    Row {
                        visible: Recorder.recording
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 10; height: 10; radius: 5
                            color: Theme.tone("error")
                            SequentialAnimation on opacity {
                                running: Recorder.recording && win.state === "rest"
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: Theme.tone("error")
                            text: Recorder.label
                        }
                        TapHandler { onTapped: Recorder.stop() }
                    }
                    // live: timer / stopwatch (click pauses, right-click stops)
                    Row {
                        id: timerChip
                        visible: Countdown.mode !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        opacity: Countdown.running ? 1 : 0.55
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        Item {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18
                            Shape {
                                anchors.fill: parent
                                visible: Countdown.mode === "timer"
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    strokeColor: Qt.alpha(Theme.tone("action"), 0.25)
                                    strokeWidth: 3
                                    fillColor: "transparent"
                                    PathAngleArc { centerX: 9; centerY: 9; radiusX: 7; radiusY: 7; startAngle: 0; sweepAngle: 360 }
                                }
                                ShapePath {
                                    strokeColor: Theme.tone("action")
                                    strokeWidth: 3
                                    fillColor: "transparent"
                                    capStyle: ShapePath.RoundCap
                                    PathAngleArc { centerX: 9; centerY: 9; radiusX: 7; radiusY: 7; startAngle: -90; sweepAngle: 360 * (1 - Countdown.progress) }
                                }
                            }
                            Icon { anchors.centerIn: parent; visible: Countdown.mode === "stopwatch"; name: "timer"; size: 17; fill: 1; color: Theme.tone("action") }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: Theme.text
                            text: Countdown.label
                        }
                        TapHandler { acceptedButtons: Qt.LeftButton; onTapped: Countdown.toggle() }
                        TapHandler { acceptedButtons: Qt.RightButton; onTapped: Countdown.stop() }
                    }
                    Rectangle { // between live chips and the rest
                        visible: Recorder.recording || Countdown.mode !== "" || Discord.inCall
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1; height: 14
                        color: Qt.alpha(Theme.text, 0.15)
                    }

                    // playing: art, title, a little equaliser
                    Art {
                        visible: win.showMedia
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; radius: 7
                        source: root.player?.trackArtUrl ?? ""
                    }
                    Text {
                        visible: win.showMedia
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 190)
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: Theme.text
                        text: root.player?.trackTitle ?? ""
                    }
                    Row {
                        visible: root.playing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        height: 14
                        Repeater {
                            model: 4
                            Rectangle {
                                id: eqBar
                                required property int index
                                property real level: 0.4
                                anchors.bottom: parent.bottom
                                width: 3
                                radius: 1.5
                                height: 3 + 11 * level
                                color: Theme.tone("action")
                                Behavior on height { SpringAnimation { spring: 5; damping: 0.35 } }
                                Timer {
                                    interval: 170 + eqBar.index * 23
                                    repeat: true
                                    running: root.playing && win.state === "rest"
                                    onTriggered: eqBar.level = Math.random()
                                }
                            }
                        }
                    }

                    // idle: time and weather
                    Text {
                        visible: !win.showMedia
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.font
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        color: Theme.text
                        text: Qt.formatTime(clock.date, "hh:mm")
                    }
                    Row {
                        visible: !win.showMedia && Weather.ready
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: Weather.icon(Weather.code, Weather.isDay); size: 16; fill: 1; color: Theme.subtext }
                        Label { anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 12; text: Math.round(Weather.temp) + "°" }
                    }
                }

                // ── activity: workspaces ──
                Row {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: 6
                    opacity: win.state === "activity" && root.activity === "workspace" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 200 } }

                    // special workspace: its name
                    Row {
                        visible: root.special
                        spacing: 8
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: "layers"; size: 18; fill: 1; color: Theme.tone("action") }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: Theme.text
                            text: (root.workspace?.name ?? "").replace(/^special:/, "") || "special"
                        }
                    }
                    Repeater {
                        model: root.special ? [] : root.workspaceIds
                        Rectangle {
                            id: dot
                            required property int modelData
                            readonly property bool current: modelData === root.workspace?.id
                            anchors.verticalCenter: parent.verticalCenter
                            width: current ? 34 : 10
                            height: current ? 20 : 10
                            radius: height / 2
                            color: current ? Theme.tone("action") : Qt.alpha(Theme.text, 0.3)
                            Behavior on width { SpringAnimation { spring: 4.5; damping: 0.3; epsilon: 0.2 } }
                            Behavior on height { SpringAnimation { spring: 4.5; damping: 0.3; epsilon: 0.2 } }
                            Behavior on color { ColorAnimation { duration: 200 } }
                            Text {
                                anchors.centerIn: parent
                                visible: dot.current
                                font.family: Theme.font
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: Theme.frame
                                text: dot.modelData
                            }
                        }
                    }
                }

                // ── activity: levels ──
                Row {
                    anchors.centerIn: parent
                    spacing: 12
                    opacity: win.state === "activity" && ["volume", "mic", "brightness"].includes(root.activity) ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    readonly property color tone: root.activityDim ? Theme.neutral : Theme.tone("action")

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: root.activityIcon
                        size: 20
                        fill: 1
                        color: parent.tone
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -6
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.activity === "volume") Audio.toggleMute()
                        }
                    }
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 190
                        height: 20
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 6
                            radius: 3
                            color: Qt.alpha(parent.parent.tone, 0.18)
                            Rectangle {
                                height: parent.height
                                radius: 3
                                width: Math.max(height, parent.width * Math.max(0, Math.min(1, root.activityLevel)))
                                color: parent.parent.parent.tone
                                Behavior on width { SpringAnimation { spring: drag.pressed ? 9 : 4.5; damping: drag.pressed ? 0.45 : 0.26; epsilon: 0.2 } }
                            }
                        }
                        MouseArea {
                            id: drag
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            enabled: root.activity !== "mic"
                            function set(x: real): void {
                                const v = Math.max(0, Math.min(1, x / width));
                                if (root.activity === "brightness") Brightness.set(root.activityScreen, v);
                                else Audio.setVolume(v);
                            }
                            onPressed: e => set(e.x)
                            onPositionChanged: e => { if (pressed) set(e.x); }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32
                        horizontalAlignment: Text.AlignRight
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        color: parent.tone
                        text: root.levelKind === "mic" ? (Audio.micMuted ? "off" : "on")
                            : root.activityDim ? "off" : Math.round(root.activityLevel * 100)
                    }
                }

                // ── activity: a new notification ──
                Item {
                    anchors.fill: parent
                    opacity: win.state === "activity" && root.activity === "notif" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    readonly property var e: root.peekEntry
                    Row {
                        x: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34; height: 34; radius: 17
                            color: Qt.alpha(Theme.tone("action"), 0.15)
                            readonly property url src: parent.parent.e?.image ? parent.parent.e.image
                                : parent.parent.e?.appIcon ? Quickshell.iconPath(parent.parent.e.appIcon, true) : ""
                            Image {
                                id: nimg
                                anchors.centerIn: parent
                                width: 22; height: 22
                                sourceSize: Qt.size(48, 48)
                                source: parent.src
                                fillMode: Image.PreserveAspectFit
                                visible: status === Image.Ready
                            }
                            Icon { anchors.centerIn: parent; visible: nimg.status !== Image.Ready; name: "notifications"; size: 18; fill: 1; color: Theme.tone("action") }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 300
                            Label {
                                width: parent.width
                                elide: Text.ElideRight
                                font.pixelSize: 11
                                text: parent.parent.parent.e?.appName ?? ""
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                color: Theme.text
                                text: parent.parent.parent.e?.summary ?? ""
                            }
                        }
                    }
                    TapHandler {
                        onTapped: {
                            const e = root.peekEntry;
                            if (e && Notifs.invoke(e.key, "default")) Notifs.remove(e.key);
                            root.activity = "";
                        }
                    }
                }

                // ── activity: timer done / recording started ──
                Row {
                    id: eventRow
                    anchors.centerIn: parent
                    spacing: 10
                    opacity: win.state === "activity" && ["timerdone", "recstart", "toast"].includes(root.activity) ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    // the kind being shown, kept while the row fades out (activity is "" by then)
                    property string kind: ""
                    readonly property bool done: kind === "timerdone"
                    readonly property bool isToast: kind === "toast"
                    Connections {
                        target: root
                        function onActivityChanged() {
                            if (["timerdone", "recstart", "toast"].includes(root.activity)) eventRow.kind = root.activity;
                        }
                    }
                    Icon {
                        id: eventIcon
                        anchors.verticalCenter: parent.verticalCenter
                        name: eventRow.isToast ? root.toastIcon : eventRow.done ? "alarm" : "radio_button_checked"
                        size: 20
                        fill: 1
                        color: eventRow.isToast ? Theme.tone(root.toastTone) : eventRow.done ? Theme.tone("action") : Theme.tone("error")
                        SequentialAnimation on scale {
                            running: eventRow.visible && eventRow.done
                            loops: Animation.Infinite
                            NumberAnimation { to: 1.25; duration: 260; easing.type: Easing.OutBack }
                            NumberAnimation { to: 1; duration: 340; easing.type: Easing.InOutSine }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Theme.text
                        text: eventRow.isToast ? root.toastText : eventRow.done ? "Timer done · " + Countdown.fmtTotal(root.doneTotal) : "Recording"
                    }
                }

                // ── launcher ──
                LauncherView {
                    id: launcherView
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: wantW
                    height: wantH
                    opacity: win.state === "launcher" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: win.state === "launcher" ? 240 : 110 } }
                    onClose: root.launcherOpen = false
                }

                // ── passkey ──
                PasskeyView {
                    id: passkeyView
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: wantW
                    height: wantH
                    opacity: win.state === "passkey" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: win.state === "passkey" ? 260 : 120 } }
                }

                // ── open: the dashboard ──
                DashboardContent {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: win.openW
                    height: win.openH
                    opacity: win.state === "open" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: win.state === "open" ? 320 : 140 } }
                    clock: clock
                    player: root.player
                    screen: win.screen
                    tab: root.tab
                    onSelect: t => root.tab = t
                    onPick: p => root.picked = p
                }
            }
        }
    }
}
