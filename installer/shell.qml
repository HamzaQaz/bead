//@ pragma UseQApplication
// bead's graphical installer: a window that walks through installing bead,
// driving strand (strand/gui.go) underneath. install.sh opens it once
// Quickshell is there:   qs -p installer   (with $STRAND and $BEAD_REPO set)
//
// Nothing of bead's own is installed yet, so this stands alone: its own
// colours, no icon font, the system's fonts.
//
// BEAD_INSTALLER_PREVIEW=1 adds `qs -p installer ipc call installer preview`:
// a pretend install (no strand, nothing changes), to see it move.
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    // ── colours: bead's dark look ──
    readonly property color bg: "#0f0f14"
    readonly property color card: "#18181f"
    readonly property color line: "#26262f"
    readonly property color text: "#ececf1"
    readonly property color sub: "#9a9bb0"
    readonly property color accent: "#b3baeb"
    readonly property color pink: "#f0a6d8"
    readonly property color good: "#86d6a0"
    readonly property color bad: "#f2949a"
    readonly property string font: "Noto Sans"

    readonly property string strand: Quickshell.env("STRAND") || "strand"
    readonly property string repo: Quickshell.env("BEAD_REPO") || ""
    readonly property bool previewing: Quickshell.env("BEAD_INSTALLER_PREVIEW") === "1"

    // ── state ──
    property int screen: 0          // 0 welcome · 1 parts · 2 review · 3 installing · 4 done
    property int was: 0
    property int dir: 1             // which way the screens slide
    onScreenChanged: { dir = screen >= was ? 1 : -1; was = screen; }
    property var sys: null           // strand --gui describe
    property var chosen: ({})        // part id → on
    property string pearl: "claude"
    property var planned: null       // strand --gui plan
    property var log: []
    property string failure: ""
    property bool badPass: false
    readonly property var screens: ["Welcome", "Choose", "Review", "Install", "Done"]
    ListModel { id: steps }          // { title, detail, st: waiting | running | done | failed, pct }
    property int doneCount: 0

    function partIds(): string { return Object.keys(chosen).filter(k => chosen[k]).join(","); }
    function canPick(p: var): bool { return !p.core && !p.disable && (!p.needs || chosen[p.needs]); }
    function toggle(p: var): void {
        if (!canPick(p)) return;
        const c = Object.assign({}, chosen);
        c[p.id] = !c[p.id];
        // a part that needs this one goes with it
        if (!c[p.id]) sys.parts.filter(q => q.needs === p.id).forEach(q => c[q.id] = false);
        chosen = c;
    }
    // things on a screen come in one after another: the i-th, as its screen's entrance (0..1) goes
    function stagger(e: real, i: int): real { return Math.max(0, Math.min(1, e * 3.2 - i * 0.22)); }

    Process {
        id: describe
        running: true
        command: [root.strand, "--repo", root.repo, "--gui", "describe"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text);
                    const c = {};
                    s.parts.forEach(p => c[p.id] = p.on && !p.disable);
                    root.chosen = c;
                    root.sys = s;
                } catch (e) { root.failure = "strand didn't answer: " + text; root.screen = 4; }
            }
        }
    }
    Process {
        id: planner
        command: [root.strand, "--repo", root.repo, "--gui", "plan", "--parts", root.partIds(), "--pearl", root.pearl]
        stdout: StdioCollector { onStreamFinished: { try { root.planned = JSON.parse(text); } catch (e) { root.planned = { steps: [], repo: [], aur: [] }; } } }
    }
    function review(): void { planned = null; screen = 2; planner.running = true; }
    // looking at the screens without clicking (tools, screenshots): never past Review,
    // except the pretend install, and only with BEAD_INSTALLER_PREVIEW=1
    IpcHandler {
        target: "installer"
        function go(n: int): void { if (n === 2) root.review(); else root.screen = Math.max(0, Math.min(1, n)); }
        function preview(): void { if (root.previewing) root.pretend(); }
        function fail(): void { if (root.previewing) { root.failure = "AUR packages failed: exit status 1"; root.log = ["error: failed to build 'quickshell'", "==> ERROR: A failure occurred in build()."]; root.screen = 4; } }
    }

    Process {
        id: runner
        property string secrets: ""
        command: [root.strand, "--repo", root.repo, "--gui", "run", "--parts", root.partIds(), "--pearl", root.pearl]
        stdinEnabled: true
        onStarted: { write(secrets + "\n"); secrets = ""; }
        stdout: SplitParser { onRead: data => root.event(data) }
        onExited: code => {
            if (root.screen !== 3) return;
            if (code === 3) { root.badPass = true; root.screen = 2; }
            else if (code !== 0 && !root.failure) root.failure = "The installer stopped (exit " + code + ")";
            if (code !== 3) root.screen = 4;
        }
    }
    function setSteps(list: var): void {
        steps.clear();
        list.forEach(s => steps.append({ title: s.title, detail: s.detail, st: "waiting", pct: -1 }));
        doneCount = 0;
    }
    function install(password: string, key: string): void {
        badPass = false;
        failure = "";
        log = [];
        setSteps(planned?.steps ?? []);
        runner.secrets = JSON.stringify({ password: password, apiKey: key });
        screen = 3;
        runner.running = true;
    }
    function event(raw: string): void {
        let e;
        try { e = JSON.parse(raw); } catch (err) { return; }
        if (e.ev === "plan") setSteps(e.steps);
        else if (e.ev === "step" && e.i < steps.count) { steps.setProperty(e.i, "st", e.state); if (e.state === "done") doneCount++; }
        else if (e.ev === "progress" && e.i < steps.count) steps.setProperty(e.i, "pct", e.pct);
        else if (e.ev === "log") log = [...log.slice(-200), e.line];
        else if (e.ev === "failed") failure = e.error;
        else if (e.ev === "badpass") badPass = true;
    }

    // the pretend install (preview only): steps tick through, one downloads
    function pretend(): void {
        failure = "";
        log = [];
        setSteps([
            { title: "Packages", detail: "quickshell hyprpolkitagent ttf-material-symbols-variable" },
            { title: "Build and install bead", detail: "shaders, then ~/.local/share/bead and ~/.local/bin" },
            { title: "Glint", detail: "build the glint command" },
            { title: "Download whisper base.en", detail: "148 MB from huggingface.co" },
            { title: "Tint", detail: "colours from your first wallpaper" },
            { title: "Hyprland keybinds", detail: "~/.config/hypr/bead.lua, and a line in hyprland.lua" }
        ]);
        screen = 3;
        fake.at = 0;
        fake.tick = 0;
        fake.start();
    }
    Timer {
        id: fake
        property int at: 0
        property int tick: 0
        interval: 120
        repeat: true
        onTriggered: {
            if (at >= steps.count) { stop(); root.screen = 4; return; }
            if (tick === 0) steps.setProperty(at, "st", "running");
            tick++;
            if (at === 3) steps.setProperty(at, "pct", Math.min(100, tick * 4));
            if (tick % 3 === 0) root.log = [...root.log, "(" + steps.get(at).title.toLowerCase() + ") working… " + tick];
            if (tick >= (at === 3 ? 26 : 9)) { steps.setProperty(at, "st", "done"); root.doneCount++; at++; tick = 0; }
        }
    }

    // ── pieces ──
    component T: Text { font.family: root.font; color: root.text; font.pixelSize: 13 }
    component Sub: Text { font.family: root.font; color: root.sub; font.pixelSize: 12; wrapMode: Text.WordWrap }
    component Button: Rectangle {
        id: btn
        property string label: ""
        property bool primary: false
        signal hit()
        width: bl.implicitWidth + 36
        height: 40
        radius: 20
        opacity: enabled ? 1 : 0.4
        scale: bma.pressed ? 0.95 : bma.containsMouse ? 1.03 : 1
        Behavior on scale { SpringAnimation { spring: 5; damping: 0.35; epsilon: 0.002 } }
        Behavior on opacity { NumberAnimation { duration: 200 } }
        color: primary ? (bma.pressed ? Qt.darker(root.accent, 1.15) : root.accent) : Qt.rgba(1, 1, 1, bma.containsMouse ? 0.1 : 0.06)
        Behavior on color { ColorAnimation { duration: 120 } }
        T {
            id: bl
            anchors.centerIn: parent
            text: btn.label
            font.weight: Font.DemiBold
            color: btn.primary ? root.bg : root.text
            // a new label slides in
            onTextChanged: swap.restart()
            NumberAnimation { id: swap; target: bl; property: "anchors.verticalCenterOffset"; from: 8; to: 0; duration: 260; easing.type: Easing.OutBack }
        }
        MouseArea { id: bma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.hit() }
    }
    component Switch: Rectangle {
        id: sw
        property bool on: false
        width: 44; height: 26; radius: 13
        color: on ? root.accent : Qt.rgba(1, 1, 1, 0.12)
        Behavior on color { ColorAnimation { duration: 160 } }
        Rectangle {
            id: knob
            height: 20; radius: 10
            y: 3
            // stretches as it travels
            width: 20 + (moving.running ? 6 : 0)
            x: sw.on ? sw.width - width - 3 : 3
            color: sw.on ? root.bg : root.text
            Behavior on x { NumberAnimation { id: moving; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
            Behavior on width { NumberAnimation { duration: 120 } }
        }
    }
    // a screen: slides and fades in from the way you're going; `e` runs 0 → 1
    // as it arrives, for what's on it to come in one after another
    component Screen: Item {
        id: scr
        property int idx: 0
        readonly property bool now: root.screen === idx
        property real t: now ? 1 : 0
        Behavior on t { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        property real e: 0
        onNowChanged: if (now) { e = 0; enter.restart(); }
        Component.onCompleted: if (now) enter.restart()
        NumberAnimation { id: enter; target: scr; property: "e"; from: 0; to: 1; duration: 1100; easing.type: Easing.OutCubic }
        default property alias content: holder.data
        width: parent?.width ?? 0
        height: parent?.height ?? 0
        opacity: t
        visible: t > 0.001
        transform: Translate { x: (1 - scr.t) * 48 * (scr.now ? root.dir : -root.dir) }
        Item { id: holder; anchors.fill: parent }
    }

    FloatingWindow {
        id: win
        title: "Install bead"
        implicitWidth: 940
        implicitHeight: 640
        color: root.bg
        visible: true
        onVisibleChanged: if (!visible && root.screen !== 3) Qt.quit()

        // a slow glow of colour behind everything, drifting
        Rectangle {
            id: glow
            width: 620; height: 620; radius: 310
            x: parent.width - 380 + 40 * Math.sin(drift.t)
            y: -260 + 30 * Math.cos(drift.t * 0.7)
            opacity: root.screen === 4 && !root.failure ? 0.16 : 0.08
            Behavior on opacity { NumberAnimation { duration: 900 } }
            gradient: Gradient {
                GradientStop { position: 0; color: root.accent }
                GradientStop { position: 1; color: root.pink }
            }
            rotation: drift.t * 12
            layer.enabled: true
        }
        FrameAnimation { id: drift; property real t: 0; running: win.visible; onTriggered: t += frameTime * 0.25 }

        // ── the steps, down the left ──
        Rectangle {
            id: rail
            width: 230
            height: parent.height
            color: Qt.rgba(1, 1, 1, 0.025)
            Row {
                x: 28; y: 30
                spacing: 10
                // bead's dot: breathes; quicker while it installs
                Item {
                    width: 22; height: 22
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle { // a ring that goes out from it while installing
                        anchors.centerIn: parent
                        width: 22 * ring.s; height: width; radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: root.accent
                        opacity: root.screen === 3 ? (1 - (ring.s - 1) / 1.2) * 0.7 : 0
                        QtObject { id: ring; property real s: 1 }
                        NumberAnimation { target: ring; property: "s"; from: 1; to: 2.2; duration: 1100; loops: Animation.Infinite; running: root.screen === 3; easing.type: Easing.OutCubic }
                    }
                    Rectangle {
                        id: dot
                        anchors.centerIn: parent
                        width: 22; height: 22; radius: 11
                        color: root.accent
                        SequentialAnimation on scale {
                            loops: Animation.Infinite
                            NumberAnimation { to: 1.14; duration: root.screen === 3 ? 450 : 1600; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1; duration: root.screen === 3 ? 450 : 1600; easing.type: Easing.InOutSine }
                        }
                    }
                }
                T { text: "bead"; font.pixelSize: 26; font.weight: Font.Bold }
            }

            // the line through the steps, filled as far as you've got
            Rectangle {
                x: 28 + 11; y: 104 + 17
                width: 2; height: 4 * 40
                color: Qt.rgba(1, 1, 1, 0.08)
                Rectangle {
                    width: parent.width
                    height: parent.height * root.screen / 4
                    color: root.accent
                    Behavior on height { NumberAnimation { duration: 520; easing.type: Easing.InOutCubic } }
                }
            }
            // the highlight, sliding to the step you're on
            Rectangle {
                x: 16; y: 104 + root.screen * 40
                width: rail.width - 32; height: 34; radius: 17
                color: Qt.alpha(root.accent, 0.1)
                Behavior on y { SpringAnimation { spring: 4; damping: 0.32; epsilon: 0.2 } }
            }
            Column {
                x: 28; y: 104
                spacing: 6
                Repeater {
                    model: root.screens
                    Row {
                        id: rs
                        required property string modelData
                        required property int index
                        readonly property bool now: root.screen === index
                        readonly property bool past: root.screen > index
                        spacing: 12
                        height: 34
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24; height: 24; radius: 12
                            color: rs.now ? root.accent : rs.past ? Qt.rgba(0.2, 0.2, 0.26, 1) : root.bg
                            Behavior on color { ColorAnimation { duration: 260 } }
                            border.width: rs.now || rs.past ? 0 : 1.5
                            border.color: Qt.rgba(1, 1, 1, 0.2)
                            scale: rs.now ? 1.15 : 1
                            Behavior on scale { SpringAnimation { spring: 5; damping: 0.28; epsilon: 0.002 } }
                            // the install step, when it failed: a red mark, not a tick
                            readonly property bool broke: rs.past && rs.index === 3 && !!root.failure
                            T { anchors.centerIn: parent; font.pixelSize: 11; font.weight: Font.Bold; color: rs.now ? root.bg : parent.broke ? root.bad : rs.past ? root.accent : root.sub; text: parent.broke ? "!" : rs.past ? "✓" : rs.index + 1 }
                        }
                        T {
                            anchors.verticalCenter: parent.verticalCenter
                            text: rs.modelData
                            color: rs.now ? root.text : root.sub
                            Behavior on color { ColorAnimation { duration: 260 } }
                            font.weight: rs.now ? Font.DemiBold : Font.Normal
                            x: rs.now ? 3 : 0
                        }
                    }
                }
            }
            Sub { x: 28; anchors.bottom: parent.bottom; anchors.bottomMargin: 24; width: parent.width - 56; text: root.repo ? "From " + root.repo.replace(Quickshell.env("HOME"), "~") : "" }
        }

        // ── the screens ──
        Item {
            id: pane
            x: rail.width + 44
            y: 40
            width: parent.width - x - 44
            height: parent.height - y - 32

            // 0 · welcome
            Screen {
                id: s0
                idx: 0
                Column {
                    width: parent.width
                    spacing: 18
                    // the title rises in, letter by letter
                    Row {
                        Repeater {
                            model: (root.sys?.installed ? "Update bead" : "Welcome to bead").split("")
                            T {
                                id: ch
                                required property string modelData
                                required property int index
                                readonly property real p: Math.max(0, Math.min(1, s0.e * 4 - index * 0.06))
                                text: modelData
                                font.pixelSize: 30; font.weight: Font.Bold
                                opacity: p
                                transform: Translate { y: 14 * (1 - ch.p) * (1 - ch.p) }
                            }
                        }
                    }
                    Sub {
                        width: parent.width
                        font.pixelSize: 14
                        opacity: root.stagger(s0.e, 1)
                        text: "An opinionated desktop shell for Hyprland: a bar, an island that's a launcher and much more, a dashboard, notifications and a lock screen, coloured from your wallpaper."
                    }
                    Rectangle {
                        width: parent.width
                        height: facts.height + 32
                        radius: 16
                        color: root.card
                        opacity: root.stagger(s0.e, 2)
                        Column {
                            id: facts
                            x: 20; y: 16
                            width: parent.width - 40
                            spacing: 10
                            Repeater {
                                model: root.sys ? [
                                    { ok: root.sys.arch, t: root.sys.arch ? "An Arch-based system" : "Not Arch-based: bead's installer needs pacman" },
                                    { ok: root.sys.helper !== "", t: root.sys.helper ? "AUR packages through " + root.sys.helper : "No AUR helper (paru or yay): some parts may not install" },
                                    { ok: true, t: root.sys.hyprBinds ? "Your Hyprland config already has bead's keys" : "bead's keys go into " + (root.sys.hyprLua ? "hyprland.lua" : "hyprland.conf") + ", backed up first" },
                                    { ok: true, t: root.sys.installed ? "bead is installed: this brings it up to date" : "Nothing of bead's yet" }
                                ] : []
                                Row {
                                    id: fact
                                    required property var modelData
                                    required property int index
                                    readonly property real p: root.stagger(s0.e, 3 + index)
                                    spacing: 10
                                    opacity: p
                                    transform: Translate { x: -16 * (1 - fact.p) }
                                    T { text: fact.modelData.ok ? "✓" : "!"; color: fact.modelData.ok ? root.good : root.bad; font.weight: Font.Bold; width: 14; scale: 0.4 + 0.6 * fact.p }
                                    T { text: fact.modelData.t }
                                }
                            }
                            Sub { visible: !root.sys; text: "Looking around…" }
                        }
                    }
                    Sub { width: parent.width; opacity: root.stagger(s0.e, 7); text: "Nothing changes until you press Install. Packages come from pacman (and the AUR); your configs are backed up before bead touches them." }
                }
            }

            // 1 · parts
            Screen {
                id: s1
                idx: 1
                Flickable {
                    width: parent.width
                    height: parent.height - 64
                    contentHeight: partsCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: partsCol
                        width: parent.width
                        spacing: 10
                        T { text: "Choose what to install"; font.pixelSize: 24; font.weight: Font.Bold; bottomPadding: 6; opacity: root.stagger(s1.e, 0) }
                        Repeater {
                            model: root.sys?.parts ?? []
                            Rectangle {
                                id: pc
                                required property var modelData
                                required property int index
                                readonly property bool on: !!root.chosen[modelData.id]
                                readonly property bool can: root.canPick(modelData)
                                readonly property real p: root.stagger(s1.e, 1 + index * 0.6)
                                width: partsCol.width
                                height: Math.max(64, pcol.height + 26)
                                radius: 14
                                color: pc.on ? Qt.rgba(0.11, 0.11, 0.15, 1) : root.card
                                Behavior on color { ColorAnimation { duration: 200 } }
                                border.width: 1
                                border.color: pc.on ? Qt.alpha(root.accent, 0.45) : pma.containsMouse && pc.can ? Qt.rgba(1, 1, 1, 0.14) : root.line
                                Behavior on border.color { ColorAnimation { duration: 200 } }
                                opacity: (pc.can || pc.modelData.core ? 1 : 0.55) * pc.p
                                transform: Translate { y: 18 * (1 - pc.p) }
                                scale: pma.pressed && pc.can ? 0.985 : 1
                                Behavior on scale { NumberAnimation { duration: 120 } }
                                Column {
                                    id: pcol
                                    x: 18; anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 36 - 60
                                    spacing: 3
                                    T { text: pc.modelData.name + (pc.modelData.core ? "  ·  always" : ""); font.weight: Font.DemiBold; font.pixelSize: 14 }
                                    Sub { width: parent.width; text: pc.modelData.disable || pc.modelData.blurb }
                                }
                                Switch { anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter; on: pc.on }
                                MouseArea { id: pma; anchors.fill: parent; hoverEnabled: true; cursorShape: pc.can ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: root.toggle(pc.modelData) }
                            }
                        }
                        // Pearl: how it answers (opens out when Pearl is chosen)
                        Item {
                            width: parent.width
                            height: ways.height * wayOpen.t
                            clip: true
                            QtObject { id: wayOpen; property real t: root.chosen["pearl"] ? 1 : 0; Behavior on t { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } } }
                            opacity: wayOpen.t
                            Column {
                                id: ways
                                width: parent.width
                                spacing: 8
                                topPadding: 8
                                T { text: "Pearl answers with"; font.weight: Font.DemiBold }
                                Row {
                                    spacing: 8
                                    Repeater {
                                        model: root.sys?.pearl ?? []
                                        Rectangle {
                                            id: wy
                                            required property var modelData
                                            readonly property bool on: root.pearl === modelData.id
                                            width: (partsCol.width - 16) / 3
                                            height: wcol.height + 24
                                            radius: 14
                                            color: wy.on ? Qt.rgba(0.14, 0.14, 0.2, 1) : root.card
                                            Behavior on color { ColorAnimation { duration: 200 } }
                                            border.width: 1
                                            border.color: wy.on ? root.accent : root.line
                                            Behavior on border.color { ColorAnimation { duration: 200 } }
                                            scale: wy.on ? 1 : 0.97
                                            Behavior on scale { SpringAnimation { spring: 5; damping: 0.3; epsilon: 0.002 } }
                                            Column {
                                                id: wcol
                                                x: 14; y: 12
                                                width: parent.width - 28
                                                spacing: 3
                                                T { text: wy.modelData.name; font.weight: Font.DemiBold }
                                                Sub { width: parent.width; text: wy.modelData.blurb }
                                            }
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.pearl = wy.modelData.id }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 2 · review
            Screen {
                id: s2
                idx: 2
                Column {
                    width: parent.width
                    spacing: 14
                    T { text: "Ready to install"; font.pixelSize: 24; font.weight: Font.Bold; opacity: root.stagger(s2.e, 0) }
                    Row {
                        visible: !root.planned
                        spacing: 10
                        Repeater { // three dots, one after another
                            model: 3
                            Rectangle {
                                required property int index
                                width: 8; height: 8; radius: 4
                                color: root.accent
                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 160 }
                                    NumberAnimation { from: 0.25; to: 1; duration: 320 }
                                    NumberAnimation { from: 1; to: 0.25; duration: 320 }
                                    PauseAnimation { duration: (2 - index) * 160 }
                                }
                            }
                        }
                        Sub { text: "Working out what's needed" }
                    }
                    Rectangle {
                        visible: !!root.planned
                        width: parent.width
                        height: Math.min(250, plan.contentHeight + 28)
                        radius: 16
                        color: root.card
                        ListView {
                            id: plan
                            x: 18; y: 14
                            width: parent.width - 36
                            height: parent.height - 28
                            clip: true
                            spacing: 8
                            model: root.planned?.steps ?? []
                            delegate: Column {
                                id: pl
                                required property var modelData
                                required property int index
                                readonly property real p: root.stagger(s2.e, 1 + index * 0.5)
                                width: plan.width
                                opacity: pl.p
                                transform: Translate { x: 20 * (1 - pl.p) }
                                T { text: (pl.index + 1) + ".  " + pl.modelData.title; font.weight: Font.DemiBold }
                                Sub { width: parent.width; leftPadding: 20; text: pl.modelData.detail; elide: Text.ElideRight; maximumLineCount: 2 }
                            }
                        }
                    }
                    Sub {
                        visible: !!root.planned?.aurWithoutHelper
                        width: parent.width
                        color: root.bad
                        text: "Some packages come from the AUR and there's no AUR helper: install paru first, or that step will fail."
                    }
                    Sub {
                        visible: (root.planned?.downloadMB ?? 0) > 0
                        text: "Downloads about " + (root.planned?.downloadMB ?? 0) + " MB of voice models."
                    }
                    // the password, for pacman
                    Column {
                        visible: !!root.planned?.needsPassword
                        width: parent.width
                        spacing: 6
                        opacity: root.stagger(s2.e, 4)
                        T { text: "Your password"; font.weight: Font.DemiBold }
                        Sub { width: parent.width; text: "To install packages with pacman. It's handed to sudo and never saved." }
                        Rectangle {
                            id: pwBox
                            width: 340; height: 42; radius: 21
                            color: Qt.rgba(1, 1, 1, pw.activeFocus ? 0.08 : 0.06)
                            Behavior on color { ColorAnimation { duration: 160 } }
                            border.width: pw.activeFocus || root.badPass ? 1.5 : 0
                            border.color: root.badPass ? root.bad : root.accent
                            // a wrong password: it shakes its head
                            property real shake: 0
                            transform: Translate { x: pwBox.shake }
                            SequentialAnimation {
                                id: no
                                NumberAnimation { target: pwBox; property: "shake"; to: -10; duration: 50 }
                                NumberAnimation { target: pwBox; property: "shake"; to: 9; duration: 70 }
                                NumberAnimation { target: pwBox; property: "shake"; to: -6; duration: 70 }
                                NumberAnimation { target: pwBox; property: "shake"; to: 4; duration: 70 }
                                NumberAnimation { target: pwBox; property: "shake"; to: 0; duration: 60 }
                            }
                            Connections { target: root; function onBadPassChanged(): void { if (root.badPass) no.restart(); } }
                            TextInput {
                                id: pw
                                x: 18; width: parent.width - 36
                                anchors.verticalCenter: parent.verticalCenter
                                echoMode: TextInput.Password
                                font.family: root.font; font.pixelSize: 14
                                color: root.text
                                focus: root.screen === 2
                                onTextEdited: root.badPass = false
                                onAccepted: go.hit()
                            }
                        }
                        Sub { visible: root.badPass; color: root.bad; text: "That password didn't work. Try again." }
                    }
                    // Pearl's own key
                    Column {
                        visible: !!root.chosen["pearl"] && root.pearl === "api"
                        width: parent.width
                        spacing: 6
                        T { text: "Anthropic API key"; font.weight: Font.DemiBold }
                        Rectangle {
                            width: 340; height: 42; radius: 21
                            color: Qt.rgba(1, 1, 1, 0.06)
                            TextInput { id: key; x: 18; width: parent.width - 36; anchors.verticalCenter: parent.verticalCenter; echoMode: TextInput.Password; font.family: root.font; font.pixelSize: 14; color: root.text }
                        }
                    }
                }
            }

            // 3 · installing
            Screen {
                id: s3
                idx: 3
                Column {
                    width: parent.width
                    spacing: 14
                    Row {
                        spacing: 14
                        T { text: "Installing"; font.pixelSize: 24; font.weight: Font.Bold }
                        T { anchors.baseline: parent.children[0].baseline; color: root.sub; font.pixelSize: 14; text: root.doneCount + " of " + steps.count }
                    }
                    // the whole way, one bar
                    Rectangle {
                        width: parent.width; height: 6; radius: 3
                        color: Qt.rgba(1, 1, 1, 0.07)
                        Rectangle {
                            height: parent.height; radius: 3
                            width: parent.width * (steps.count ? root.doneCount / steps.count : 0)
                            Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: root.accent }
                                GradientStop { position: 1; color: root.pink }
                            }
                            // a shine running along it
                            Rectangle {
                                width: 60; height: parent.height; radius: 3
                                opacity: 0.5
                                x: (shine.t % 1) * (parent.width + 60) - 60
                                visible: parent.width > 20
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: "transparent" }
                                    GradientStop { position: 0.5; color: "white" }
                                    GradientStop { position: 1; color: "transparent" }
                                }
                            }
                            clip: true
                        }
                        FrameAnimation { id: shine; property real t: 0; running: s3.now; onTriggered: t += frameTime * 0.6 }
                    }
                    Rectangle {
                        width: parent.width
                        height: stepCol.height + 28
                        radius: 16
                        color: root.card
                        Column {
                            id: stepCol
                            x: 18; y: 14
                            width: parent.width - 36
                            spacing: 10
                            Repeater {
                                model: steps
                                Column {
                                    id: sr
                                    required property string title
                                    required property string detail
                                    required property string st
                                    required property real pct
                                    required property int index
                                    readonly property real p: root.stagger(s3.e, index * 0.5)
                                    width: stepCol.width
                                    spacing: 6
                                    opacity: p
                                    transform: Translate { y: 10 * (1 - sr.p) }
                                    Row {
                                        spacing: 10
                                        x: sr.st === "running" ? 4 : 0
                                        Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                                        Item {
                                            width: 18; height: 18
                                            anchors.verticalCenter: parent.verticalCenter
                                            T {
                                                id: mark
                                                anchors.centerIn: parent
                                                visible: sr.st !== "running"
                                                font.weight: Font.Bold
                                                text: sr.st === "done" ? "✓" : sr.st === "failed" ? "✕" : "•"
                                                color: sr.st === "done" ? root.good : sr.st === "failed" ? root.bad : root.sub
                                            }
                                            // a finished step: its tick pops in
                                            Connections {
                                                target: sr
                                                function onStChanged(): void { if (sr.st === "done" || sr.st === "failed") pop.restart(); }
                                            }
                                            ParallelAnimation {
                                                id: pop
                                                SequentialAnimation {
                                                    NumberAnimation { target: mark; property: "scale"; from: 0.2; to: 1.45; duration: 180; easing.type: Easing.OutCubic }
                                                    NumberAnimation { target: mark; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 }
                                                }
                                                NumberAnimation { target: ringOut; property: "s"; from: 1; to: 2.6; duration: 560; easing.type: Easing.OutCubic }
                                            }
                                            Rectangle { // and a ring goes out from it
                                                id: ringOut
                                                property real s: 2.6
                                                anchors.centerIn: parent
                                                width: 18 * s; height: width; radius: width / 2
                                                color: "transparent"; border.width: 1.5
                                                border.color: sr.st === "failed" ? root.bad : root.good
                                                opacity: (2.6 - s) / 1.6 * 0.8
                                            }
                                            Rectangle { // a spinner while it runs
                                                visible: sr.st === "running"
                                                anchors.fill: parent
                                                radius: 9
                                                color: "transparent"
                                                border.width: 2
                                                border.color: Qt.alpha(root.accent, 0.25)
                                                Rectangle { width: 6; height: 6; radius: 3; color: root.accent; x: 6; y: -2 }
                                                RotationAnimation on rotation { running: sr.st === "running"; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                                            }
                                        }
                                        T {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: sr.title
                                            font.weight: sr.st === "running" ? Font.DemiBold : Font.Normal
                                            color: sr.st === "waiting" ? root.sub : root.text
                                            Behavior on color { ColorAnimation { duration: 240 } }
                                        }
                                        Sub { anchors.verticalCenter: parent.verticalCenter; text: sr.detail; elide: Text.ElideRight; width: Math.max(0, stepCol.width - 260); wrapMode: Text.NoWrap }
                                    }
                                    Rectangle {
                                        visible: sr.st === "running" && sr.pct >= 0
                                        x: 28; width: parent.width - 28; height: 4; radius: 2
                                        color: Qt.rgba(1, 1, 1, 0.08)
                                        Rectangle {
                                            width: parent.width * Math.min(1, Math.max(0, sr.pct) / 100)
                                            Behavior on width { NumberAnimation { duration: 260 } }
                                            height: parent.height; radius: 2; color: root.accent
                                        }
                                    }
                                }
                            }
                        }
                    }
                    // what it's saying, the last few lines
                    Rectangle {
                        width: parent.width
                        height: Math.max(80, pane.height - y - 12)
                        radius: 14
                        color: "#0a0a0e"
                        border.width: 1
                        border.color: root.line
                        clip: true
                        Text {
                            x: 14; width: parent.width - 28
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 12
                            font.family: "monospace"; font.pixelSize: 11
                            color: root.sub
                            elide: Text.ElideRight
                            text: root.log.slice(-Math.max(3, Math.floor((parent.height - 24) / 15))).join("\n")
                        }
                    }
                }
            }

            // 4 · done (or not)
            Screen {
                id: s4
                idx: 4
                onNowChanged: if (now) { badgeIn.restart(); if (!root.failure) beads.go(); }
                Column {
                    width: parent.width
                    spacing: 16
                    Item {
                        width: 64; height: 64
                        // beads burst out of it
                        Item {
                            id: beads
                            anchors.centerIn: parent
                            property real t: 0
                            function go(): void { t = 0; flyOut.restart(); }
                            NumberAnimation { id: flyOut; target: beads; property: "t"; from: 0; to: 1; duration: 1300; easing.type: Easing.OutCubic }
                            Repeater {
                                model: 16
                                Rectangle {
                                    required property int index
                                    readonly property real a: index / 16 * Math.PI * 2 + 0.2
                                    readonly property real reach: 70 + (index % 3) * 26
                                    width: 6 + (index % 4) * 2; height: width; radius: width / 2
                                    color: [root.accent, root.pink, root.good][index % 3]
                                    x: Math.cos(a) * reach * beads.t - width / 2
                                    y: Math.sin(a) * reach * beads.t - width / 2 + 30 * beads.t * beads.t
                                    opacity: beads.t > 0 && beads.t < 1 ? 1 - Math.pow(beads.t, 3) : 0
                                }
                            }
                        }
                        Rectangle {
                            id: badge
                            anchors.fill: parent
                            radius: 32
                            color: root.failure ? Qt.rgba(0.27, 0.14, 0.16, 1) : Qt.rgba(0.13, 0.24, 0.17, 1)
                            scale: 0
                            T { anchors.centerIn: parent; font.pixelSize: 30; font.weight: Font.Bold; color: root.failure ? root.bad : root.good; text: root.failure ? "!" : "✓" }
                            SequentialAnimation {
                                id: badgeIn
                                PauseAnimation { duration: 120 }
                                NumberAnimation { target: badge; property: "scale"; from: 0; to: 1; duration: 620; easing.type: Easing.OutBack; easing.overshoot: 2.4 }
                            }
                        }
                    }
                    T { text: root.failure ? "That didn't finish" : "bead is ready"; font.pixelSize: 28; font.weight: Font.Bold; opacity: root.stagger(s4.e, 1); transform: Translate { y: 12 * (1 - root.stagger(s4.e, 1)) } }
                    Sub {
                        width: parent.width
                        font.pixelSize: 14
                        opacity: root.stagger(s4.e, 2)
                        text: root.failure ? root.failure + "\n\nNothing after that step ran. Fix what it says, then try again: steps already done are quick the second time."
                            : "Start it now. Its welcome shows you around, and Settings (in the launcher) has everything else. From now on bead starts with Hyprland."
                    }
                    Rectangle {
                        visible: !!root.failure && root.log.length > 0
                        width: parent.width
                        height: 150
                        radius: 14
                        color: "#0a0a0e"
                        clip: true
                        opacity: root.stagger(s4.e, 3)
                        Text { x: 14; width: parent.width - 28; anchors.bottom: parent.bottom; anchors.bottomMargin: 12; font.family: "monospace"; font.pixelSize: 11; color: root.sub; elide: Text.ElideRight; text: root.log.slice(-8).join("\n") }
                    }
                }
            }

            // ── back / next ──
            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: 10
                opacity: root.screen === 3 ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 240 } }
                Button { visible: root.screen === 1 || root.screen === 2 || (root.screen === 4 && !!root.failure); label: "Back"; onHit: root.screen = root.screen === 4 ? 2 : root.screen - 1 }
                Button { visible: root.screen === 4; label: "Close"; onHit: Qt.quit() }
                Button {
                    id: go
                    primary: true
                    enabled: root.screen === 0 ? !!root.sys?.arch
                        : root.screen === 2 ? !!root.planned && (!root.planned.needsPassword || pw.text.length > 0) && !(root.chosen["pearl"] && root.pearl === "api" && !key.text)
                        : true
                    label: root.screen === 0 ? "Get started" : root.screen === 1 ? "Review" : root.screen === 2 ? "Install" : root.failure ? "Try again" : "Start bead"
                    onHit: {
                        if (!enabled) return;
                        if (root.screen === 0) root.screen = 1;
                        else if (root.screen === 1) root.review();
                        else if (root.screen === 2) { root.install(pw.text, key.text); pw.text = ""; key.text = ""; }
                        else if (root.failure) { root.failure = ""; root.review(); }
                        else if (root.previewing) root.screen = 0;
                        else {
                            Quickshell.execDetached(["sh", "-c", 'exec "$HOME/.local/bin/bead" start 2>/dev/null || exec bead start']);
                            Qt.quit();
                        }
                    }
                }
            }
        }
    }
}
