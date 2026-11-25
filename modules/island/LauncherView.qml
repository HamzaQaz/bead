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
import "../../services/store.js" as StoreJs
import "launcher-actions.js" as RowActions
import "../../services/pkgs.js" as Pkgs
import "keys.js" as KeySheet

// The island as a launcher: type to fuzzy-search apps (the ones you launch
// most float up), do maths (qalc: "2^10", "5 usd to eur"; Enter copies the
// answer), or start with ">" for actions (lock, suspend, log out, reboot,
// shut down, do not disturb, hide island, clear notifications, "timer 10m",
// stopwatch), ";" for clipboard history (Enter pastes it where you were,
// Shift+Enter only copies, Shift+Delete forgets it), ":" for emoji and
// symbols (Enter types it, Shift+Enter copies), "/" for files (fd; Enter opens,
// Shift+Enter copies the path), or "?" to ask Pearl (services/Ask.qml): the answer streams in
// below; Enter on an edited question asks a follow-up. Log out / reboot /
// shut down need a second Enter.
// Keys: Up/Down (Ctrl+J/K/N/P), Enter, Esc; Tab: what you can do with the
// selected app, window or file (Shift+Tab or Esc: back).
Item {
    id: root

    signal close()
    signal say(string icon, string text, string tone) // a short note on the island

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

    // a mode's symbol (? > ; :) doesn't stay in the field: it becomes a chip
    // before it, and Backspace at the start of the field takes it away again.
    // `query` still reads as before ("?question"), so the rest is unchanged
    property string mode: ""
    property string fieldText: ""
    readonly property string query: acting ? "" : mode + fieldText

    // ── Tab: what you can do with a row (launcher-actions.js). While its
    // actions show, the row's name is the chip, and typing narrows them or
    // gives a workspace number ──
    property var acting: null      // the row (an app, a window or a file)
    property var actingBack: null  // { mode, text, index }: what to go back to
    function rowName(r: var): string { return r.kind === "app" ? r.e.name : r.kind === "win" ? r.w.name : r.kind === "file" ? r.f.name : ""; }
    function appWindows(e: var): list<var> {
        return Hyprland.toplevels.values.filter(t => Apps.entryFor(t.wayland?.appId ?? t.lastIpcObject?.class ?? "")?.id === e.id);
    }
    function rowInfo(r: var): var {
        return { kind: r.kind, name: rowName(r), running: r.kind === "app" ? appWindows(r.e).length : 0, ws: r.kind === "win" ? (r.w.t.workspace?.id ?? 0) : 0 };
    }
    function enterActions(): bool {
        const r = results[current];
        if (acting || !r || !RowActions.hasActions(r.kind)) return false;
        actingBack = { mode: mode, text: field.text, index: current };
        acting = r;
        mode = "";
        field.text = "";
        return true;
    }
    function leaveActions(): void {
        if (!acting) return;
        const back = actingBack;
        acting = null;
        actingBack = null;
        mode = back.mode;
        field.text = back.text;
        fieldText = back.text;
        Qt.callLater(() => { current = Math.min(back.index, Math.max(0, results.length - 1)); });
    }
    function winAddr(t: var): string { const a = String(t.address); return a.startsWith("0x") ? a : "0x" + a; }
    function dispatch(lua: string): void { Quickshell.execDetached(["hyprctl", "dispatch", lua]); }
    function runRowAction(a: var, r: var): void {
        const here = Hyprland.focusedWorkspace?.id ?? 1;
        if (r.kind === "app") {
            if (a.act === "open") Apps.launch(r.e);
            else if (a.act === "open_on") Apps.launchOn(r.e, a.ws);
            else if (a.act === "open_empty") {
                const busy = Hyprland.toplevels.values.map(t => t.workspace?.id);
                let n = 1;
                while (n < 10 && busy.includes(n)) n++;
                Apps.launchOn(r.e, n);
                dispatch(`hl.dsp.focus({ workspace = "${n}" })`);
            }
            else if (a.act === "quit") for (const t of appWindows(r.e)) dispatch(`hl.dsp.window.close({ window = "address:${winAddr(t)}" })`);
            else if (a.act === "uninstall") {
                const name = r.e.name;
                Packages.ownerOf(r.e.id, o => { o.title = name; root.say("delete", Packages.remove(o), "info"); });
            }
        } else if (r.kind === "win") {
            const w = `window = "address:${winAddr(r.w.t)}"`;
            if (a.act === "bring") { dispatch(`hl.dsp.window.move({ workspace = "${here}", ${w}, follow = false })`); dispatch(`hl.dsp.focus({ ${w} })`); }
            else if (a.act === "move_to") dispatch(`hl.dsp.window.move({ workspace = "${a.ws}", ${w}, follow = false })`);
            else if (a.act === "close") dispatch(`hl.dsp.window.close({ ${w} })`);
        } else if (r.kind === "file") {
            if (a.act === "open") Quickshell.execDetached(["xdg-open", r.f.path]);
            else if (a.act === "folder") Quickshell.execDetached(["xdg-open", r.f.isDir ? r.f.path : r.f.path.slice(0, r.f.path.lastIndexOf("/")) || "/"]);
            else if (a.act === "copy_path") Quickshell.execDetached(["wl-copy", r.f.path]);
        }
    }
    readonly property var modes: ({
        "?": { label: "Ask Claude", hint: "Ask anything" },
        ">": { label: "Actions", hint: "Lock, timer, Wi-Fi, screenshot…" },
        ";": { label: "Clipboard", hint: "Search what you copied" },
        ":": { label: "Emoji", hint: "Search emoji and symbols" },
        "/": { label: "Files", hint: "Search your home folder" },
        "#": { label: "Keys", hint: "Search bead's keyboard shortcuts" },
        "+": { label: "Install", hint: "Search the repos, Flathub and the AUR" }
    })
    // ── "+": bead's installer (Packages): results from all three, best first ──
    readonly property bool installing: query.startsWith("+")
    onQueryChanged: if (installing) Packages.search(query.slice(1)); else if (Packages.query) Packages.search("")
    function pkgRow(r: var): var {
        const src = r.source === "repo" ? "Repo \u00b7 " + r.repo : r.source === "flathub" ? "Flathub" : "AUR \u00b7 unreviewed";
        const bits = [src, r.version, r.source === "repo" ? Pkgs.size(r.size) : "", r.source === "aur" ? r.votes + " votes" : "",
            r.outdated ? "out of date" : "", r.installed ? "installed" : ""].filter(Boolean);
        return { kind: "action", a: { id: "pkg:" + r.source + ":" + r.name, pkg: r, glyph: r.installed ? "check_circle" : r.source === "repo" ? "inventory_2" : r.source === "flathub" ? "deployed_code" : "construction",
            title: (r.title || r.name) + (r.desc ? "  \u00b7  " + r.desc : ""), sub: bits.join(" \u00b7 ") + (r.source === "aur" && !r.installed ? " \u00b7 Enter twice: builds it from the AUR" : ""),
            confirm: r.source === "aur" && !r.installed } };
    }
    // ── "#": the keys sheet (keys.js; `bead keys`, or type "keys") ──
    readonly property bool keying: query.startsWith("#")
    property var keyList: []
    FileView {
        path: Quickshell.shellPath("data/keys.json")
        onLoaded: root.keyList = KeySheet.parse(text())
    }
    function absorb(text: string): void {
        if (!acting && !mode && text.length && modes[text[0]]) {
            mode = text[0];
            field.text = text.slice(1).replace(/^ +/, ""); // comes straight back here
            return;
        }
        fieldText = text;
    }
    property int current: 0
    property string confirming: ""   // action id waiting for a second Enter
    property string pinNote: ""      // why the selected clip can't be pinned, for a moment
    Timer { id: pinNoteTimer; interval: 2400; onTriggered: root.pinNote = "" }

    function reset(seed: string): void {
        Ask.clear();
        acting = null;
        actingBack = null;
        mode = "";
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
        if (Demo.on) return []; // their titles are yours: none in screenshots
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

    // ── files: "/" searches your home with fd (hidden and junk folders skipped) ──
    readonly property bool filing: query.startsWith("/")
    readonly property string fileQ: filing ? query.slice(1).trim() : ""
    property list<var> files: []
    property bool fileBusy: false
    onFileQChanged: { if (fileQ.length >= 2) fileTimer.restart(); else { files = []; fd.running = false; } }
    Timer {
        id: fileTimer
        interval: 160
        onTriggered: {
            fd.running = false;
            fd.command = ["fd", "--ignore-case", "--max-results", "40", "--max-depth", "8",
                "--exclude", "node_modules", "--exclude", ".git", "--exclude", "go", "--exclude", "target",
                "--", root.fileQ.replace(/\s+/g, ".*"), Quickshell.env("HOME")];
            root.fileBusy = true;
            fd.running = true;
        }
    }
    Process {
        id: fd
        stdout: StdioCollector {
            onStreamFinished: {
                const home = Quickshell.env("HOME");
                root.files = text.split("\n").filter(l => l).map(l => {
                    const dir = l.endsWith("/");
                    const path = dir ? l.slice(0, -1) : l;
                    const i = path.lastIndexOf("/");
                    return { path: path, name: path.slice(i + 1), dir: path.slice(0, i).replace(home, "~"), isDir: dir };
                })
                // shallower first: what you mean is rarely ten folders down
                .sort((a, b) => a.path.split("/").length - b.path.split("/").length);
                root.fileBusy = false;
            }
        }
    }
    function fileGlyph(f: var): string {
        if (f.isDir) return "folder";
        const x = (f.name.split(".").pop() ?? "").toLowerCase();
        if (["png", "jpg", "jpeg", "gif", "webp", "svg", "avif"].includes(x)) return "image";
        if (["mp4", "mkv", "webm", "mov"].includes(x)) return "movie";
        if (["mp3", "flac", "ogg", "wav", "m4a"].includes(x)) return "music_note";
        if (["pdf"].includes(x)) return "picture_as_pdf";
        if (["zip", "tar", "gz", "xz", "zst", "7z"].includes(x)) return "folder_zip";
        if (["qml", "js", "ts", "py", "go", "rs", "c", "h", "cpp", "lua", "sh", "json", "toml", "yaml", "yml"].includes(x)) return "code";
        return "description";
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
    // your voice commands (services/Voice.qml), to run without saying them;
    // not the ones that need words after them
    readonly property list<var> yours: Voice.custom.filter(c => !c.text).map(c => ({ id: "voice:" + c.name,
        title: (c.phrases[0] ?? c.name.replace(/_/g, " ")).replace(/^./, m => m.toUpperCase()),
        sub: "Your command \u00b7 " + c.steps.length + (c.steps.length === 1 ? " step" : " steps"), glyph: "bolt" }))
    readonly property list<var> actions: [
        ...yours,
        ...timeActions,
        ...Session.actions,
        { id: "dnd", title: Notifs.dnd ? "Turn off Do Not Disturb" : "Do Not Disturb", sub: "Hold notification popups", glyph: Notifs.dnd ? "notifications_active" : "notifications_off" },
        { id: "clear", title: "Clear notifications", sub: Notifs.entries.length + " in history", glyph: "clear_all" },
        { id: "island", title: "Hide / show the island", sub: "Same as Super+I", glyph: "visibility" },
        { id: "settings", title: "Settings", sub: "Wi-Fi, sound, displays, colours, idle, keys…", glyph: "settings" },
        { id: "walls", title: "Wallpapers", sub: "Pick one on the dashboard; the colours follow", glyph: "wallpaper" },
        { id: "wallshuffle", title: "Shuffle wallpaper", sub: "Another one at random", glyph: "shuffle" },
        { id: "awake", title: Idle.keepAwake ? "Stop keeping awake" : "Keep awake", sub: "Don't lock, blank or sleep when idle", glyph: "coffee" },
        // focus modes: each one, and off
        ...Focus.modes.map(m => ({ id: "focus:" + m.id, title: m.id === Focus.active ? "Leave " + m.name + " mode" : m.name + " mode", sub: "Focus · " + Focus.summary(m), glyph: m.icon })),
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
        { id: "vault", title: "Open the vault", sub: "Obsidian · brain", glyph: "book_2" },
        { id: "store", title: "App Store", sub: "Find and install apps", glyph: "storefront" }
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
        if (String(a.id).startsWith("voice:")) { Voice.decided({ action: a.id.slice(6), text: "" }, ""); return; }
        // installs show on the island's update card, the AUR included (no terminal)
        if (a.pkg) {
            if (a.pkg.installed) { Store.openApp({ name: a.pkg.name, source: a.pkg.source }); return; }
            if (!Updates.installApp({ title: a.pkg.title || a.pkg.name, name: a.pkg.name, source: a.pkg.source, icon: Quickshell.iconPath(a.pkg.name, true) }))
                root.say("hourglass_top", "Busy: another install or update is running", "info");
            return;
        }
        if (a.id === "pkg:none") return;
        if (String(a.id).startsWith("focus:")) { Focus.toggle(a.id.slice(6)); return; }
        switch (a.id) {
        case "dnd": Notifs.dnd = !Notifs.dnd; break;
        case "clear": Notifs.clear(); break;
        case "island": islandToggle.running = true; break;
        case "stopwatch": Countdown.startStopwatch(); break;
        case "awake": Idle.keepAwake = !Idle.keepAwake; break;
        case "walls": Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "dashboard", "tab", "5"]); break;
        case "settings": SettingsApp.show(""); break;
        case "store": Store.show(a.q ?? ""); break;
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
        if (acting) return RowActions.actionsFor(rowInfo(acting), fieldText, { here: Hyprland.focusedWorkspace?.id ?? 0 })
            .map(a => ({ kind: "action", a: Object.assign({}, a, { id: "row:" + a.id, act: a.id }) }));
        const q = query.trim();
        if (clipping) {
            const words = q.slice(1).trim().toLowerCase().split(/\s+/).filter(w => w);
            // secrets match only by kind, so typing part of one doesn't find it
            const hay = e => e.image ? `image ${e.image.fmt} ${e.image.w}x${e.image.h} ${e.image.w}×${e.image.h}` : e.type === "secret" ? "secret hidden" : e.text.toLowerCase();
            const hit = e => !words.length || words.every(w => hay(e).includes(w));
            return Clipboard.list.filter(hit).slice(0, 80).map(e => ({ kind: "clip", c: e }));
        }
        if (emojiing) return Emoji.search(q.slice(1)).map(e => ({ kind: "emoji", m: e }));
        if (keying) return KeySheet.find(keyList, q.slice(1)).map(k => ({ kind: "key", k: k }));
        if (installing) {
            const sq = q.slice(1).trim();
            const rows = Packages.results.map(r => root.pkgRow(r));
            if (sq.length >= 2) rows.unshift({ kind: "action", a: { id: "store", q: sq, title: "Open \u201c" + sq + "\u201d in the App Store", sub: "One result per app, with picks for what you need", glyph: "storefront" } });
            if (!rows.length && q.slice(1).trim().length >= 2)
                return [{ kind: "action", a: { id: "pkg:none", glyph: Packages.searching ? "hourglass_top" : "search_off",
                    title: Packages.searching ? "Searching the repos, Flathub and the AUR\u2026" : "Nothing called \u201c" + q.slice(1).trim() + "\u201d", sub: "" } }];
            return rows;
        }
        if (filing) return files.map(f => ({ kind: "file", f: f }));
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
        // "install obs": the App Store, searched
        const iq = StoreJs.launcherQuery(q);
        if (iq) out.push({ kind: "action", a: { id: "store", q: iq, title: "Find \u201c" + iq + "\u201d in the App Store", sub: "Apps from the repos, Flathub and the AUR", glyph: "storefront" } });
        if (KeySheet.asksFor(q)) out.push({ kind: "action", a: { id: "keysmenu", title: "Keyboard shortcuts", sub: "bead's keys, searchable", glyph: "keyboard" } });
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
        else if (r.kind === "file") {
            close();
            if (copyOnly) Quickshell.execDetached(["wl-copy", r.f.path]);
            else Quickshell.execDetached(["xdg-open", r.f.path]);
        }
        else if (r.kind === "calc") { Quickshell.execDetached(["wl-copy", calc.result]); close(); }
        else if (r.kind === "key") return; // a list to read
        else {
            if (r.a.id === "timermenu") { root.mode = ">"; field.text = "timer "; return; } // stay open: pick a length
            if (r.a.id === "keysmenu") { root.mode = "#"; field.text = ""; return; }
            if (r.a.act) {
                if ((r.a.act === "open_on" || r.a.act === "move_to") && !r.a.ws) return; // wants a number first
                if (r.a.confirm && confirming !== r.a.id) { current = i; confirming = r.a.id; return; }
                const on = acting;
                close();
                runRowAction(r.a, on);
                return;
            }
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
            name: root.acting ? "bolt" : root.asking ? "auto_awesome" : root.clipping ? "content_paste" : root.emojiing ? "mood" : root.filing ? "folder_open" : root.keying ? "keyboard" : root.installing ? "download" : root.query.trim().startsWith(">") ? "bolt" : root.mathy ? "calculate" : "search"
            color: root.asking ? Theme.tone("action") : Theme.subtext
            size: 20
        }
        Rectangle {
            id: modeChip
            x: 40
            anchors.verticalCenter: parent.verticalCenter
            height: 26
            radius: 13
            readonly property var m: root.acting ? { label: root.rowName(root.acting) } : root.modes[root.mode] ?? null
            property string shownLabel: ""
            onMChanged: if (m) shownLabel = m.label // keeps its text while it fades out
            width: m ? Math.min(chipLabel.implicitWidth + 22, 220) : 0
            opacity: m ? 1 : 0
            visible: width > 1
            clip: true
            color: Qt.alpha(Theme.tone("action"), 0.18)
            Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 140 } }
            Text {
                id: chipLabel
                anchors.centerIn: parent
                width: Math.min(implicitWidth, 198)
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: Theme.body
                font.weight: Font.Medium
                color: Theme.tone("action")
                text: modeChip.shownLabel
            }
            TapHandler { onTapped: { if (root.acting) root.leaveActions(); else root.mode = ""; field.forceActiveFocus(); } }
        }
        TextInput {
            TextMenu {}   // right-click: cut, copy, paste
            id: field
            x: modeChip.width > 1 ? modeChip.x + modeChip.width + 10 : 44
            width: parent.width - x - 16
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.font
            font.pixelSize: Theme.title
            color: Theme.text
            selectionColor: Qt.alpha(Theme.tone("action"), 0.4)
            clip: true
            onTextChanged: root.absorb(text)
            Keys.onPressed: e => {
                const ctrl = e.modifiers & Qt.ControlModifier;
                // Backspace at the very start leaves the mode
                if (e.key === Qt.Key_Backspace && root.mode && field.cursorPosition === 0 && !field.selectedText) {
                    root.mode = ""; e.accepted = true; return;
                }
                // a row's actions: Tab opens them; Shift+Tab, Esc or Backspace on nothing goes back
                const backtab = e.key === Qt.Key_Backtab || e.key === Qt.Key_Tab && (e.modifiers & Qt.ShiftModifier);
                if (root.acting && (backtab || e.key === Qt.Key_Escape || e.key === Qt.Key_Backspace && !field.text)) {
                    root.leaveActions(); e.accepted = true; return;
                }
                if (e.key === Qt.Key_Tab && !backtab && !root.acting && root.enterActions()) { e.accepted = true; return; }
                if (root.answering) { // the answer is showing: arrows scroll it, Enter asks again
                    if (e.key === Qt.Key_Down || e.key === Qt.Key_Up) { answer.scroll(e.key === Qt.Key_Down ? 60 : -60); e.accepted = true; return; }
                    if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                        if (root.askText && (root.askText !== Ask.question || Ask.st === "error")) Ask.ask(root.askText);
                        e.accepted = true;
                        return;
                    }
                }
                if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab && !backtab || ctrl && (e.key === Qt.Key_J || e.key === Qt.Key_N)) { root.move(1); e.accepted = true; }
                else if (e.key === Qt.Key_Up || backtab || ctrl && (e.key === Qt.Key_K || e.key === Qt.Key_P)) { root.move(-1); e.accepted = true; }
                else if (e.key === Qt.Key_PageDown) { root.move(Math.min(root.maxRows, root.results.length - 1 - root.current)); e.accepted = true; }
                else if (e.key === Qt.Key_PageUp) { root.move(-Math.min(root.maxRows, root.current)); e.accepted = true; }
                else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { root.activate(root.current, !!(e.modifiers & Qt.ShiftModifier)); e.accepted = true; }
                else if (e.key === Qt.Key_Delete && (e.modifiers & Qt.ShiftModifier) && root.results[root.current]?.kind === "clip") {
                    Clipboard.remove(root.results[root.current].c); e.accepted = true;
                }
                else if (ctrl && e.key === Qt.Key_S && root.results[root.current]?.kind === "clip") { // pin it, or unpin
                    const c = root.results[root.current].c;
                    if (c.pinned) Clipboard.unpin(c); else root.pinNote = Clipboard.pin(c);
                    if (root.pinNote) pinNoteTimer.restart();
                    e.accepted = true;
                }
                else if (e.key === Qt.Key_Escape) { root.close(); e.accepted = true; }
            }
            // the placeholder: in a mode, what it searches; otherwise "Search apps"
            // and, faintly after it, one of the other things to type, a new one
            // every few seconds (all of them at once was a wall of symbols)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                visible: !field.text && !field.preeditText
                spacing: 14
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: Theme.title
                    text: root.acting ? "Pick one, or type a workspace number" : root.modes[root.mode]?.hint ?? "Search apps"
                }
                Row {
                    id: tip
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.acting && !root.mode
                    spacing: 6
                    readonly property var tips: [["=", "maths"], ["+", "install apps"], [";", "clipboard"], [">", "actions"], ["/", "files"], [":", "emoji"], ["#", "keys"], ["?", "ask Claude"]]
                    property int at: 0
                    readonly property var cur: tips[at % tips.length]
                    Timer {
                        interval: 3200
                        repeat: true
                        running: tip.visible && root.visible
                        onTriggered: tipSwap.restart()
                    }
                    SequentialAnimation {
                        id: tipSwap
                        NumberAnimation { target: tip; property: "opacity"; to: 0; duration: 180; easing.type: Easing.InQuad }
                        ScriptAction { script: tip.at++ }
                        NumberAnimation { target: tip; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutQuad }
                    }
                    Key { text: tip.cur[0]; anchors.verticalCenter: parent.verticalCenter }
                    Label { text: tip.cur[1]; font.pixelSize: Theme.body; opacity: 0.6; anchors.verticalCenter: parent.verticalCenter }
                }
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
                    font.pixelSize: Theme.heading
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
                            : row.modelData.kind === "ask" ? "auto_awesome" : row.modelData.kind === "clip" ? (row.modelData.c.pinned ? "keep" : root.clipGlyph(row.modelData.c.type))
                            : row.modelData.kind === "win" ? "select_window"
                            : row.modelData.kind === "key" ? "keyboard"
                            : row.modelData.kind === "file" ? root.fileGlyph(row.modelData.f) : "apps"
                    }
                }
            }
            Row { // the selected row says what Tab does
                id: tabHint
                visible: row.sel && !root.acting && RowActions.hasActions(row.modelData.kind)
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Key { text: "Tab"; anchors.verticalCenter: parent.verticalCenter }
                Label { text: "more"; font.pixelSize: Theme.caption; anchors.verticalCenter: parent.verticalCenter }
            }
            Row { // a shortcut's keys, as key caps
                id: keyCaps
                visible: row.modelData.kind === "key"
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Repeater {
                    model: row.modelData.kind === "key" ? KeySheet.caps(row.modelData.k.keys) : []
                    Key { required property string modelData; text: modelData }
                }
            }
            Column {
                x: 52
                width: parent.width - 52 - 12 - (tabHint.visible ? tabHint.width + 10 : 0) - (keyCaps.visible ? keyCaps.width + 10 : 0)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    font.family: Theme.font
                    font.pixelSize: Theme.title
                    font.weight: row.sel ? Font.Medium : Font.Medium
                    color: row.confirm ? Theme.tone("error") : Theme.text
                    text: row.modelData.kind === "app" ? row.modelData.e.name
                        : row.modelData.kind === "win" ? row.modelData.w.title
                        : row.modelData.kind === "calc" ? calc.result
                        : row.modelData.kind === "ask" ? row.modelData.q
                        : row.modelData.kind === "clip" ? (row.modelData.c.image ? "Image · " + row.modelData.c.image.w + "×" + row.modelData.c.image.h
                            : row.modelData.c.type === "secret" ? "•".repeat(12) + "  hidden"
                            : row.modelData.c.text.replace(/\s+/g, " ").trim())
                        : row.modelData.kind === "emoji" ? row.modelData.m.name
                        : row.modelData.kind === "file" ? row.modelData.f.name
                        : row.modelData.kind === "key" ? KeySheet.title(row.modelData.k.what)
                        : row.confirm ? "Press Enter again to " + row.a.title.toLowerCase() : row.a.title
                }
                Label {
                    width: parent.width
                    elide: Text.ElideRight
                    font.pixelSize: Theme.caption
                    visible: text !== ""
                    text: row.modelData.kind === "app" ? (row.modelData.e.comment || row.modelData.e.genericName || "")
                        : row.modelData.kind === "win" ? "Switch to " + row.modelData.w.name + (row.modelData.w.ws ? "  ·  workspace " + row.modelData.w.ws : "")
                        : row.modelData.kind === "calc" ? "= " + root.expr + "  ·  Enter copies"
                        : row.modelData.kind === "ask" ? "Ask Claude  ·  Enter"
                        : row.modelData.kind === "clip" ? (row.sel ? (root.pinNote || (row.modelData.c.pinned ? "Pinned  ·  Enter pastes  ·  Ctrl+S unpins" : "Enter pastes  ·  Shift+Enter copies  ·  Ctrl+S pins  ·  Shift+Del forgets"))
                            : row.modelData.c.pinned ? "Pinned" : root.clipHint(row.modelData.c))
                        : row.modelData.kind === "emoji" ? (row.sel ? "Enter types it  ·  Shift+Enter copies" : "")
                        : row.modelData.kind === "file" ? (row.sel ? "Enter opens  ·  Shift+Enter copies the path" : row.modelData.f.dir)
                        : row.modelData.kind === "key" ? row.modelData.k.group
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
            Label { anchors.horizontalCenter: parent.horizontalCenter; font.pixelSize: Theme.caption; text: "Enter still pastes it  ·  Shift+Del forgets it" }
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
                font.pixelSize: Theme.title
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
            font.pixelSize: Theme.caption
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
        Label { text: root.clipping ? (Clipboard.loading ? "Loading…" : Clipboard.list.length ? "No matches" : "Nothing on the clipboard history") : root.asking ? "Type a question for Claude" : root.filing ? (root.fileQ.length < 2 ? "Type a file or folder name" : root.fileBusy ? "Searching…" : "No files found") : root.keying ? "No key does that" : root.mathy ? "Working it out…" : "Nothing found" }
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
                    TextMenu {}   // right-click: cut, copy, paste
                    width: parent.width
                    visible: !!Ask.answer
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.RichText
                    font.family: Theme.font
                    font.pixelSize: Theme.body
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
                        font.pixelSize: Theme.caption
                        text: "Edit the question and press Enter for a follow-up"
                    }
                }
            }
        }
    }
}
