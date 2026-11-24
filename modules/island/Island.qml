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
// It lives on one monitor ($BEAD_ISLAND_SCREEN or Settings, default the first screen). Hidden (IPC
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
        // the media card without hovering (a keybind, or checking how it looks)
        function media(): void { root.mediaPinned = !root.mediaPinned; }
    }
    property bool mediaPinned: false
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
    // false until the first check: a freshly started island stays tucked
    // rather than popping out for a moment over a window that covers it
    property bool settled: false
    function checkCovered(): void {
        settled = true;
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
    Timer { interval: 1500; repeat: true; running: true; triggeredOnStart: true; onTriggered: geometryTimer.restart() }

    // ── launcher ──
    property bool launcherOpen: false
    // workspace overview (Super+Tab); opening one closes the other
    property bool overviewOpen: false
    onOverviewOpenChanged: if (overviewOpen) launcherOpen = false
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

    // bound in Hyprland as hl.dsp.global("bead:overview") on Super+Tab
    // push-to-talk dictation: hold, speak, release (Super+A)
    GlobalShortcut {
        appid: "bead"
        name: "dictate"
        description: "Hold to dictate into the focused field"
        onPressed: Dictation.start()
        onReleased: Dictation.stop()
    }
    Connections {
        target: Dictation
        function onFailed(why) { root.toast("mic_off", why, "error", 3500); }
    }
    // voice commands: hold, say what you want, release (Super+Space)
    GlobalShortcut {
        appid: "bead"
        name: "voice"
        description: "Hold to give a voice command"
        onPressed: Voice.start()
        onReleased: Voice.stop()
    }
    Connections {
        target: Voice
        function onFailed(why) { root.toast("mic_off", why, "error", 3500); }
        function onDecided(a, heard) { root.runVoice(a, heard); }
    }
    // "1 hour and thirty seconds", "an hour and a half", "90 seconds" -> ms (0 if none)
    function spokenDuration(text: string): real {
        const words = { a: 1, an: 1, one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
            eleven: 11, twelve: 12, fifteen: 15, twenty: 20, thirty: 30, forty: 40, "forty-five": 45, fifty: 50, sixty: 60, ninety: 90 };
        const unit = { h: 3600, m: 60, s: 1 };
        const t = text.toLowerCase().replace(/-(?!five)/g, " ")
            .replace(/\bhalf (an|a) hour\b/g, "30 minutes").replace(/\bhalf (a|an) minute\b/g, "30 seconds");
        let total = 0;
        const re = /(\d+(?:\.\d+)?|[a-z-]+)\s+(hour|hr|minute|min|second|sec)s?\b(\s+and\s+a\s+half)?/g;
        let m;
        while ((m = re.exec(t)) !== null) {
            const n = /^\d/.test(m[1]) ? parseFloat(m[1]) : words[m[1]];
            if (n === undefined) continue;
            const u = unit[m[2][0]];
            total += (n + (m[3] ? 0.5 : 0)) * u;
        }
        return Math.round(total) * 1000;
    }
    // run what the voice model picked; each says what it did on the island
    function runVoice(a: var, heard: string): void {
        const say = (icon, text) => root.toast(icon, text, "action", 2200);
        const dispatch = lua => Quickshell.execDetached(["hyprctl", "dispatch", lua]);
        switch (a.action) {
        case "timer": {
            // the words themselves first: small models mix up units
            const ms = root.spokenDuration(heard) || (((a.hours ?? 0) * 60 + (a.minutes ?? 0)) * 60 + (a.seconds ?? 0)) * 1000;
            if (!(ms > 0)) break;
            Countdown.startTimer(ms, "");
            return say("timer", "Timer \u00b7 " + Countdown.fmtTotal(ms));
        }
        case "stopwatch": Countdown.startStopwatch(); return say("timer", "Stopwatch started");
        case "stop_timers": Countdown.stopAll(); return say("timer_off", "Timers stopped");
        case "play_pause": if (root.player?.canTogglePlaying) { root.player.togglePlaying(); return say(root.player.isPlaying ? "pause" : "play_arrow", root.player.isPlaying ? "Paused" : "Playing"); } break;
        case "next_track": if (root.player?.canGoNext) { root.player.next(); return say("skip_next", "Next track"); } break;
        case "previous_track": if (root.player?.canGoPrevious) { root.player.previous(); return say("skip_previous", "Previous track"); } break;
        case "volume_set": if (a.level === undefined) break; Audio.setVolume(a.level / 100); root.flash("volume", ""); return;
        case "volume_up": Audio.setVolume(Audio.volume + 0.1); root.flash("volume", ""); return;
        case "volume_down": Audio.setVolume(Audio.volume - 0.1); root.flash("volume", ""); return;
        case "mute": Audio.toggleMute(); root.flash("volume", ""); return;
        case "mic_mute": Audio.toggleMicMute(); root.flash("mic", ""); return;
        case "open_app": {
            // small models sometimes leave the place in the name ("x on window 5"):
            // take it off, and read the workspace and "close the rest" from the
            // words too in case the model missed them
            const words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"];
            const place = /\s+(?:on|in|to|at)\s+(?:the\s+)?(?:workspace|window|desktop|screen)\s+(\w+).*$/i;
            const name = (a.app ?? "").replace(place, "").trim();
            const m = heard.match(/(?:workspace|window|desktop|screen)\s+(?:number\s+)?(\w+)/i);
            const spoken = m ? (parseInt(m[1]) || words.indexOf(m[1].toLowerCase())) : -1;
            const ws = a.workspace > 0 ? a.workspace : spoken > 0 ? spoken : 0;
            const alone = a.alone === true || /close\s+(?:all\s+)?(?:the\s+)?(?:other|rest|everything)/i.test(heard);
            const e = name ? Apps.search(name)[0] : null;
            if (!e) return root.toast("search_off", "No app called \u201c" + (name || heard) + "\u201d", "error", 2600);
            if (!ws) { Apps.launch(e); return say("open_in_new", "Opening " + e.name); }
            let closed = 0;
            if (alone) for (const t of Hyprland.toplevels.values) {
                if (t.workspace?.id !== ws) continue;
                const ad = t.address.startsWith("0x") ? t.address : "0x" + t.address;
                dispatch(`hl.dsp.window.close({ window = "address:${ad}" })`);
                closed++;
            }
            Apps.launchOn(e, ws);
            dispatch(`hl.dsp.focus({ workspace = "${ws}" })`);
            return say("open_in_new", "Opening " + e.name + " on " + ws + (closed ? " \u00b7 closed " + closed : ""));
        }
        case "workspace": if (!(a.workspace > 0)) break; dispatch(`hl.dsp.focus({ workspace = "${a.workspace}" })`); return;
        case "overview": root.overviewOpen = true; return;
        case "wallpaper": Wallpaper.random(""); return say("wallpaper", "New wallpaper");
        case "dnd": Notifs.dnd = !Notifs.dnd; return say(Notifs.dnd ? "do_not_disturb_on" : "notifications", Notifs.dnd ? "Do not disturb on" : "Do not disturb off");
        case "screenshot_area": Capture.shot("area"); return;
        case "screenshot_screen": Capture.shot("screen"); return;
        case "ask": {
            const q = a.text || heard;
            root.launcherSeed = "?" + q;
            if (root.launcherOpen) root.launcherSeedChanged();
            root.launcherOpen = true;
            Ask.ask(q);
            return;
        }
        }
        root.toast("help", "Not a command: \u201c" + heard + "\u201d", "info", 2800);
    }
    GlobalShortcut {
        appid: "bead"
        name: "overview"
        description: "Workspace overview"
        onPressed: root.overviewOpen = !root.overviewOpen
    }
    IpcHandler {
        target: "overview"
        function toggle(): void { root.overviewOpen = !root.overviewOpen; }
        function open(): void { root.overviewOpen = true; }
        function close(): void { root.overviewOpen = false; }
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
        target: Osd // batteries, Bluetooth, Do Not Disturb, keyboard layout
        function onToast(icon: string, text: string, tone: string, ms: int) { root.toast(icon, text, tone, ms); }
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
            readonly property bool tucked: root.hidden || root.fullscreen || root.covered || !root.settled
            readonly property string state: Passkey.active ? "passkey" : Voice.active ? "voice" : root.overviewOpen ? "overview" : root.launcherOpen ? "launcher" : open ? "open" : mediaCard || (root.mediaPinned && root.playing) ? "media" : showsActivity ? "activity" : tucked && !Dictation.active && !Voice.active ? "tucked" : "rest"
            onStateChanged: {
                // see tuckW: keep a small state's width; a big one (dashboard,
                // launcher…) tucks at the resting width, not as a wide strip
                if (state === "tucked") tuckW = prevState === "activity" || prevState === "rest" ? sw.value : restW;
                prevState = state;
                if (state === "launcher") { launcherView.reset(root.launcherSeed); root.launcherSeed = ""; grabTimer.restart(); }
                else if (state === "overview") { overviewView.reset(); grabTimer.restart(); }
                else { grabTimer.stop(); grabbing = false; }
                if (state === "passkey" || state === "launcher" || state === "overview") focusTimer.restart();
            }
            // the layer gets keyboard focus a moment after it asks for it
            Timer {
                id: focusTimer
                interval: 120
                onTriggered: win.state === "passkey" ? passkeyView.focusField() : win.state === "overview" ? overviewView.focusField() : launcherView.focusField()
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
            Timer { id: grabTimer; interval: 250; onTriggered: win.grabbing = win.state === "launcher" || win.state === "overview" }
            HyprlandFocusGrab {
                windows: [win]
                active: win.grabbing
                onCleared: if (win.grabbing) { win.grabbing = false; root.launcherOpen = false; root.overviewOpen = false; }
            }
            readonly property bool showMedia: root.playing && (root.peek || hovered)
            // clock ↔ track: fade the old one out, swap at the low point, let the
            // pill reshape, then fade the new one in (a cut used to jump, and the
            // wider row spilled past the pill while it caught up)
            property bool mediaShown: showMedia
            property real mediaSwapOp: 1
            onShowMediaChanged: { mediaSwap.stop(); mediaSwap.start(); }
            SequentialAnimation {
                id: mediaSwap
                NumberAnimation { target: win; property: "mediaSwapOp"; to: 0; duration: 110; easing.type: Easing.OutCubic }
                ScriptAction { script: win.mediaShown = win.showMedia }
                PauseAnimation { duration: 140 }
                NumberAnimation { target: win; property: "mediaSwapOp"; to: 1; duration: 220; easing.type: Easing.OutCubic }
            }
            onOpenChanged: root.openCount += open ? 1 : -1

            // hover a moment before it grows (passing by doesn't open it)
            // while something plays, hover first grows the media card; staying on
            // (or clicking it) goes on to the dashboard
            property bool mediaCard: false
            Timer {
                id: openTimer
                interval: 220
                onTriggered: {
                    if (root.playing) win.mediaCard = true; // the card opens the dashboard itself
                    else win.expanded = true;
                }
            }
            Timer {
                id: leaveTimer
                interval: 300
                onTriggered: {
                    win.hovered = false;
                    if (win.expanded || win.mediaCard) win.closedAt = Date.now();
                    win.expanded = false;
                    win.mediaCard = false;
                    if (!activityTimer.running && win.showsActivity) root.activity = "";
                }
            }
            // one state for the edge strip and the island together: moving from
            // one to the other must not count as leaving
            readonly property bool pointerIn: edgeHover.hovered || boxHover.hovered
            onPointerInChanged: pointerIn ? enterHover() : leaveHover()
            // just after it closes, crossing the top strip on the way out (or the
            // pill as it shrinks) isn't a request to open it again: that made it
            // spring back to full size before closing for real
            property real closedAt: 0
            function enterHover(): void {
                if (root.fullscreen && !open) return;
                leaveTimer.stop();
                hovered = true;
                if (!expanded && Date.now() - closedAt > 600) openTimer.restart();
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
            WlrLayershell.keyboardFocus: Passkey.asking || root.launcherOpen || root.overviewOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
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
            // tucking keeps the width it had, so it only retracts upwards (it used to
            // take the resting width and spread out on its way up)
            property real tuckW: restW
            property string prevState: "rest"
            Spring {
                id: sw
                to: win.state === "passkey" ? passkeyView.wantW : win.state === "voice" ? voiceView.wantW : win.state === "overview" ? overviewView.wantW : win.state === "launcher" ? launcherView.wantW : win.state === "open" ? win.openW : win.state === "media" ? mediaView.wantW : win.state === "activity" ? win.activityW : win.state === "tucked" ? win.tuckW : win.restW
                settleWhenShrinking: true
                duration: Motion.dur * 0.9
            }
            Spring {
                id: sh
                to: win.state === "passkey" ? passkeyView.wantH : win.state === "voice" ? voiceView.wantH : win.state === "overview" ? overviewView.wantH : win.state === "launcher" ? launcherView.wantH : win.state === "open" ? win.openH : win.state === "media" ? mediaView.wantH
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
                        enabled: !win.open && win.state !== "media" // the media card scrolls the player's volume
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
                    // waits for the dashboard to be gone, so the two never overlap
                    opacity: win.state === "rest" && dash.opacity < 0.05 ? 1 : 0
                    visible: opacity > 0.01
                    SwapFade on opacity {}

                    // live: dictation. The mic and your level while you hold the key,
                    // then pulsing dots while whisper works (click: stop / cancel)
                    Row {
                        id: voiceChip
                        visible: Dictation.active || Voice.active
                        // the command one shows a different glyph and "thinks" after transcribing
                        readonly property bool cmd: Voice.active
                        readonly property string phase: cmd ? Voice.state : Dictation.state
                        readonly property real level: cmd ? Voice.level : Dictation.level
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: voiceChip.cmd ? "graphic_eq" : "mic"
                            size: 17
                            fill: 1
                            color: Theme.tone("action")
                        }
                        Row {
                            visible: voiceChip.phase === "listening"
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Repeater {
                                model: 5
                                Rectangle {
                                    required property int index
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 3
                                    radius: 1.5
                                    color: Theme.text
                                    // the middle bars reach highest
                                    readonly property real shape: [0.55, 0.8, 1, 0.8, 0.55][index]
                                    height: 4 + 12 * Math.min(1, voiceChip.level * shape * 1.3)
                                    Behavior on height { NumberAnimation { duration: 70 } }
                                }
                            }
                        }
                        Row {
                            visible: voiceChip.phase === "transcribing" || voiceChip.phase === "thinking"
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 3
                            Repeater {
                                model: 3
                                Rectangle {
                                    id: dot
                                    required property int index
                                    width: 5; height: 5; radius: 2.5
                                    color: Theme.text
                                    opacity: 0.3
                                    SequentialAnimation on opacity {
                                        running: voiceChip.visible && voiceChip.phase !== "listening"
                                        loops: Animation.Infinite
                                        PauseAnimation { duration: dot.index * 140 }
                                        NumberAnimation { to: 1; duration: 260 }
                                        NumberAnimation { to: 0.3; duration: 260 }
                                        PauseAnimation { duration: (2 - dot.index) * 140 }
                                    }
                                }
                            }
                        }
                        TapHandler { onTapped: voiceChip.cmd ? (Voice.state === "listening" ? Voice.stop() : Voice.cancel()) : Dictation.state === "listening" ? Dictation.stop() : Dictation.cancel() }
                    }
                    // live: Discord. In a call: a deafen button, then who's
                    // there (talking lights them up). Unread DMs (never servers): the
                    // latest sender and a count; tap to go read them
                    Row {
                        visible: Discord.inCall || Discord.dmCount > 0
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Repeater { // deafen
                            model: Discord.inCall ? [
                                { on: Discord.deaf, g: Discord.deaf ? "headset_off" : "headphones", act: () => Discord.toggleDeaf() }
                            ] : []
                            Rectangle {
                                id: dBtn
                                required property var modelData
                                anchors.verticalCenter: parent?.verticalCenter
                                width: 24; height: 24; radius: 12
                                color: dBtn.modelData.on ? Qt.alpha(Theme.tone("error"), 0.22) : dHover.hovered ? Qt.alpha(Theme.text, 0.12) : "transparent"
                                Behavior on color { ColorAnimation { duration: 150 } }
                                scale: dTap.pressed ? 0.85 : 1
                                Behavior on scale { SpringAnimation { spring: 6; damping: 0.3; epsilon: 0.002 } }
                                Icon {
                                    anchors.centerIn: parent
                                    name: dBtn.modelData.g
                                    size: 16
                                    fill: 1
                                    color: dBtn.modelData.on ? Theme.tone("error") : Theme.tone("action")
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }
                                HoverHandler { id: dHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { id: dTap; onTapped: dBtn.modelData.act() }
                            }
                        }
                        // who's in the call: the first three as a small overlapping stack,
                        // "+N" for the rest. Talking lights a face's ring and pulses it in
                        // place: the width only changes when someone joins or leaves, so
                        // the island doesn't spring about while people talk
                        Item {
                            id: faces
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property int shown: Math.min(3, Discord.members.length)
                            readonly property real step: 13
                            width: shown > 0 ? 22 + (shown - 1) * step : 0
                            height: 22
                            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            Repeater {
                                model: faces.shown
                                Item {
                                    id: face
                                    required property int index
                                    readonly property var m: Discord.members[index] ?? null
                                    readonly property bool talking: !!m?.speaking
                                    x: index * faces.step
                                    z: faces.shown - index
                                    width: 22; height: 22
                                    scale: talking ? 1.12 : 1
                                    Behavior on scale { NumberAnimation { duration: talking ? 260 : 220; easing.type: talking ? Easing.OutBack : Easing.OutCubic; easing.overshoot: 2 } }
                                    // the ring: the island's colour (separates the stack), green while talking
                                    Rectangle { anchors.fill: parent; radius: 11; color: Theme.frame }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 11
                                        color: Theme.tone("success")
                                        opacity: face.talking ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 180 } }
                                    }
                                    Image {
                                        id: faceImg
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        source: face.m?.avatar ?? ""
                                        sourceSize: Qt.size(40, 40)
                                        visible: false
                                    }
                                    Rectangle { id: faceMask; anchors.fill: faceImg; radius: width / 2; visible: false; layer.enabled: true }
                                    MultiEffect { anchors.fill: faceImg; source: faceImg; maskEnabled: true; maskSource: faceMask }
                                }
                            }
                        }
                        Text { // more than three: how many more (green if one of them talks)
                            visible: Discord.members.length > 3
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: Discord.members.slice(3).some(m => m.speaking) ? Theme.tone("success") : Theme.subtext
                            Behavior on color { ColorAnimation { duration: 180 } }
                            text: "+" + (Discord.members.length - 3)
                        }
                        // unread DMs: the latest sender's face with the count on it
                        Item {
                            id: dmChip
                            visible: Discord.dmCount > 0
                            anchors.verticalCenter: parent.verticalCenter
                            width: dmRow.width
                            height: 24
                            Row {
                                id: dmRow
                                spacing: 5
                                anchors.verticalCenter: parent.verticalCenter
                                Item {
                                    width: 22; height: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    Image {
                                        id: dmImg
                                        anchors.fill: parent
                                        source: Discord.dms[0]?.avatar ?? ""
                                        sourceSize: Qt.size(40, 40)
                                        visible: false
                                    }
                                    Rectangle { id: dmMask; anchors.fill: parent; radius: 11; visible: false; layer.enabled: true }
                                    MultiEffect { anchors.fill: parent; source: dmImg; maskEnabled: true; maskSource: dmMask; visible: dmImg.status === Image.Ready }
                                    Icon { anchors.centerIn: parent; visible: dmImg.status !== Image.Ready; name: "chat_bubble"; size: 15; fill: 1; color: Theme.tone("action") }
                                }
                                Rectangle { // the count: pops when it goes up
                                    id: dmBadge
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(18, dmNum.implicitWidth + 10)
                                    height: 18
                                    radius: 9
                                    color: Theme.tone("error")
                                    Text {
                                        id: dmNum
                                        anchors.centerIn: parent
                                        font.family: Theme.font
                                        font.pixelSize: 11
                                        font.weight: Font.Bold
                                        font.features: { "tnum": 1 }
                                        color: "white"
                                        text: Discord.dmCount > 99 ? "99+" : Discord.dmCount
                                    }
                                    Connections {
                                        target: Discord
                                        function onDmArrived(): void { dmPop.restart(); }
                                    }
                                    SequentialAnimation {
                                        id: dmPop
                                        NumberAnimation { target: dmBadge; property: "scale"; to: 1.35; duration: 120; easing.type: Easing.OutQuad }
                                        NumberAnimation { target: dmBadge; property: "scale"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2.5 }
                                    }
                                }
                            }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: Discord.openDms() }
                        }
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
                        visible: Recorder.recording || Countdown.mode !== "" || Discord.inCall || Discord.dmCount > 0 || Dictation.active || Voice.active
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1; height: 14
                        color: Qt.alpha(Theme.text, 0.15)
                    }

                    // playing: art, title, a little equaliser
                    Art {
                        visible: win.mediaShown
                        opacity: win.mediaSwapOp
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22; radius: 7
                        source: root.player?.trackArtUrl ?? ""
                    }
                    Text {
                        visible: win.mediaShown
                        opacity: win.mediaSwapOp
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
                        visible: !win.mediaShown
                        opacity: win.mediaSwapOp
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.font
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        color: Theme.text
                        text: Qt.formatTime(clock.date, "hh:mm")
                    }
                    Row {
                        visible: !win.mediaShown && Weather.ready
                        opacity: win.mediaSwapOp
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
                    SwapFade on opacity {}

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
                    SwapFade on opacity {}
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
                    SwapFade on opacity {}
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
                    SwapFade on opacity {}
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
                    // follow the springing shape, so switching modes (; clipboard,
                    // : emoji) or a longer result list grows smoothly, not in a snap
                    width: win.state === "launcher" ? Math.min(sw.value, wantW + 24) : wantW
                    height: win.state === "launcher" ? sh.value : wantH
                    clip: true
                    opacity: win.state === "launcher" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: win.state === "launcher" ? 240 : 110 } }
                    onClose: root.launcherOpen = false
                }

                // ── media card (hover while playing) ──
                MediaCard {
                    id: mediaView
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: wantW
                    height: wantH
                    player: root.player
                    active: win.state === "media"
                    pointerIn: win.pointerIn
                    opacity: active ? 1 : 0
                    visible: opacity > 0.01
                    SwapFade on opacity {}
                    onExpand: win.expanded = true
                }

                // ── workspace overview ──
                VoiceView {
                    id: voiceView
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: wantW
                    height: wantH
                    active: win.state === "voice"
                    opacity: active ? 1 : 0
                    visible: opacity > 0.01
                    SwapFade on opacity {}
                }
                OverviewView {
                    id: overviewView
                    maxW: win.width - 40
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: wantW
                    height: wantH
                    opacity: win.state === "overview" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: win.state === "overview" ? 240 : 110 } }
                    onClose: root.overviewOpen = false
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
                    id: dash
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: win.openW
                    height: win.openH
                    opacity: win.state === "open" ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: win.state === "open" ? 320 : 90; easing.type: win.state === "open" ? Easing.Linear : Easing.OutCubic } } // gone before the resting row fades in
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
