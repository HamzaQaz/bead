.pragma library

// The Displays tab's logic: reading `hyprctl monitors -j`, building a full
// hl.monitor({...}) spec (Hyprland's Lua config), and snapping a dragged
// monitor against the others. Positions and sizes are logical pixels.

function _num(v) { return Number(Number(v).toFixed(2)); }
function _safe(s) { return String(s == null ? "" : s).replace(/[^A-Za-z0-9_.:-]/g, ""); }

// refresh rates the monitor offers at its current size, highest first; ones
// that round to the same whole number show once, the closest to it kept
// (120.00 over 119.88)
function rates(m) {
    var by = {};
    (m.availableModes || []).forEach(function (s) {
        var r = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(s);
        if (!r || Number(r[1]) !== m.width || Number(r[2]) !== m.height) return;
        var hz = _num(r[3]), k = Math.round(hz);
        if (by[k] == null || Math.abs(hz - k) < Math.abs(by[k] - k)) by[k] = hz;
    });
    return Object.keys(by).map(function (k) { return by[k]; }).sort(function (a, b) { return b - a; });
}

// where it sits and how big it is on the desktop: rotated 90/270 swaps the
// sides, and scale shrinks them
function logical(m) {
    var rot = (m.transform || 0) % 2 === 1, s = m.scale || 1;
    return { x: m.x || 0, y: m.y || 0, w: Math.round((rot ? m.height : m.width) / s), h: Math.round((rot ? m.width : m.height) / s) };
}

// the whole rule for one monitor: what it has now (colour settings included,
// so nothing the user pinned is reset), with `c` applied: rate, scale,
// transform, x, y
function spec(m, c) {
    c = c || {};
    var bits = [
        'output = "' + _safe(m.name) + '"',
        'mode = "' + m.width + "x" + m.height + "@" + _num(c.rate != null ? c.rate : m.refreshRate) + '"',
        'position = "' + Math.round(c.x != null ? c.x : m.x) + "x" + Math.round(c.y != null ? c.y : m.y) + '"',
        "scale = " + _num(c.scale != null ? c.scale : m.scale || 1),
        "transform = " + (c.transform != null ? c.transform : m.transform || 0),
        "bitdepth = " + (/2101010/.test(m.currentFormat || "") ? 10 : 8)
    ];
    if (m.colorManagementPreset) bits.push('cm = "' + _safe(m.colorManagementPreset) + '"');
    if (m.sdrBrightness != null) bits.push("sdrbrightness = " + _num(m.sdrBrightness));
    if (m.sdrSaturation != null) bits.push("sdrsaturation = " + _num(m.sdrSaturation));
    if (m.vrr) bits.push("vrr = 1");
    return "hl.monitor({ " + bits.join(", ") + " })";
}

function _overlaps(a, b) { return a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h; }
function _clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

// where a monitor dropped at a.x, a.y goes: against a side of one of the
// others (never overlapping), the closest such place; an edge within `tol`
// of lining up with the other's lines up
function snap(a, others, tol) {
    if (!others.length) return { x: a.x, y: a.y };
    var best = null;
    function along(v, lo, len, olen) {   // slide along a side, keeping some of it shared
        v = _clamp(v, lo - len + 50, lo + olen - 50);
        if (Math.abs(v - lo) <= tol) return lo;
        if (Math.abs(v - (lo + olen - len)) <= tol) return lo + olen - len;
        return v;
    }
    others.forEach(function (b) {
        [
            { x: b.x + b.w, y: along(a.y, b.y, a.h, b.h) },
            { x: b.x - a.w, y: along(a.y, b.y, a.h, b.h) },
            { x: along(a.x, b.x, a.w, b.w), y: b.y + b.h },
            { x: along(a.x, b.x, a.w, b.w), y: b.y - a.h }
        ].forEach(function (p) {
            var r = { x: p.x, y: p.y, w: a.w, h: a.h };
            if (others.some(function (o) { return _overlaps(r, o); })) return;
            var d = Math.hypot(p.x - a.x, p.y - a.y);
            if (!best || d < best.d) best = { x: p.x, y: p.y, d: d };
        });
    });
    return best ? { x: best.x, y: best.y } : { x: a.x, y: a.y };
}
