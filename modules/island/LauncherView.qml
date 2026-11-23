pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Io
import qs.components
import qs.config
import qs.services

// The island as a launcher: type to fuzzy-search apps (the ones you launch
// most float up), do maths (qalc: "2^10", "5 usd to eur"; Enter copies the
// answer), or start with ">" for actions (lock, suspend, log out, reboot,
// shut down, do not disturb, hide island, clear notifications, "timer 10m",
// stopwatch), ";" for clipboard history (Enter pastes it where you were,
// Shift+Enter only copies, Shift+Delete forgets it), ":" for emoji and
// symbols (Enter types it, Shift+Enter copies), or "?" to ask Claude (services/Ask.qml): the answer streams in
// below; Enter on an edited question asks a follow-up. Log out / reboot /
// shut down need a second Enter.
// Keys: Up/Down (Tab, Ctrl+J/K/N/P), Enter, Esc.
Item {
    id: root

    signal close()

    readonly property int rowH: 46
    readonly property int maxRows: 7
    readonly property int shown: Math.min(results.length, maxRows)
    readonly property bool asking: query.trim().startsWith("?")
    readonly property string askText: query.trim().slice(1).trim()
    readonly property bool answering: asking && Ask.active
    readonly property real wantW: answering ? 640 : clipping && results.length ? 780 : 600
    readonly property int previewW: 280 // clipboard mode: the selected entry in full
    // clipboard mode keeps room for the preview even with few results
    readonly property real wantH: 58 + (answering ? answer.height + 16 : results.length ? (clipping ? Math.max(shown, 4) : shown) * rowH + 14 : 52)

    property string query: ""
    property int current: 0
    property string confirming: ""   // action id waiting for a second Enter

    function reset(seed: string): void {
        Ask.clear();
        field.text = seed ?? "";
        current = 0;
        confirming = "";
        calc.result = "";
    }
    function focusField(): void { field.forceActiveFocus(); }

    // Claude's markdown -> rich text: code blocks in a monospace box, `inline
    // code`, **bold**, *italic*, headings, lists, paragraphs (Qt's own markdown
    // mode shows code as plain text). Also fine on a half-streamed answer.
    function md(src: string): string {
        const esc = t => t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
        const codeBg = Qt.alpha(Theme.text, 0.08);
        const bg = "rgba(" + Math.round(codeBg.r * 255) + "," + Math.round(codeBg.g * 255) + "," + Math.round(codeBg.b * 255) + "," + codeBg.a.toFixed(2) + ")";
        const inline = t => esc(t)
            .replace(/`([^`]+)`/g, `<span style="font-family:monospace; background-color:${bg};">&nbsp;$1&nbsp;</span>`)
            .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
            .replace(/(^|[^*])\*([^*\s][^*]*)\*/g, "$1<i>$2</i>");
        const out = [];
        let code = null, list = null, para = [];
        const flushPara = () => { if (para.length) out.push("<p>" + para.map(inline).join("<br>") + "</p>"); para = []; };
        const flushList = () => { if (list) out.push(`<${list.tag}>` + list.items.map(i => "<li>" + inline(i) + "</li>").join("") + `</${list.tag}>`); list = null; };
        for (const line of src.split("\n")) {
            if (code !== null) {
                if (/^\s*```/.test(line)) { out.push(`<table width="100%" cellpadding="8" style="background-color:${bg};"><tr><td><pre style="font-family:monospace;">${esc(code.join("\n"))}</pre></td></tr></table>`); code = null; }
                else code.push(line);
                continue;
            }
            if (/^\s*```/.test(line)) { flushPara(); flushList(); code = []; continue; }
            const li = /^\s*(?:[-*•]|(\d+)[.)])\s+(.*)$/.exec(line);
            if (li) {
                flushPara();
                const tag = li[1] ? "ol" : "ul";
                if (!list || list.tag !== tag) { flushList(); list = { tag: tag, items: [] }; }
                list.items.push(li[2]);
                continue;
            }
            const h = /^#{1,6}\s+(.*)$/.exec(line);
            if (h) { flushPara(); flushList(); out.push("<p><b>" + inline(h[1]) + "</b></p>"); continue; }
            if (!line.trim()) { flushPara(); flushList(); continue; }
            flushList();
            para.push(line);
        }
        if (code !== null) out.push(`<pre style="font-family:monospace;">${esc(code.join("\n"))}</pre>`); // still streaming
        flushPara(); flushList();
        return out.join("");
    }

    // ── open windows ──
    function windowsFor(q: string): list<var> {
        const ql = q.toLowerCase();
        const out = [];
        for (const t of Hyprland.toplevels.values) {
            const app = t.wayland?.appId ?? t.lastIpcObject?.class ?? "";
            const entry = Apps.entryFor(app);
            const name = entry?.name ?? app;
            const title = t.title ?? "";
            const s = Math.max(Apps.score(ql, title.toLowerCase()), Apps.score(ql, name.toLowerCase()) * 1.1);
            if (s > 0) out.push({ s: s, t: t, title: title || name, name: name, icon: entry?.icon ?? app, ws: t.workspace?.name ?? "" });
        }
        out.sort((a, b) => b.s - a.s);
        return out.slice(0, 5);
    }
    function focusWindow(w: var): void {
        const a = String(w.t.address);
        Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ window = "address:${a.startsWith("0x") ? a : "0x" + a}" })`]);
    }

    // ── maths ──
    readonly property bool mathy: /^=/.test(query.trim()) || /^[\d(.\-+√]/.test(query.trim())
    readonly property string expr: query.trim().replace(/^=\s*/, "")
    QtObject {
        id: calc
        property string result: ""
    }
    onExprChanged: { calc.result = ""; if (mathy && expr) calcTimer.restart(); }
    Timer { id: calcTimer; interval: 140; onTriggered: { qalc.running = false; qalc.command = ["qalc", "-t", "--", root.expr]; qalc.running = true; } }
    Process {
        id: qalc
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim();
                calc.result = t && !/^error/i.test(t) && t !== root.expr ? t : "";
            }
        }
    }

    // ── actions ──
    // timers and the stopwatch: what's running comes first, with its controls
    readonly property list<var> timeActions: {
        const out = [];
        for (const t of Countdown.items) {
            const what = t.kind === "stopwatch" ? "the stopwatch" : t.name + " timer";
            out.push({ id: "c-toggle-" + t.id, op: "toggle", tid: t.id, glyph: t.running ? "pause" : "play_arrow",
                title: (t.running ? "Pause " : "Resume ") + what, sub: t.running ? "Running" : "Paused" });
            if (t.kind === "stopwatch")
                out.push({ id: "c-lap-" + t.id, op: "lap", tid: t.id, glyph: "flag", title: "Lap", sub: (t.laps.length ? t.laps.length + " so far" : "Mark a lap") });
            else
                out.push({ id: "c-add-" + t.id, op: "add", tid: t.id, glyph: "more_time", title: "Add a minute to the " + what, sub: "Rides on the island" });
            out.push({ id: "c-stop-" + t.id, op: "stop", tid: t.id, glyph: "stop_circle", title: "Stop " + what, sub: "See them all on the dashboard's Timers tab" });
        }
        if (Countdown.items.length > 1)
            out.push({ id: "c-stopall", op: "stopall", glyph: "timer_off", title: "Stop all timers", sub: Countdown.items.length + " running" });
        out.push({ id: "timermenu", glyph: "timer", title: "Timer…", sub: "Pick a length, or type one: > timer 7m30s" });
        out.push({ id: "stopwatch", glyph: "avg_pace", title: Countdown.stopwatch ? "Restart the stopwatch" : "Start a stopwatch", sub: "Laps and all, on the dashboard's Timers tab" });
        return out;
    }
    readonly property list<var> presets: [
        { m: 1, n: "1 minute" }, { m: 3, n: "3 minutes", note: "Tea" }, { m: 5, n: "5 minutes" },
        { m: 10, n: "10 minutes" }, { m: 15, n: "15 minutes" }, { m: 25, n: "25 minutes", note: "Focus" },
        { m: 45, n: "45 minutes" }, { m: 60, n: "1 hour" }
    ]
    readonly property list<var> actions: [
        ...timeActions,
        ...Session.actions,
        { id: "dnd", title: Notifs.dnd ? "Turn off Do Not Disturb" : "Do Not Disturb", sub: "Hold notification popups", glyph: Notifs.dnd ? "notifications_active" : "notifications_off" },
        { id: "clear", title: "Clear notifications", sub: Notifs.entries.length + " in history", glyph: "clear_all" },
        { id: "island", title: "Hide / show the island", sub: "Same as Super+I", glyph: "visibility" },
        { id: "settings", title: "Settings", sub: "Idle timings, colours, main monitor…", glyph: "settings" },
        { id: "walls", title: "Wallpapers", sub: "Pick one on the dashboard; the colours follow", glyph: "wallpaper" },
        { id: "wallshuffle", title: "Shuffle wallpaper", sub: "Another one at random", glyph: "shuffle" },
        { id: "awake", title: Idle.keepAwake ? "Stop keeping awake" : "Keep awake", sub: "Don't lock, blank or sleep when idle", glyph: "coffee" },
        // toggles
        { id: "wifi", title: Networking.wifiEnabled ? "Turn Wi-Fi off" : "Turn Wi-Fi on", sub: "Wi-Fi", glyph: Networking.wifiEnabled ? "wifi_off" : "wifi" },
        { id: "bt", title: Bluetooth.defaultAdapter?.enabled ? "Turn Bluetooth off" : "Turn Bluetooth on", sub: "Bluetooth", glyph: Bluetooth.defaultAdapter?.enabled ? "bluetooth_disabled" : "bluetooth" },
        { id: "mute", title: Audio.muted ? "Unmute sound" : "Mute sound", sub: "Output", glyph: Audio.muted ? "volume_up" : "volume_off" },
        { id: "mic", title: Audio.micMuted ? "Unmute microphone" : "Mute microphone", sub: "Input", glyph: Audio.micMuted ? "mic" : "mic_off" },
        // capture
        { id: "shot", title: "Screenshot an area", sub: "Select a region", glyph: "screenshot_region" },
        { id: "shotscreen", title: "Screenshot the screen", sub: "The focused monitor", glyph: "screenshot_monitor" },
        { id: "rec", title: Recorder.recording ? "Stop recording" : "Record the screen", sub: Recorder.recording ? Recorder.label : "Without sound", glyph: Recorder.recording ? "stop_circle" : "screen_record" },
        { id: "pick", title: "Pick a colour", sub: "Copies its hex", glyph: "colorize" },
        // bead and the vault
        { id: "restart", title: "Restart bead", sub: "Behind a still, so nothing flashes", glyph: "restart_alt" },
        { id: "vault", title: "Open the vault", sub: "Obsidian · brain", glyph: "book_2" }
    ]
    function runAction(a: var): void {
        if (a.op) {
            switch (a.op) {
            case "toggle": Countdown.toggle(a.tid); break;
            case "add": Countdown.addTime(a.tid, 60000); break;
            case "lap": Countdown.lap(a.tid); break;
            case "stop": Countdown.stop(a.tid); break;
            case "stopall": Countdown.stopAll(); break;
            }
            return;
        }
        switch (a.id) {
        case "dnd": Notifs.dnd = !Notifs.dnd; break;
        case "clear": Notifs.clear(); break;
        case "island": islandToggle.running = true; break;
        case "stopwatch": Countdown.startStopwatch(); break;
        case "awake": Idle.keepAwake = !Idle.keepAwake; break;
        case "walls": Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "dashboard", "tab", "5"]); break;
        case "settings": Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "dashboard", "tab", "6"]); break;
        case "wallshuffle": Wallpaper.random("all"); break;
        case "timer": Countdown.startTimer(a.ms, a.name ?? ""); break;
        case "wifi": Networking.wifiEnabled = !Networking.wifiEnabled; break;
        case "bt": if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled; break;
        case "mute": Audio.toggleMute(); break;
        case "mic": Audio.toggleMicMute(); break;
        // after the island has closed, so it isn't in the picture
        case "shot": later(() => Capture.shot("area")); break;
        case "shotscreen": later(() => Capture.shot("screen")); break;
        case "rec": if (Recorder.recording) Recorder.stop(); else later(() => Capture.record("screen", false)); break;
        case "pick": later(() => Capture.pickColour()); break;
        case "restart": Quickshell.execDetached(["bead", "restart"]); break;
        case "vault": Quickshell.execDetached(["xdg-open", "obsidian://open?vault=brain"]); break;
        default: Session.run(a);
        }
    }
    Timer { id: laterTimer; interval: 450; property var fn: null; onTriggered: if (fn) fn() }
    function later(fn: var): void { laterTimer.fn = fn; laterTimer.restart(); }
    Process { id: islandToggle; command: ["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "island", "toggle"] }

    // ── results ──
    readonly property bool clipping: query.startsWith(";")
    readonly property bool emojiing: query.startsWith(":")
    onClippingChanged: if (clipping) Clipboard.load()
    readonly property list<var> results: {
        const q = query.trim();
        if (clipping) {
            const words = q.slice(1).trim().toLowerCase().split(/\s+/).filter(w => w);
            // secrets match only by kind, so typing part of one doesn't find it
            const hay = e => e.image ? `image ${e.image.fmt} ${e.image.w}x${e.image.h} ${e.image.w}×${e.image.h}` : e.type === "secret" ? "secret hidden" : e.text.toLowerCase();
            const hit = e => !words.length || words.every(w => hay(e).includes(w));
            return Clipboard.entries.filter(hit).slice(0, 80).map(e => ({ kind: "clip", c: e }));
        }
        if (emojiing) return Emoji.search(q.slice(1)).map(e => ({ kind: "emoji", m: e }));
        if (q.startsWith("?")) return askText ? [{ kind: "ask", q: askText }] : [];
        if (q.startsWith(">")) {
            const a = q.slice(1).trim().toLowerCase();
            const out = [];
            // "> timer [length]": the presets, and whatever length you typed
            const t = /^tim(?:er?)?(?:\s+(.*))?$/.exec(a);
            if (t) {
                const rest = (t[1] ?? "").trim();
                const ms = Countdown.parse(rest);
                if (ms > 0)
                    out.push({ kind: "action", a: { id: "timer", ms: ms, title: "Start a " + Countdown.fmtTotal(ms) + " timer", sub: "Rides on the island", glyph: "timer" } });
                for (const p of presets)
                    if (!rest || String(p.m).startsWith(rest) || p.n.startsWith(rest) || (p.note ?? "").toLowerCase().startsWith(rest))
                        if (p.m * 60000 !== ms)
                            out.push({ kind: "action", a: { id: "timer", ms: p.m * 60000, name: p.note ?? "", title: "Start a " + (p.m === 60 ? "1 hour" : p.m + " minute") + " timer",
                                sub: p.note ? p.note + " · rides on the island" : "Rides on the island", glyph: "timer" } });
                if (/^timer\s/.test(a) || out.length) return out;
            }
            const scored = actions.map((x, i) => ({ x: x, i: i, s: a ? Apps.score(a, x.title.toLowerCase()) : 1 })).filter(x => x.s > 0);
            scored.sort((p, q2) => q2.s - p.s || p.i - q2.i); // keep the list order on ties
            return out.concat(scored.map(x => ({ kind: "action", a: x.x })));
        }
        const out = [];
        if (mathy && calc.result) out.push({ kind: "calc" });
        // open windows that match, above the apps: Enter switches to one
        if (q && !mathy) out.push(...windowsFor(q).map(w => ({ kind: "win", w: w })));
        return out.concat(Apps.search(q).slice(0, 40).map(e => ({ kind: "app", e: e })));
    }
    onResultsChanged: { current = 0; confirming = ""; }

    function move(d: int): void {
        if (!results.length) return;
        current = (current + d + results.length) % results.length;
        confirming = "";
        list.positionViewAtIndex(current, ListView.Contain);
    }
    function activate(i: int, copyOnly: bool): void {
        const r = results[i];
        if (!r) return;
        if (r.kind === "clip") { close(); Clipboard.pick(r.c, copyOnly); }
        else if (r.kind === "emoji") { close(); Emoji.type(r.m, copyOnly); }
        else if (r.kind === "ask") Ask.ask(r.q);
        else if (r.kind === "app") { Apps.launch(r.e); close(); }
        else if (r.kind === "win") { close(); focusWindow(r.w); }
        else if (r.kind === "calc") { Quickshell.execDetached(["wl-copy", calc.result]); close(); }
        else {
            if (r.a.id === "timermenu") { field.text = "> timer "; return; } // stay open: pick a length
            if (r.a.confirm && confirming !== r.a.id) { current = i; confirming = r.a.id; return; }
            close();
            runAction(r.a);
        }
    }

    // ── search box ──
    Item {
        id: bar
        x: 18
        y: 10
        width: parent.width - 36
        height: 40
        Rectangle {
            anchors.fill: parent
            radius: 20
            color: Qt.alpha(Theme.text, 0.06)
        }
        Icon {
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            name: root.asking ? "auto_awesome" : root.clipping ? "content_paste" : root.emojiing ? "mood" : root.query.trim().startsWith(">") ? "bolt" : root.mathy ? "calculate" : "search"
            color: root.asking ? Theme.tone("action") : Theme.subtext
            size: 20
        }
        TextInput {
            id: field
            x: 44
            width: parent.width - 44 - 16
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.font
            font.pixelSize: 15
            color: Theme.text
            selectionColor: Qt.alpha(Theme.tone("action"), 0.4)
            clip: true
            onTextChanged: root.query = text
            Keys.onPressed: e => {
                const ctrl = e.modifiers & Qt.ControlModifier;
                if (root.answering) { // the answer is showing: arrows scroll it, Enter asks again
                    if (e.key === Qt.Key_Down || e.key === Qt.Key_Up) { answer.scroll(e.key === Qt.Key_Down ? 60 : -60); e.accepted = true; return; }
                    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        if (root.askText && (root.askText !== Ask.question || Ask.st === "error")) Ask.ask(root.askText);
                        e.accepted = true;
                        return;
                    }
                }
                if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab || ctrl && (e.key === Qt.Key_J || e.key === Qt.Key_N)) { root.move(1); e.accepted = true; }
                else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab || ctrl && (e.key === Qt.Key_K || e.key === Qt.Key_P)) { root.move(-1); e.accepted = true; }
                else if (e.key === Qt.Key_PageDown) { root.move(Math.min(root.maxRows, root.results.length - 1 - root.current)); e.accepted = true; }
                else if (e.key === Qt.Key_PageUp) { root.move(-Math.min(root.maxRows, root.current)); e.accepted = true; }
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.activate(root.current, !!(e.modifiers & Qt.ShiftModifier)); e.accepted = true; }
                else if (e.key === Qt.Key_Delete && (e.modifiers & Qt.ShiftModifier) && root.results[root.current]?.kind === "clip") {
                    Clipboard.remove(root.results[root.current].c); e.accepted = true;
                }
                else if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; }
            }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                visible: !field.text && !field.preeditText
                font.pixelSize: 15
                text: "Search apps, = maths, > actions, ; clipboard, : emoji, ? ask Claude"
            }
        }
    }

    // ── results ──
    ListView {
        id: list
        visible: !root.answering
        x: 10
        y: 58
        width: parent.width - 20 - (root.clipping && root.results.length ? root.previewW + 10 : 0)
        height: root.shown * root.rowH
        clip: true
        model: root.results
        currentIndex: root.current
        boundsBehavior: Flickable.StopAtBounds
        highlightFollowsCurrentItem: false

        Rectangle { // the selection springs between rows
            z: -1
            width: list.width
            height: root.rowH
            radius: 14
            y: root.current * root.rowH - list.contentY
            visible: root.results.length > 0
            color: root.confirming ? Qt.alpha(Theme.tone("error"), 0.16) : Qt.alpha(Theme.text, 0.08)
            Behavior on y { SpringAnimation { spring: 5; damping: 0.34; epsilon: 0.2 } }
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool sel: index === root.current
            readonly property var a: modelData.a ?? null
            readonly property bool confirm: !!a && root.confirming === a.id
            width: list.width
            height: root.rowH

            Item {
                id: ico
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30
                readonly property string path: row.modelData.kind === "app" ? Apps.iconPath(row.modelData.e.icon)
                    : row.modelData.kind === "win" ? Apps.iconPath(row.modelData.w.icon) : ""
                Image {
                    id: appImg
                    anchors.fill: parent
                    sourceSize: Qt.size(64, 64)
                    source: ico.path
                    visible: status === Image.Ready
                    asynchronous: true
                }
                Text { // emoji / symbol
                    anchors.centerIn: parent
                    visible: row.modelData.kind === "emoji"
                    font.pixelSize: 21
                    color: Theme.text
                    text: row.modelData.m?.c ?? ""
                }
                Rectangle { // clipboard colour: the colour itself
                    anchors.fill: parent
                    radius: 15
                    visible: row.modelData.c?.type === "colour"
                    color: visible ? Clipboard.colourOf(row.modelData.c.text) : "transparent"
                    border.width: 1
                    border.color: Qt.alpha(Theme.text, 0.18)
                }
                Rectangle { // clipboard image
                    id: clipThumb
                    readonly property var img: row.modelData.c?.image ?? null
                    readonly property string src: img ? (Clipboard.thumbs[row.modelData.c.id] ?? "") : ""
                    anchors.fill: parent
                    radius: 7
                    visible: !!img
                    color: Qt.alpha(Theme.text, 0.08)
                    Component.onCompleted: if (img) Clipboard.ensureThumb(row.modelData.c)
                    // only image rows build the rounded thumbnail: its mask needs an
                    // offscreen layer, far too heavy to make for every row of every mode
                    Loader {
                        anchors.fill: parent
                        active: !!clipThumb.img
                        sourceComponent: Item {
                            Image {
                                id: clipImg
                                anchors.fill: parent
                                source: clipThumb.src
                                sourceSize: Qt.size(96, 96)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: false
                            }
                            Rectangle { id: clipMask; anchors.fill: parent; radius: 7; visible: false; layer.enabled: true }
                            MultiEffect { // rounded (clip ignores radius)
                                anchors.fill: parent
                                source: clipImg
                                maskEnabled: true
                                maskSource: clipMask
                                visible: clipImg.status === Image.Ready
                            }
                        }
                    }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: 15
                    visible: appImg.status !== Image.Ready && row.modelData.kind !== "emoji" && !clipThumb.img && row.modelData.c?.type !== "colour"
                    color: row.confirm ? Qt.alpha(Theme.tone("error"), 0.2) : Qt.alpha(Theme.tone("action"), 0.14)
                    Icon {
                        anchors.centerIn: parent
                        size: 17
                        fill: 1
                        color: row.confirm ? Theme.tone("error") : Theme.tone("action")
                        name: row.modelData.kind === "calc" ? "calculate" : row.modelData.kind === "action" ? row.a.glyph
                            : row.modelData.kind === "ask" ? "auto_awesome" : row.modelData.kind === "clip" ? root.clipGlyph(row.modelData.c.type)
                            : row.modelData.kind === "win" ? "select_window" : "apps"
                    }
                }
            }
            Column {
                x: 52
                width: parent.width - 52 - 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: 14
                    font.weight: row.sel ? Font.DemiBold : Font.Medium
                    color: row.confirm ? Theme.tone("error") : Theme.text
                    text: row.modelData.kind === "app" ? row.modelData.e.name
                        : row.modelData.kind === "win" ? row.modelData.w.title
                        : row.modelData.kind === "calc" ? calc.result
                        : row.modelData.kind === "ask" ? row.modelData.q
                        : row.modelData.kind === "clip" ? (row.modelData.c.image ? "Image · " + row.modelData.c.image.w + "×" + row.modelData.c.image.h
                            : row.modelData.c.type === "secret" ? "•".repeat(12) + "  hidden"
                            : row.modelData.c.text.replace(/\s+/g, " ").trim())
                        : row.modelData.kind === "emoji" ? row.modelData.m.name
                        : row.confirm ? "Press Enter again to " + row.a.title.toLowerCase() : row.a.title
                }
                Label {
                    width: parent.width
                    elide: Text.ElideRight
                    font.pixelSize: 11
                    visible: text !== ""
                    text: row.modelData.kind === "app" ? (row.modelData.e.comment || row.modelData.e.genericName || "")
                        : row.modelData.kind === "win" ? "Switch to " + row.modelData.w.name + (row.modelData.w.ws ? "  ·  workspace " + row.modelData.w.ws : "")
                        : row.modelData.kind === "calc" ? "= " + root.expr + "  ·  Enter copies"
                        : row.modelData.kind === "ask" ? "Ask Claude  ·  Enter"
                        : row.modelData.kind === "clip" ? (row.sel ? "Enter pastes  ·  Shift+Enter copies  ·  Shift+Del forgets" : root.clipHint(row.modelData.c))
                        : row.modelData.kind === "emoji" ? (row.sel ? "Enter types it  ·  Shift+Enter copies" : "")
                        : row.a.sub
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: if (root.current !== row.index) { root.current = row.index; root.confirming = ""; }
                onClicked: root.activate(row.index, false)
            }
        }
    }

    function clipGlyph(t: string): string {
        return ({ secret: "key", link: "link", path: "folder", command: "terminal", code: "code", number: "tag", text: "notes" })[t] ?? "content_paste";
    }
    function clipHint(c: var): string {
        if (c.type === "link") { const m = /^\w+:\/\/([^/]+)/.exec(c.text.trim()); return m ? m[1] : "Link"; }
        return ({ secret: "Looks like a key or token", path: "Path", command: "Command", code: "Code", colour: "Colour" })[c.type] ?? "";
    }

    // ── clipboard: the selected entry in full ──
    readonly property var clipSel: clipping ? (results[current]?.c ?? null) : null
    onClipSelChanged: if (clipSel) { if (clipSel.image) Clipboard.ensureThumb(clipSel); else if (clipSel.type !== "secret") Clipboard.loadFull(clipSel); }
    Rectangle {
        id: preview
        visible: root.clipping && !!root.clipSel && !root.answering
        x: list.x + list.width + 10
        y: 58
        width: root.previewW
        height: Math.max(list.height, 4 * root.rowH)
        radius: 14
        color: Qt.alpha(Theme.text, 0.05)
        clip: true
        readonly property var e: root.clipSel
        readonly property string body: e && !e.image && e.type !== "secret" ? (Clipboard.full[e.id] ?? e.text) : ""
        readonly property bool mono: !!e && ["code", "command", "path"].includes(e.type)

        // image
        Image {
            visible: !!preview.e?.image
            anchors.fill: parent
            anchors.margins: 10
            anchors.bottomMargin: 34
            source: preview.e?.image ? (Clipboard.thumbs[preview.e.id] ?? "") : ""
            sourceSize: Qt.size(560, 560)
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        // secret
        Column {
            visible: preview.e?.type === "secret"
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -12
            spacing: 8
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "key"; size: 34; fill: 1; color: Theme.subtext }
            Label { anchors.horizontalCenter: parent.horizontalCenter; text: "Hidden: looks like a key or token" }
            Label { anchors.horizontalCenter: parent.horizontalCenter; font.pixelSize: 11; text: "Enter still pastes it  ·  Shift+Del forgets it" }
        }
        // colour
        Column {
            visible: preview.e?.type === "colour"
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -12
            spacing: 10
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 120; height: 120; radius: 22
                color: preview.e?.type === "colour" ? Clipboard.colourOf(preview.e.text) : "transparent"
                border.width: 1
                border.color: Qt.alpha(Theme.text, 0.18)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: "monospace"
                font.pixelSize: 15
                color: Theme.text
                text: preview.e?.text.trim() ?? ""
            }
        }
        // text
        Text {
            visible: !!preview.e && !preview.e.image && preview.e.type !== "colour" && preview.e.type !== "secret"
            x: 14; y: 12
            width: parent.width - 28
            height: parent.height - 12 - 34
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: preview.mono ? "monospace" : Theme.font
            font.pixelSize: preview.mono ? 12 : 13
            lineHeight: 1.15
            color: Theme.text
            text: preview.body
        }
        // what it is
        Label {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            font.pixelSize: 11
            text: {
                const e = preview.e;
                if (!e) return "";
                if (e.image) return e.image.fmt.toUpperCase() + "  ·  " + e.image.w + " × " + e.image.h;
                if (e.type === "secret") return "Secret  ·  " + e.text.trim().length + " characters";
                const t = preview.body;
                const lines = t.replace(/\n$/, "").split("\n").length;
                const kind = ({ link: "Link", path: "Path", command: "Command", code: "Code", colour: "Colour", number: "Number" })[e.type] ?? "Text";
                return kind + "  ·  " + t.length.toLocaleString() + (t.length >= 20000 ? "+" : "") + " characters" + (lines > 1 ? "  ·  " + lines + " lines" : "");
            }
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 66
        visible: root.results.length === 0 && !root.answering
        Label { text: root.clipping ? (Clipboard.loading ? "Loading…" : Clipboard.entries.length ? "No matches" : "Nothing on the clipboard history") : root.asking ? "Type a question for Claude" : root.mathy ? "Working it out…" : "Nothing found" }
    }

    // ── Claude's answer ──
    Item {
        id: answer
        x: 18
        y: 58
        width: parent.width - 36
        height: Math.min(380, Math.max(44, body.implicitHeight + 8))
        visible: root.answering
        clip: true
        function scroll(dy: real): void {
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY + dy));
        }

        Flickable {
            id: flick
            anchors.fill: parent
            contentWidth: width
            contentHeight: body.implicitHeight + 8
            boundsBehavior: Flickable.StopAtBounds
            // follow the stream while it's coming in
            onContentHeightChanged: if (Ask.busy) contentY = Math.max(0, contentHeight - height)

            Column {
                id: body
                x: 4
                width: parent.width - 8
                spacing: 10

                Row { // thinking: three breathing dots
                    visible: Ask.busy && !Ask.answer
                    spacing: 5
                    height: 24
                    Repeater {
                        model: 3
                        Rectangle {
                            id: dotItem
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7; height: 7; radius: 3.5
                            color: Theme.tone("action")
                            SequentialAnimation on opacity {
                                running: Ask.busy && !Ask.answer
                                loops: Animation.Infinite
                                PauseAnimation { duration: dotItem.index * 150 }
                                NumberAnimation { to: 0.25; duration: 400; easing.type: Easing.InOutSine }
                                NumberAnimation { to: 1; duration: 400; easing.type: Easing.InOutSine }
                            }
                        }
                    }
                    Label { anchors.verticalCenter: parent.verticalCenter; leftPadding: 6; text: "Claude is thinking…" }
                }

                TextEdit {
                    width: parent.width
                    visible: !!Ask.answer
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.RichText
                    font.family: Theme.font
                    font.pixelSize: 14
                    color: Theme.text
                    selectionColor: Qt.alpha(Theme.tone("action"), 0.4)
                    text: root.md(Ask.answer)
                }

                Label {
                    width: parent.width
                    visible: Ask.st === "error"
                    wrapMode: Text.Wrap
                    color: Theme.tone("error")
                    text: Ask.error
                }

                Row {
                    visible: Ask.st === "done"
                    spacing: 8
                    Rectangle {
                        id: copyBtn
                        width: copyRow.implicitWidth + 24
                        height: 28
                        radius: 14
                        color: Qt.alpha(Theme.text, copyMa.containsMouse ? 0.12 : 0.07)
                        property bool copied: false
                        Row {
                            id: copyRow
                            anchors.centerIn: parent
                            spacing: 6
                            Icon { anchors.verticalCenter: parent.verticalCenter; name: copyBtn.copied ? "check" : "content_copy"; size: 15; color: Theme.text }
                            Label { anchors.verticalCenter: parent.verticalCenter; color: Theme.text; text: copyBtn.copied ? "Copied" : "Copy" }
                        }
                        MouseArea {
                            id: copyMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Quickshell.execDetached(["wl-copy", Ask.answer]); copyBtn.copied = true; }
                        }
                        Connections { target: Ask; function onAnswerChanged() { copyBtn.copied = false; } }
                    }
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: 11
                        text: "Edit the question and press Enter for a follow-up"
                    }
                }
            }
        }
    }
}
