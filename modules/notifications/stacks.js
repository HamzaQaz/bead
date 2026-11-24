.pragma library

// Pop-ups from one app stack into one pill: a new one from an app already on
// screen takes that pill's place, carrying the ones before it. Toasts, pinned
// ones (questions, prompts) and critical ones never stack.

var keep = 4; // earlier ones a pill remembers

function _stacks(p) {
    return !!p && !p.spec && !p.sticky && p.urgency !== 2 && !!p.appName;
}

// null when `entry` doesn't join a pop-up in `popups`; otherwise {gone, entry}:
// the key of the pop-up it replaces, and `entry` with that one's history.
function merge(popups, entry) {
    if (!_stacks(entry)) return null;
    for (var i = 0; i < popups.length; i++) {
        var p = popups[i];
        if (!_stacks(p) || p.appName !== entry.appName) continue;
        var earlier = [{ summary: p.summary || "", body: p.body || "" }].concat(p.earlier || []).slice(0, keep);
        return { gone: p.key, entry: Object.assign({}, entry, { earlier: earlier, count: (p.count || 1) + 1 }) };
    }
    return null;
}

// the count beside a stacked pill's title ("" for a single one)
function label(entry) { return entry && entry.count > 1 ? String(entry.count) : ""; }

function _plain(t) {
    return String(t || "").replace(/<[^>]*>/g, "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\s+/g, " ").trim();
}

// the earlier ones as faint lines under the newest's text, in `color`
// (StyledText: the pill's markup)
function fan(entry, color) {
    var e = (entry && entry.earlier) || [];
    return e.map(function (x) {
        var b = _plain(x.body);
        return "<font color='" + (color || "#888888") + "'>" + _plain(x.summary) + (b ? " · " + b : "") + "</font>";
    }).join("<br>");
}
