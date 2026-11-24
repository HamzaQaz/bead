.pragma library
// Fading from one palette to the next (Theme.qml). Colours are "rrggbb", as
// Tint writes them. Plain logic: tests/tst_blend.qml.

function channels(hex) {
    return /^[0-9a-f]{6}$/i.test(String(hex)) ? [0, 2, 4].map(function (i) { return parseInt(hex.substr(i, 2), 16); }) : null;
}

// the colour a share `t` (0 to 1) of the way from one to the other, as "#rrggbb"
function mixHex(from, to, t) {
    var a = channels(from), b = channels(to);
    if (!a || !b) return "#" + to;
    t = Math.max(0, Math.min(1, t));
    return "#" + [0, 1, 2].map(function (i) {
        var v = Math.round(a[i] + (b[i] - a[i]) * t).toString(16);
        return v.length < 2 ? "0" + v : v;
    }).join("");
}

// one part of the ripple: it starts `start` of the way in and takes `span` of it
function phase(t, start, span) { return Math.max(0, Math.min(1, (t - start) / span)); }

// are two palettes different?
function differs(a, b) {
    var ka = Object.keys(a), kb = Object.keys(b);
    if (ka.length !== kb.length) return true;
    return ka.some(function (k) { return a[k] !== b[k]; });
}
