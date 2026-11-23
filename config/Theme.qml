pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Colours come from Tint (bin/bead-tint: built from the wallpaper, written to
// $XDG_STATE_HOME/bead/scheme.json) and follow it live. Until Tint has run, a
// Caelestia scheme is used if there is one. BEAD_THEME=sileo uses sileo's own
// palette.
Singleton {
    id: root

    readonly property bool themed: Settings.theme !== "sileo"
    property var tint: ({})
    property var caelestia: ({})
    readonly property var scheme: Object.keys(tint).length ? tint : caelestia

    function c(key: string, fallback: string): color {
        return themed && scheme[key] ? "#" + scheme[key] : fallback;
    }

    readonly property string font: "Noto Sans"
    readonly property color fill: c("surfaceContainer", "#1a1a1a")
    // Caelestia's screen frame: its colour and thickness (physical px)
    readonly property color frame: c("surface", "#0e0e0e")
    readonly property int frameThickness: 10
    readonly property color text: c("onSurface", "#e6e6e6")
    readonly property color subtext: themed && scheme.onSurfaceVariant ? Qt.alpha(c("onSurfaceVariant", "#ffffff"), 0.8) : Qt.rgba(1, 1, 1, 0.5)
    readonly property color neutral: c("outline", "#a3a3a3")

    // sileo's state tones, or the scheme's matching roles
    readonly property var tones: ({
        success: c("success", "#3ac530"), loading: c("outline", "#737373"), error: c("error", "#fb2c36"),
        warning: c("term2", "#f0b100"), info: c("tertiary", "#00a6f4"),
        action: c("primary", "#2b7fff"), notify: c("primary", "#2b7fff"),
        confirm: c("primary", "#2b7fff"), choose: c("primary", "#2b7fff")
    })
    function tone(kind: string): color { return tones[kind] || tones.info; }

    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/bead/scheme.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.tint = JSON.parse(text()).colours || {}; } catch (e) {} }
    }
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/caelestia/scheme.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.caelestia = JSON.parse(text()).colours || {}; } catch (e) {} }
    }
}
