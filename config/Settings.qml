pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// bead's settings, kept in ~/.config/bead/settings.json. Changing one here (or
// in the Settings window) saves it; editing the file applies live.
Singleton {
    id: root

    // idle, in minutes (0 = never)
    property alias lockAfter: a.lockAfter
    property alias discordMusic: a.discordMusic     // Discord presence: the music playing (off by default)
    property alias discordProject: a.discordProject // Discord presence: the project you're in (off by default)
    property alias workspaceGroups: a.workspaceGroups // each monitor owns ten workspaces (services/Windows.qml)
    property alias lockAtLogin: a.lockAtLogin       // "auto" (when the machine logs in by itself) | "on" | "off"
    property alias screenOffAfter: a.screenOffAfter
    property alias suspendAfter: a.suspendAfter
    property alias pauseForMedia: a.pauseForMedia   // stay awake while something plays
    // looks
    property alias theme: a.theme                   // "wallpaper" | "sileo"
    property alias tint: a.tint                     // Tint's strength: "vibrant" | "muted" | "mono"
    property alias showTitle: a.showTitle           // the window title down the bar
    property alias islandScreen: a.islandScreen     // monitor name; "" = $BEAD_ISLAND_SCREEN or the first screen
    property alias scale: a.scale                   // UI size; read by `bead start` ($BEAD_SCALE wins)
    property alias scaleWas: a.scaleWas             // the size before a change not yet confirmed (0: none), see config/sizecheck.js
    // other
    property alias units: a.units                   // "auto" | "celsius" | "fahrenheit"
    property alias askModel: a.askModel             // "sonnet" | "opus" | "haiku"
    property alias askVia: a.askVia                 // "claude" (Claude Code) | "api" (own key) | "local"
    property alias clipHints: a.clipHints           // copied a colour, address, tracking number: the island offers what's next
    property alias nightLight: a.nightLight         // "off" | "on" | "sunset": a warmer screen (services/NightLight.qml)
    property alias nightTemp: a.nightTemp           // its colour temperature, K (2500 to 6000)
    property alias gameMode: a.gameMode             // performance, no blur or animations while a game is fullscreen

    // the island's monitor: chosen, or Hyprland's first (id 0; Quickshell's own
    // screen order doesn't follow it, so screens[0] could be a side monitor)
    readonly property string home: islandScreen || Quickshell.env("BEAD_ISLAND_SCREEN")
        || ([...Hyprland.monitors.values].sort((a, b) => a.id - b.id)[0]?.name ?? Quickshell.screens[0]?.name ?? "")

    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/bead/settings.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: err => { if (err === FileViewError.FileNotFound) { Quickshell.execDetached(["mkdir", "-p", file.path.replace(/\/[^/]*$/, "")]); saveLater.start(); } }

        JsonAdapter {
            id: a
            property real lockAfter: 3
            property string lockAtLogin: "auto"
            property bool workspaceGroups: true
            property bool discordMusic: false
            property bool discordProject: false
            property real screenOffAfter: 5
            property real suspendAfter: 10
            property bool pauseForMedia: true
            property string theme: Quickshell.env("BEAD_THEME") === "sileo" ? "sileo" : "wallpaper"
            property string tint: "vibrant"
            property bool showTitle: true
            property string islandScreen: ""
            property real scale: 1
            property real scaleWas: 0
            property string units: "auto"
            property string askModel: Quickshell.env("BEAD_ASK_MODEL") || "sonnet"
            property string askVia: "claude"
            property bool gameMode: true
            property string nightLight: "off"
            property real nightTemp: 4500
            property bool clipHints: true
        }
    }
    // first run: write the defaults once the folder exists
    Timer { id: saveLater; interval: 300; onTriggered: file.writeAdapter() }
}
