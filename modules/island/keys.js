.pragma library
// The keys sheet: bead's keyboard shortcuts (data/keys.json, the same keys
// strand writes into Hyprland's config: strand's tests keep the two in step),
// searchable from the launcher ("#", or type "keys"). They're bead's defaults:
// Hyprland can't say what a key does, so ones you've changed or added aren't
// here. Plain logic: tests/tst_keys.qml.

var names = {
    SUPER: "Super", SHIFT: "Shift", CTRL: "Ctrl", ALT: "Alt", Period: ".", Return: "Enter", Print: "PrtSc",
    XF86AudioPlay: "Play", XF86AudioNext: "Next", XF86AudioPrev: "Previous",
    XF86MonBrightnessUp: "Brightness +", XF86MonBrightnessDown: "Brightness −"
};

// "SUPER + SHIFT + S" → ["Super", "Shift", "S"]; a modifier's own key
// (SUPER + SUPER_L: tapping Super) isn't said twice
function caps(keys) {
    var parts = String(keys).split("+").map(function (p) { return p.trim(); }).filter(function (p) { return p; });
    var out = [];
    parts.forEach(function (p) {
        var m = /^(SUPER|SHIFT|CTRL|ALT)_[LR]$/.exec(p);
        var name = names[m ? m[1] : p] || p;
        if (out.indexOf(name) < 0) out.push(name);
    });
    return out;
}
function title(what) { var s = String(what); return s.charAt(0).toUpperCase() + s.slice(1); }

// the ones matching every word typed (in what it does, its keys or its group)
function find(list, query) {
    var words = String(query).trim().toLowerCase().split(/\s+/).filter(function (w) { return w; });
    return list.filter(function (k) {
        var hay = (k.what + " " + caps(k.keys).join(" ") + " " + k.group).toLowerCase();
        return words.every(function (w) { return hay.indexOf(w) >= 0; });
    });
}

function parse(text) {
    var d;
    try { d = JSON.parse(text); } catch (e) { return []; }
    if (!Array.isArray(d)) return [];
    return d.filter(function (k) { return k && k.keys && k.what; })
        .map(function (k) { return { keys: String(k.keys), what: String(k.what), group: String(k.group || "") }; });
}

// typed in the ordinary search: is this asking for the sheet?
function asksFor(query) {
    var q = String(query).trim().toLowerCase();
    return q.length >= 3 && ("keys".indexOf(q) === 0 || "keyboard shortcuts".indexOf(q) === 0 || "shortcuts".indexOf(q) === 0);
}
