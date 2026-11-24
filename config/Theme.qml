pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "blend.js" as Blend

// Colours come from Tint (bin/bead-tint: built from the wallpaper, written to
// $XDG_STATE_HOME/bead/scheme.json) and follow it live. Until Tint has run,
// the fallbacks below (a neutral dark palette). BEAD_THEME=sileo uses sileo's
// own palette.
//
// A new palette (a new wallpaper) doesn't snap in: it ripples out from the
// island. `ripple` runs 0 → 1; the island's own colours and the accents lead,
// the frame, the bar and the text follow a moment behind. `changed` fires as
// it starts, for anything that wants to mark it (the island and the bar send
// a band of light across themselves).
Singleton {
    id: root

    readonly property bool themed: Settings.theme !== "sileo"
    property var scheme: ({})

    // ── the ripple ──
    property var prev: ({})    // the palette before this one
    property real ripple: 1
    readonly property real lead: Blend.phase(ripple, 0, 0.72)
    readonly property real trail: Blend.phase(ripple, 0.28, 0.72)
    signal changed()
    NumberAnimation { id: rippling; target: root; property: "ripple"; from: 0; to: 1; duration: 820; easing.type: Easing.InOutSine }
    // take a newly read palette; if there was one before and it differs, ripple
    function adopt(next: var): void {
        const before = scheme;
        scheme = next;
        if (!Object.keys(before).length || !Blend.differs(before, scheme)) return;
        prev = before;
        ripple = 0;
        rippling.restart();
        changed();
    }
    function at(key: string, fallback: string, t: real): color {
        if (!(themed && scheme[key])) return fallback;
        return t < 1 ? Blend.mixHex(prev[key], scheme[key], t) : "#" + scheme[key];
    }

    function c(key: string, fallback: string): color { return at(key, fallback, lead); }

    readonly property string font: "Noto Sans"
    readonly property color fill: c("surfaceContainer", "#1a1a1a")
    // the screen frame: its colour and thickness (physical px)
    readonly property color frame: at("surface", "#0e0e0e", trail)
    readonly property int frameThickness: 10
    readonly property color text: at("onSurface", "#e6e6e6", trail)
    readonly property color subtext: themed && scheme.onSurfaceVariant ? Qt.alpha(at("onSurfaceVariant", "#ffffff", trail), 0.8) : Qt.rgba(1, 1, 1, 0.5)
    readonly property color neutral: at("outline", "#a3a3a3", trail)

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
        onLoaded: { try { root.adopt(JSON.parse(text()).colours || {}); } catch (e) {} }
    }
}
