pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "displays.js" as D

// Monitors: what Hyprland has now (hyprctl monitors -j), and changing them
// live with `hyprctl eval 'hl.monitor({...})'`. Every change is on trial: it
// goes back by itself after 15 s unless kept, so a mode the screen can't show
// undoes itself. Keeping writes the whole layout to ~/.config/hypr/bead-monitors.lua,
// which Hyprland reads only if the user's config has `pcall(require, "bead-monitors")`
// after its own monitor rules (bead never edits the user's config).
Singleton {
    id: root

    property var monitors: []
    readonly property string savePath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hypr/bead-monitors.lua"
    readonly property string hookLine: 'pcall(require, "bead-monitors")'
    property bool hooked: false      // the user's config loads the saved file
    property string error: ""

    // ── reading ──
    function refresh(): void { probe.running = true; hookProbe.running = true; }
    Process {
        id: probe
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.monitors = JSON.parse(text).sort((a, b) => a.x - b.x); } catch (e) {} }
        }
    }
    Process {
        id: hookProbe
        command: ["sh", "-c", 'grep -rqs --include="*.lua" "bead-monitors" "$1" --exclude=bead-monitors.lua', "sh",
            (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/hypr"]
        onExited: code => root.hooked = code === 0
    }

    // ── changing, on trial ──
    property var before: null        // every monitor's spec before the trial started
    property int left: 0             // seconds until it goes back
    readonly property bool trying: before !== null
    function apply(name: string, change: var): void {
        const m = monitors.find(x => x.name === name);
        if (!m) return;
        if (!trying) before = monitors.map(x => D.spec(x, {}));
        error = "";
        run(D.spec(m, change));
        left = 15;
        countdown.restart();
    }
    function keep(): void {
        countdown.stop();
        before = null;
        saveAfterRefresh = true;
        refresh();
    }
    function revert(): void {
        countdown.stop();
        if (before) run(before.join("\n"));
        before = null;
    }
    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: { if (--root.left <= 0) root.revert(); }
    }
    function run(lua: string): void {
        applier.command = ["hyprctl", "eval", lua];
        applier.running = true;
    }
    Process {
        id: applier
        stdout: StdioCollector {
            onStreamFinished: { const t = text.trim(); if (t && t !== "ok") root.error = t; }
        }
        onExited: settle.restart()
    }
    // monitors take a moment to come back with the new mode
    Timer { id: settle; interval: 700; onTriggered: root.refresh() }

    // ── saving ──
    property bool saveAfterRefresh: false
    onMonitorsChanged: if (saveAfterRefresh) { saveAfterRefresh = false; save(); }
    function save(): void {
        file.setText("-- Written by bead's Displays tab; changes made there are saved here.\n"
            + "-- Hyprland reads it when your config has, after its own monitor rules:\n"
            + "--   " + hookLine + "\n\n"
            + monitors.map(m => D.spec(m, {})).join("\n") + "\n");
    }
    FileView { id: file; path: root.savePath; printErrors: false }
}
