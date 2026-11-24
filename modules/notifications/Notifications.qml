pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import "../../services/snooze.js" as Snooze
import qs.components
import qs.config
import qs.services

// Also shows `toast` CLI toasts (IPC target "toast"), e.g. Claude Code prompts:
// they join the same stack, and questions stay pinned open at the top.
//
// The desktop notification server (org.freedesktop.Notifications), shown as a
// stack of sileo pills that grow out of the right edge of Caelestia's screen
// frame, top-right of the primary monitor (the island's, Settings.home).
//
// Only one server can own the name. If another (Caelestia) holds it, Quickshell
// waits and takes over as soon as it is released, and the other does the same
// for us, so whichever started first wins and the other is the fallback.
Scope {
    id: root

    // Popups on screen, newest first. Each entry is a plain snapshot, so a pill
    // can finish animating after its notification object is gone.
    property list<var> popups: []
    property int serial: 0

    // ── fullscreen (a game, a video): no pop-ups, just a dot each, top right,
    // in front of it and never in the way. Critical ones still pop up. Back
    // out of fullscreen: the dots go, and the island says what came in.
    readonly property bool quiet: Hyprland.focusedWorkspace?.hasFullscreen ?? false
    property list<var> dots: []   // newest first: { key, critical, entry }
    function dot(entry: var, critical: bool): void {
        root.dots = [{ key: ++root.serial, critical: critical, entry: entry }, ...root.dots].slice(0, 30);
    }
    onQuietChanged: {
        if (quiet || !dots.length) return;
        const list = dots.map(d => d.entry).filter(e => e && e.time);
        dots = [];
        if (!list.length) return;
        Notifs.awayFrom = Math.min(...list.map(e => e.time));
        Notifs.awayTo = Date.now();
        Notifs.missed(list);
    }

    // a popup for a recorded history entry (same key)
    function popupFor(n: Notification, e: var): var {
        return Object.assign({}, e, {
            notif: n,
            sticky: n.urgency === NotificationUrgency.Critical,
            timeout: n.expireTimeout
        });
    }

    // at most `maxShown` on screen: the oldest ones expire
    readonly property int maxShown: 4
    function trim(): void {
        for (const c of stack.children)
            if (c.pillRect !== undefined && c.index >= maxShown && !c.sticky) c.dismiss("timeout");
    }

    // Newest first, but interactive ones (questions, prompts) stay above the rest.
    function add(entry: var): void {
        if (popups.length === 0) win.held = win.focused; // stay put while shown
        const pinned = popups.filter(p => p.sticky);
        const rest = popups.filter(p => !p.sticky);
        popups = entry.sticky ? [entry, ...pinned, ...rest] : [...pinned, entry, ...rest];
        Qt.callLater(trim);
    }

    // ── toasts from the `toast` CLI ──
    // push(spec JSON) puts one in the stack; the outcome (button id, "dismissed",
    // "timeout") is written to $XDG_RUNTIME_DIR/bead/toast/<id>.result.
    readonly property string toastDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/bead/toast"
    property var reported: ({})
    function esc(t: string): string { return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
    function report(id: string, name: string, text: string): void {
        if (name === "result") {
            if (reported[id]) return;
            reported[id] = true;
        }
        writer.createObject(root, { path: toastDir + "/" + id + "." + name, text: text });
    }
    Component {
        id: writer
        Process {
            property string path
            property string text
            command: ["sh", "-c", 'mkdir -p "${1%/*}" && printf %s "$2" > "$1.tmp" && mv "$1.tmp" "$1"', "sh", path, text]
            running: true
            onExited: destroy()
        }
    }
    IpcHandler {
        target: "toast"
        function push(spec: string): string {
            let s;
            try { s = JSON.parse(spec); } catch (e) { return "error: bad json"; }
            s.id = String(s.id || Date.now());
            const interactive = s.type === "confirm" || s.type === "choose" || s.type === "loading" || s.type === "ask";
            if (root.quiet) {
                // not shown: anything waiting on it hears so at once (a question
                // is then asked where it came from, the terminal)
                root.report(s.id, "result", "dismissed");
                root.dot(null, false);
                return s.id;
            }
            root.add({ key: ++root.serial, spec: s, sticky: interactive || s.duration === 0 });
            return s.id;
        }
        function ping(): string { return "pong"; }
        // withdraw `toast` CLI toasts whose id starts with PREFIX (a toast's id is
        // "<pid of the toast process>-<time>"), e.g. a question answered elsewhere
        function close(prefix: string): void { if (prefix) root.withdraw(prefix); }
    }
    signal withdraw(string prefix)
    property Item replyPill: null // the pop-up whose reply field is open

    function remove(key: real): void { // real: keys (ms × 1000) overflow a 32-bit int
        popups = popups.filter(p => p.key !== key);
    }

    // a snoozed one's time has come: it pops up again, by the same rules as a new one
    Connections {
        target: Notifs
        function onReturned(e) {
            if (Notifs.panelOpen || Notifs.dnd) return;
            if (root.quiet) { root.dot(e, false); return; }
            root.add(Object.assign({}, e, { notif: Notifs.live[e.key] ?? null, sticky: false, timeout: 0 }));
            Notifs.posted(e);
        }
    }

    NotificationServer {
        id: server
        keepOnReload: true // live reloads keep the D-Bus name
        actionsSupported: true
        inlineReplySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: false
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            const e = Notifs.record(n);
            // the history panel shows it live; Do Not Disturb holds all but critical
            if (Notifs.panelOpen) return;
            if (Notifs.dnd && n.urgency !== NotificationUrgency.Critical) return;
            if (root.quiet && n.urgency !== NotificationUrgency.Critical) {
                root.dot(e, false);
                return;
            }
            root.add(root.popupFor(n, e));
            Notifs.posted(e);
        }
    }

    // the dots: on the screen with the fullscreen window, click-through
    PanelWindow {
        id: dotsWin
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        visible: root.quiet && root.dots.length > 0
        anchors.top: true
        anchors.right: true
        implicitWidth: 220
        implicitHeight: 30
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        mask: Region {}
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "bead-notification-dots"

        Rectangle { // a faint backing, so they show on bright games too
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: dotRow.width + 12
            height: 15
            radius: 7.5
            color: Qt.alpha("black", 0.3)
        }
        Row {
            id: dotRow
            anchors.right: parent.right
            anchors.rightMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            layoutDirection: Qt.RightToLeft // the newest on the right, by the corner
            spacing: 5
            Repeater {
                model: ScriptModel {
                    values: root.dots.slice(0, 8)
                    objectProp: "key"
                }
                delegate: Rectangle {
                    required property var modelData
                    width: 7
                    height: 7
                    radius: 3.5
                    color: modelData.critical ? Theme.tone("error") : Theme.tone("action")
                    scale: 0
                    Component.onCompleted: scale = 1
                    Behavior on scale { NumberAnimation { duration: 280; easing.type: Easing.OutBack } }
                }
            }
        }
    }

    PanelWindow {
        id: win

        // always the primary monitor (Settings.home: the island's screen, the first one by default)
        readonly property ShellScreen focused: Quickshell.screens.find(s => s.name === Settings.home) ?? Quickshell.screens[0]
        property ShellScreen held: focused
        screen: held
        visible: root.popups.length > 0
        anchors.top: true
        anchors.right: true
        // the frame strip, in logical px (QT_SCALE_FACTOR applies)
        readonly property real wallW: Theme.frameThickness / devicePixelRatio
        implicitWidth: 350 + 40 + wallW
        implicitHeight: screen?.height ?? 800
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore // the real corner, over the frame
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "bead-notifications"
        // the keyboard only while a reply is being typed
        WlrLayershell.keyboardFocus: root.replyPill ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // clicks only land on the pills themselves
        mask: Region {
            regions: stack.children.filter(c => c.hitRegion).map(c => c.hitRegion)
        }

        // One shape for everything: Caelestia's frame (top + right edges and its
        // rounded inner corner, redrawn in the same colour) melted together
        // with every pill, so the stack is a single blob growing out of the corner.
        ShaderEffect {
            id: blob
            anchors.fill: parent
            fragmentShader: Qt.resolvedUrl("../../shaders/stack.frag.qsb")
            readonly property var shapes: stack.children.filter(c => c.pillRect !== undefined)
            function pr(i: int): vector4d {
                const c = shapes[i];
                if (!c) return Qt.vector4d(0, 0, 0, 0);
                const r = c.pillRect;
                return Qt.vector4d(stack.x + c.x + r.x, stack.y + c.y + r.y, r.width, r.height);
            }
            function br(i: int): vector4d {
                const c = shapes[i];
                if (!c) return Qt.vector4d(0, 0, 0, 0);
                const r = c.bodyRect;
                return Qt.vector4d(stack.x + c.x + r.x, stack.y + c.y + r.y, r.width, r.height);
            }
            property size size: Qt.size(width, height)
            property vector4d inner: Qt.vector4d(-2000, win.wallW, width - win.wallW + 2000, height + 2000)
            property real innerRadius: 20 / win.devicePixelRatio
            property real radius: 16
            property real goo: 20
            property color fill: Theme.frame
            property vector4d p0: pr(0); property vector4d p1: pr(1); property vector4d p2: pr(2); property vector4d p3: pr(3)
            property vector4d p4: pr(4); property vector4d p5: pr(5); property vector4d p6: pr(6); property vector4d p7: pr(7)
            property vector4d b0: br(0); property vector4d b1: br(1); property vector4d b2: br(2); property vector4d b3: br(3)
            property vector4d b4: br(4); property vector4d b5: br(5); property vector4d b6: br(6); property vector4d b7: br(7)
        }

        Column {
            id: stack
            x: win.width - width
            y: win.wallW + 6 // close enough to melt into the top edge
            width: 350 + win.wallW

            Repeater {
                model: ScriptModel {
                    values: root.popups
                    objectProp: "key"
                }

                delegate: Pill {
                    id: pill

                    required property var modelData
                    required property int index
                    readonly property Notification notif: modelData.notif ?? null
                    readonly property var spec: modelData.spec ?? null // a `toast` CLI toast
                    property Region hitRegion: Region { item: pill.hitItem }

                    readonly property bool critical: !spec && modelData.urgency === NotificationUrgency.Critical
                    readonly property string icon: spec?.icon ?? ""
                    readonly property bool iconIsPath: icon.startsWith("/") || /\.(svg|png|jpe?g|webp)$/i.test(icon)

                    kind: spec ? (asking ? "action" : spec.type) : critical ? "error" : "notify"
                    title: asking ? (question?.header || spec.title) + (questions.length > 1 ? "  ·  " + (step + 1) + "/" + questions.length : "")
                        : spec ? spec.title : modelData.summary || modelData.appName || "Notification"
                    desc: asking ? (spec.desc ? spec.desc + "<br>" : "") + root.esc(question?.question ?? "")
                        : spec ? spec.desc ?? "" : modelData.body
                    iconSource: spec ? (iconIsPath ? "file://" + icon : "")
                        : modelData.image ? modelData.image
                        : modelData.appIcon ? Quickshell.iconPath(modelData.appIcon, true) : ""
                    iconGlyph: spec && !iconIsPath ? icon : ""
                    buttons: spec ? spec.buttons ?? []
                        : snoozing ? Snooze.choices
                        // (one that came back has no app behind its old buttons)
                        : (notif ? modelData.actions.filter(a => a.id !== "default" && a.label) : [])
                            .concat(notif?.hasInlineReply ? [{ id: "__reply", label: "Reply" }] : [])
                            .concat([{ id: "__later", label: "Later" }])
                    duration: spec ? spec.duration ?? 6000 : critical ? 0
                        : modelData.timeout > 0 ? modelData.timeout : 6000
                    sticky: modelData.sticky
                    autopilot: spec ? spec.autopilot !== false : true
                    align: "right"
                    edge: true
                    wideButtons: !spec   // notifications; the CLI's choices keep their size
                    closable: !spec
                    drawShape: false // the blob above draws it
                    gap: 6           // close enough to melt into each other
                    calm: true
                    autoExpand: index === 0 || sticky // only the newest opens by itself
                    compact: index > 0 && !sticky      // older ones are just their icon
                    wallW: win.wallW
                    fill: Theme.frame

                    // a replaced notification (same id, new content) updates in place
                    Connections {
                        target: pill.notif
                        ignoreUnknownSignals: true
                        function onSummaryChanged() { pill.resync(); }
                        function onBodyChanged() { pill.resync(); }
                        function onImageChanged() { pill.resync(); }
                        function onClosed() { pill.dismiss("closed"); }
                    }
                    Connections {
                        target: root
                        function onWithdraw(prefix) { if (pill.spec && String(pill.spec.id).startsWith(prefix)) pill.dismiss("dismissed"); }
                    }
                    // ── questions (`glint ask`): one at a time in this one toast ──
                    readonly property bool asking: spec?.type === "ask"
                    readonly property var questions: asking ? spec.questions ?? [] : []
                    property int step: 0
                    readonly property var question: questions[step] ?? null
                    readonly property bool multi: question?.multiSelect === true
                    property var picks: []   // per question: the option indexes picked
                    property var sel: []     // this question's ticks (multi-select)
                    function pick(i: int): void {
                        if (pill.multi) {
                            pill.sel = pill.sel.includes(i) ? pill.sel.filter(x => x !== i) : pill.sel.concat([i]).sort();
                            return;
                        }
                        pill.next([i]);
                    }
                    function next(chosen: var): void {
                        const p = pill.picks.slice();
                        p[pill.step] = chosen;
                        pill.picks = p;
                        if (pill.step + 1 < pill.questions.length) {
                            pill.sel = p[pill.step + 1] ?? [];
                            pill.step++;
                            return;
                        }
                        const q = pill.question;
                        pill.answer("answers:" + JSON.stringify(p), "success:" + (pill.questions.length > 1 ? "Answered" : (q.options[chosen[0]]?.label ?? "Answered")));
                    }
                    function back(): void {
                        if (pill.step === 0) return;
                        pill.sel = pill.picks[pill.step - 1] ?? [];
                        pill.step--;
                    }

                    function resync(): void {
                        if (!notif) return;
                        Notifs.refresh(modelData.key);
                        title = notif.summary || notif.appName || "Notification";
                        desc = notif.body;
                        refresh();
                    }

                    onClicked: {
                        if (notif) Notifs.invoke(modelData.key, "default");
                        dismiss(spec ? "clicked" : "dismissed"); // toast --wait exits 0 on a click
                    }
                    // "Later": the buttons become how long; picking one sends it away
                    // until then (it stays in the history, marked)
                    property bool snoozing: false
                    onAnswered: id => {
                        if (id === "__reply") { pill.startReply(); return; }
                        if (id === "__later") { pill.snoozing = true; return; }
                        if (Snooze.choiceOf(id)) { Notifs.snooze(modelData.key, Snooze.choiceOf(id)); pill.dismiss("timeout"); return; }
                        if (spec) root.report(spec.id, "result", id);
                        else Notifs.invoke(modelData.key, id);
                    }

                    // ── inline reply (apps that offer one: messengers) ──
                    property bool replying: false
                    holding: replying
                    function startReply(): void {
                        replying = true;
                        root.replyPill = pill;
                        replyFocus.restart(); // once the layer has the keyboard
                    }
                    function endReply(send: bool): void {
                        const text = replyField.text.trim();
                        replying = false;
                        if (root.replyPill === pill) root.replyPill = null;
                        if (send && text && notif) { notif.sendInlineReply(text); dismiss("replied"); }
                        replyField.text = "";
                    }
                    Component.onDestruction: if (root.replyPill === pill) root.replyPill = null
                    Timer { id: replyFocus; interval: 80; onTriggered: replyField.forceActiveFocus() }
                    Rectangle {
                        width: parent?.width ?? 0
                        height: pill.replying ? 36 : 0
                        visible: pill.replying
                        radius: 18
                        color: Qt.alpha(Theme.text, 0.07)
                        border.width: 1
                        border.color: Qt.alpha(Theme.tone("action"), replyField.activeFocus ? 0.6 : 0.2)
                        TextInput {
                            id: replyField
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 40
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            font.family: Theme.font
                            font.pixelSize: 13
                            color: Theme.text
                            selectionColor: Qt.alpha(Theme.tone("action"), 0.4)
                            Keys.onReturnPressed: pill.endReply(true)
                            Keys.onEnterPressed: pill.endReply(true)
                            Keys.onEscapePressed: pill.endReply(false)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !replyField.text
                                font: replyField.font
                                color: Theme.subtext
                                text: pill.notif?.inlineReplyPlaceholder || "Reply…"
                            }
                        }
                        Icon {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            name: "send"
                            size: 17
                            fill: 1
                            color: replyField.text.trim() ? Theme.tone("action") : Theme.subtext
                            MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: pill.endReply(true) }
                        }
                    }
                    // moving between questions: the options slide in from the side
                    // they come from (Next: the right, Back: the left) and fade up
                    property int shownStep: 0
                    onStepChanged: {
                        askCol.from = step > shownStep ? 1 : -1;
                        shownStep = step;
                        askSlide.restart();
                    }
                    Column {
                        id: askCol
                        visible: pill.asking
                        width: parent?.width ?? 0
                        spacing: 6
                        property real from: 1
                        transform: Translate { id: askShift }
                        ParallelAnimation {
                            id: askSlide
                            NumberAnimation { target: askShift; property: "x"; from: 28 * askCol.from; to: 0; duration: 320; easing.type: Easing.OutCubic }
                            NumberAnimation { target: askCol; property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutQuad }
                        }
                        Repeater {
                            model: pill.question?.options ?? []
                            delegate: Rectangle {
                                id: opt
                                required property var modelData
                                required property int index
                                readonly property bool ticked: pill.sel.includes(index)
                                width: parent.width
                                height: optText.implicitHeight + 18
                                radius: 12
                                color: Qt.alpha(Theme.tone("action"), optMa.containsMouse ? 0.22 : ticked ? 0.18 : 0.1)
                                border.width: ticked ? 1 : 0
                                border.color: Qt.alpha(Theme.tone("action"), 0.6)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Icon {
                                    id: tick
                                    visible: pill.multi
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: opt.ticked ? "check_box" : "check_box_outline_blank"
                                    fill: opt.ticked ? 1 : 0
                                    size: 18
                                    color: Theme.tone("action")
                                }
                                Column {
                                    id: optText
                                    anchors.left: pill.multi ? tick.right : parent.left
                                    anchors.leftMargin: pill.multi ? 8 : 12
                                    anchors.right: parent.right
                                    anchors.rightMargin: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2
                                    Text {
                                        width: parent.width
                                        wrapMode: Text.Wrap
                                        font.family: Theme.font
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                        color: Theme.text
                                        text: opt.modelData.label ?? ""
                                    }
                                    Text {
                                        visible: text !== ""
                                        width: parent.width
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                        font.family: Theme.font
                                        font.pixelSize: 12
                                        color: Theme.subtext
                                        text: opt.modelData.description ?? ""
                                    }
                                }
                                MouseArea {
                                    id: optMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: pill.pick(opt.index)
                                }
                            }
                        }
                        // Back, and for a multi-select question Next / Send
                        Item {
                            visible: pill.step > 0 || pill.multi
                            width: parent.width
                            height: 32
                            Rectangle {
                                visible: pill.step > 0
                                width: backLbl.implicitWidth + 28
                                height: 32
                                radius: 16
                                color: Qt.alpha(Theme.neutral, backMa.containsMouse ? 0.25 : 0.15)
                                Text {
                                    id: backLbl
                                    anchors.centerIn: parent
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    color: Theme.text
                                    text: "Back"
                                }
                                MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pill.back() }
                            }
                            Rectangle {
                                visible: pill.multi
                                anchors.right: parent.right
                                width: parent.width - (pill.step > 0 ? backLbl.implicitWidth + 36 : 0)
                                height: 32
                                radius: 16
                                opacity: pill.sel.length ? 1 : 0.45
                                color: Qt.alpha(Theme.tone("action"), nextMa.containsMouse && pill.sel.length ? 0.3 : 0.2)
                                Text {
                                    anchors.centerIn: parent
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                    color: Theme.tone("action")
                                    text: pill.step + 1 < pill.questions.length ? "Next" : "Send"
                                }
                                MouseArea { id: nextMa; anchors.fill: parent; hoverEnabled: true; cursorShape: pill.sel.length ? Qt.PointingHandCursor : Qt.ArrowCursor; onClicked: if (pill.sel.length) pill.next(pill.sel) }
                            }
                        }
                    }
                    // promise toasts: the CLI rewrites this file when its command ends
                    FileView {
                        path: pill.spec?.state ?? ""
                        watchChanges: path !== ""
                        printErrors: false
                        onFileChanged: reload()
                        onLoaded: pill.applyState(text())
                    }
                    function applyState(t: string): void {
                        if (!t || !t.trim()) return;
                        let u;
                        try { u = JSON.parse(t); } catch (e) { return; }
                        if (u.type) kind = u.type;
                        if (u.title !== undefined) title = u.title;
                        if (u.desc !== undefined) desc = u.desc;
                        if (u.duration !== undefined) duration = u.duration;
                        root.report(spec.id, "ack", "1");
                        refresh();
                    }
                    onFinished: reason => {
                        if (spec) root.report(spec.id, "result", reason);
                        // timed out: it stays in the history; dismissed or acted on: gone
                        if (modelData.notif && reason !== "timeout" && reason !== "closed")
                            Notifs.remove(modelData.key);
                        root.remove(modelData.key);
                    }
                }
            }
        }
    }
}
