.pragma library

// The island's glow while music plays: the most vivid of an album cover's main
// colours (ColorQuantizer's), lifted so it shows against the dark frame. A
// grey or black-and-white cover gets none. Colours are {r, g, b} in 0..1.

function _sv(c) {
    var mx = Math.max(c.r, c.g, c.b), mn = Math.min(c.r, c.g, c.b);
    return { s: mx > 0 ? (mx - mn) / mx : 0, v: mx };
}

function pick(colors) {
    var best = null, score = 0;
    (colors || []).forEach(function (c) {
        var sv = _sv(c);
        if (sv.s < 0.25 || sv.v < 0.12) return; // grey, or nearly black
        var k = sv.s * Math.sqrt(sv.v);
        if (k > score) { score = k; best = c; }
    });
    if (!best) return null;
    var lift = Math.max(1, 0.8 / Math.max(best.r, best.g, best.b));
    return { r: Math.min(1, best.r * lift), g: Math.min(1, best.g * lift), b: Math.min(1, best.b * lift) };
}
