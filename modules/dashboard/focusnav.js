.pragma library
// Moving around the dashboard with the keyboard: which control the focus
// ring goes to, and what each key means. DashboardContent.qml finds the
// controls and moves the ring; this is the deciding. Plain logic:
// tests/tst_focusnav.qml.
//
// a control: { x, y, w, h } (in the dashboard), plus whatever the caller adds

function cx(r) { return r.x + r.w / 2; }
function cy(r) { return r.y + r.h / 2; }

// the nearest control from `from` going "left" | "right" | "up" | "down", or
// null. One that's in line (overlapping across the direction) beats a closer
// one off to the side. With no `from`, the first in reading order
function nearest(rects, from, dir) {
    if (!rects.length) return null;
    if (!from) return order(rects)[0];
    var horizontal = dir === "left" || dir === "right", sign = dir === "right" || dir === "down" ? 1 : -1;
    var best = null, bestScore = Infinity;
    rects.forEach(function (r) {
        if (r === from) return;
        // how far along the direction (edge to edge), and how far off to the side
        var along = horizontal ? (sign > 0 ? r.x - (from.x + from.w) : from.x - (r.x + r.w))
                               : (sign > 0 ? r.y - (from.y + from.h) : from.y - (r.y + r.h));
        var ahead = horizontal ? sign * (cx(r) - cx(from)) : sign * (cy(r) - cy(from));
        if (ahead <= 1) return;
        var gap = horizontal ? Math.max(0, Math.max(r.y - (from.y + from.h), from.y - (r.y + r.h)))
                             : Math.max(0, Math.max(r.x - (from.x + from.w), from.x - (r.x + r.w)));
        var off = horizontal ? Math.abs(cy(r) - cy(from)) : Math.abs(cx(r) - cx(from));
        // in line: by distance, then by how centred; off to the side costs a lot more
        var score = Math.max(0, along) + gap * 4 + (gap > 0 ? 1000 : 0) + off * 0.01;
        if (score < bestScore) { bestScore = score; best = r; }
    });
    return best;
}

// reading order: rows (controls within 12 px of level), then left to right
function order(rects) {
    return rects.slice().sort(function (p, q) { return Math.abs(p.y - q.y) > 12 ? p.y - q.y : p.x - q.x; });
}
// the next (dir 1) or previous (-1) in reading order, wrapping; the first with no `from`
function step(rects, from, dir) {
    var o = order(rects);
    if (!o.length) return null;
    var i = o.indexOf(from);
    return i < 0 ? o[0] : o[(i + dir + o.length) % o.length];
}

// what a key means. ctx: { tabs, tab, adjustable (the ring is on a slider or
// a choice), editing (a text field has the keys), ctrl, shift }
function action(key, ctx) {
    if (ctx.editing) return key === "Escape" ? { type: "leave" } : { type: "none" };
    if (key === "Escape") return { type: "close" };
    if (key === "Tab") {
        var d = ctx.shift ? -1 : 1;
        return ctx.ctrl ? { type: "tab", index: (ctx.tab + d + ctx.tabs) % ctx.tabs } : { type: "step", dir: d };
    }
    if (/^[1-9]$/.test(key)) return Number(key) <= ctx.tabs ? { type: "tab", index: Number(key) - 1 } : { type: "none" };
    if (key === "Return" || key === "Space") return { type: "press" };
    if (key === "Left" || key === "Right") {
        if (ctx.adjustable) return { type: "adjust", dir: key === "Right" ? 1 : -1 };
        return { type: "move", dir: key.toLowerCase() };
    }
    if (key === "Up" || key === "Down") return { type: "move", dir: key.toLowerCase() };
    return { type: "none" };
}

// The hint strip's text for the focused control: what it can do
// ({press, adjust, calendar}), or null when nothing has the ring yet; `tabs`
// is how many tabs the number keys reach.
function hints(can, tabs) {
    var bits = [];
    if (!can) bits.push("←↑↓→ move", "1–" + (tabs || 7) + " tabs");
    else if (can.calendar) bits.push("←↑↓→ day", "[ ] month", "t today");
    else {
        if (can.adjust) bits.push("←→ adjust");
        if (can.press) bits.push("⏎ press");
    }
    bits.push("esc close");
    return bits.join(" · ");
}
