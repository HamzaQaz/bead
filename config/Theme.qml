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
    NumberAnimation { id: rippling; target: root; property: "ripple"; from: 0; to: 1; duration: Look.v.ripple ? Motion.ms(820) : 1; easing.type: Easing.InOutSine }
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

    readonly property string font: Look.v.font
    // ── type: one scale for everything, two weights (Regular, Medium; DemiBold
    // only at heading size and up) ──
    readonly property int tiny: 10      // badges, counters
    readonly property int caption: 11   // hints, secondary lines
    readonly property int small: 12     // chips, labels
    readonly property int body: 13      // the default
    readonly property int title: 15     // a row's or a card's name
    readonly property int heading: 22   // a page's title
    readonly property int display: 28   // a big number, a hero's name
    // Customise → Look & feel: an accent of your own (else the wallpaper's), the frame's colour
    readonly property string accent: Look.v.accent
    function acc(fallbackKey: string, fallback: string): color { return accent ? accent : c(fallbackKey, fallback); }
    readonly property color fill: c("surfaceContainer", "#1a1a1a")
    // the screen frame: its colour and thickness (physical px)
    readonly property color frameBase: Look.v.frameColor === "black" ? "#000000"
        : Look.v.frameColor === "accent" ? Qt.tint(at("surface", "#0e0e0e", trail), Qt.alpha(acc("primary", "#2b7fff"), 0.16))
        : at("surface", "#0e0e0e", trail)
    readonly property color frame: frameBase
    // what the frame, the island and the pop-ups are drawn with (see-through when asked)
    readonly property color frameFill: Qt.alpha(frameBase, Look.v.frameOpacity)
    readonly property int frameThickness: Look.v.frameThickness
    readonly property color text: at("onSurface", "#e6e6e6", trail)
    readonly property color subtext: themed && scheme.onSurfaceVariant ? Qt.alpha(at("onSurfaceVariant", "#ffffff", trail), Look.v.subtext) : Qt.rgba(1, 1, 1, 0.5 * Look.v.subtext / 0.8)
    readonly property color neutral: at("outline", "#a3a3a3", trail)

    // sileo's state tones, or the scheme's matching roles
    readonly property var tones: ({
        success: c("success", "#3ac530"), loading: c("outline", "#737373"), error: c("error", "#fb2c36"),
        warning: c("term2", "#f0b100"), info: c("tertiary", "#00a6f4"),
        action: acc("primary", "#2b7fff"), notify: acc("primary", "#2b7fff"),
        confirm: acc("primary", "#2b7fff"), choose: acc("primary", "#2b7fff")
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
