.pragma library
// Pinned clips: things you paste again and again, kept on top of the
// clipboard list and never expiring (cliphist's history does). Clipboard.qml
// keeps them in ~/.config/bead/clips.json. Plain logic: tests/tst_pins.qml.
//
// a pin: { id, text, added (ms) }

// "" if this history entry can be pinned, else why not
function whyNot(entry) {
    if (entry.image || entry.type === "image") return "Only text can be pinned";
    if (entry.type === "secret") return "Keys and tokens can't be pinned";
    return "";
}

function same(a, b) { return String(a).trim() === String(b).trim(); }
function has(pins, text) { return pins.some(function (p) { return same(p.text, text); }); }

// with `text` pinned on top (unless it's empty or pinned already)
function add(pins, text, now) {
    if (!String(text).trim() || has(pins, text)) return pins.slice();
    var n = 1, taken = pins.map(function (p) { return p.id; });
    while (taken.indexOf("p" + now + "_" + n) >= 0) n++;
    return [{ id: "p" + now + "_" + n, text: String(text), added: now }].concat(pins);
}
function remove(pins, id) { return pins.filter(function (p) { return p.id !== id; }); }

// the clipboard list: pins, then the history without what's pinned; a search
// narrows both. `typeOf` (optional) says what kind of text a pin is
function rows(pins, entries, query, typeOf) {
    var q = String(query).trim().toLowerCase();
    var hit = function (t) { return !q || String(t).toLowerCase().indexOf(q) >= 0; };
    var top = pins.filter(function (p) { return hit(p.text); }).map(function (p) {
        return { id: "pin:" + p.id, pin: p.id, pinned: true, text: p.text, image: null, type: typeOf ? typeOf(p.text) : "text" };
    });
    var rest = entries.filter(function (e) { return !(e.text && has(pins, e.text)) && (e.image ? !q : hit(e.text)); });
    return top.concat(rest);
}

function parse(text) {
    var d;
    try { d = JSON.parse(text); } catch (e) { return []; }
    if (!d || !Array.isArray(d.pins)) return [];
    return d.pins.filter(function (p) { return p && p.id && typeof p.text === "string" && p.text.trim(); })
        .map(function (p) { return { id: String(p.id), text: p.text, added: Number(p.added) || 0 }; });
}
function serialise(pins) { return JSON.stringify({ pins: pins }, null, 2) + "\n"; }
