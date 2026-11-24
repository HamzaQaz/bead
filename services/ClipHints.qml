pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.config

// What you copy, read for the obvious next step; the island offers it for a
// moment and a tap does it: a colour (shown, tap for its other format), a
// tracking number (tap to track it), a street address (tap for the map), a
// link copied outside the browser (tap to open). Nothing is sent anywhere
// unless you tap. Passwords (marked by the password manager), anything that
// looks like a key or token, and copies made under a fullscreen window are
// ignored. Settings.clipHints turns it off.
Singleton {
    id: root

    signal hint(string kind, string text)
    property string last: ""
    property bool primed: false   // the first read is what was already copied

    // every new text copy: its start, then a record separator
    Process {
        id: watch
        running: Settings.clipHints
        command: ["sh", "-c", "exec wl-paste --type text --watch sh -c 'wl-paste --list-types 2>/dev/null | grep -q passwordManagerHint && exit 0; head -c 400; printf \"\\036\"'"]
        stdout: SplitParser {
            splitMarker: "\u001e"
            onRead: data => root.read(data)
        }
        onRunningChanged: if (!running) root.primed = false
        onExited: if (Settings.clipHints) again.start()
    }
    Timer { id: again; interval: 5000; onTriggered: watch.running = Settings.clipHints }

    readonly property var browsers: /^(firefox|librewolf|zen|floorp|waterfox|chromium|google-chrome|brave-browser|vivaldi|microsoft-edge|thorium|org\.mozilla|com\.brave|org\.chromium)/i

    function read(t: string): void {
        const s = t.trim();
        if (!primed) { primed = true; last = s; return; }
        if (!s || s === last || s.length > 300) { last = s; return; }
        last = s;
        if (Hyprland.focusedWorkspace?.hasFullscreen) return;
        const k = kindOf(s);
        if (k === "link" && root.browsers.test(Hyprland.activeToplevel?.wayland?.appId ?? "")) return;
        if (k) hint(k, s);
    }
    function kindOf(s: string): string {
        const type = Clipboard.typeOf(s);
        if (type === "secret") return "";
        if (type === "colour") return "colour";
        if (type === "link") return /^(https?:\/\/|www\.)/i.test(s) ? "link" : "";
        const flat = s.replace(/\s+/g, "");
        if (/^1Z[0-9A-Z]{16}$/i.test(flat)            // UPS
            || /^9[2-5]\d{20}$/.test(flat)             // USPS
            || /^[A-Z]{2}\d{9}[A-Z]{2}$/.test(flat)) return "parcel"; // international post (RR123456785GB)
        // "221B Baker Street, London", "1600 Amphitheatre Pkwy, Mountain View, CA 94043"
        if (s.length < 160 && !/\n.*\n.*\n/.test(s)
            && /^\d{1,6}[a-z]?\s+(?:[\w.'-]+\s+){0,4}(street|st|avenue|ave|road|rd|boulevard|blvd|drive|dr|lane|ln|way|court|ct|place|pl|parkway|pkwy|highway|hwy|circle|cir|terrace|ter|square|sq|close|crescent)\b\.?(,|\s|$)/i.test(s)) return "address";
        return "";
    }

    // the same colour the other way round: #rrggbb <-> rgb(r, g, b) ("" for hsl)
    function otherColour(s: string): string {
        s = s.trim();
        let r, g, b, al = 1;
        const hex = s.match(/^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i);
        const rgb = s.match(/^rgba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)(?:[\s,\/]+([\d.]+%?))?\s*\)$/i);
        if (hex) {
            let x = hex[1];
            if (x.length <= 4) x = x.split("").map(c => c + c).join("");
            [r, g, b] = [0, 2, 4].map(i => parseInt(x.slice(i, i + 2), 16));
            if (x.length === 8) al = parseInt(x.slice(6), 16) / 255;
            return "rgb" + (al < 1 ? "a" : "") + "(" + r + ", " + g + ", " + b + (al < 1 ? ", " + Math.round(al * 100) / 100 : "") + ")";
        }
        if (rgb) {
            [r, g, b] = [1, 2, 3].map(i => Math.min(255, parseInt(rgb[i])));
            if (rgb[4]) al = rgb[4].endsWith("%") ? parseFloat(rgb[4]) / 100 : parseFloat(rgb[4]);
            const h = v => Math.round(v).toString(16).padStart(2, "0");
            return "#" + h(r) + h(g) + h(b) + (al < 1 ? h(al * 255) : "");
        }
        return "";
    }
}
