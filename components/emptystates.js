.pragma library
// What a panel says when it has nothing to show, is still loading, or
// couldn't load: the words, and whether there's something to press. Plain
// logic: tests/tst_emptystates.qml.

// the weather tab: null when there's weather to show (old weather stays up
// if a refresh fails)
function weather(s) {
    if (s.ready) return null;
    if (s.failed) return { glyph: "cloud_off", text: "Couldn't get the weather", hint: "Check the connection, then try again", retry: true };
    return { glyph: "cloud_sync", text: "Getting the weather…", hint: "", retry: false };
}

// the wallpapers tab: null when the grid has something in it
function wallpapers(s) {
    if (s.shown > 0) return null;
    if (s.stills + s.lives === 0)
        return { glyph: "wallpaper", text: "No wallpapers yet", hint: "Put pictures in " + s.dir, open: true };
    var other = s.filter === "live" ? s.stills : s.lives, kind = s.filter === "live" ? "still" : "live";
    return { glyph: "filter_alt_off", text: "No " + s.filter + " wallpapers",
             hint: other + " " + kind + (other === 1 ? " one is" : " ones are") + " under All", open: false };
}

// the Wi-Fi panel's line: "" when there are networks. `looking`: seconds since it opened
function wifi(s) {
    if (!s.enabled) return "Wi-Fi is off";
    if (!s.adapter) return "No Wi-Fi adapter";
    if (s.nets > 0) return "";
    return s.looking < 10 ? "Looking for networks…" : "No networks in range";
}
