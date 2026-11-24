.pragma library

// The overview's small decisions (OverviewView.qml).

// Where a window dropped on "New workspace" goes: the lowest number not in use
// (special workspaces have negative ids and don't count)
function freeWorkspace(ids) {
    var used = {};
    ids.forEach(function (i) { if (i > 0) used[i] = true; });
    var n = 1;
    while (used[n]) n++;
    return n;
}

// ↓/↑ through a card's `count` windows: -1 is the card itself, ↓ goes in and
// stops at the last window, ↑ comes back out to the card
function step(at, count, dir) {
    if (count <= 0) return -1;
    return Math.max(-1, Math.min(count - 1, Math.min(at, count - 1) + dir));
}

// windows top to bottom, then left to right, so ↓ follows how you'd read the
// card; `at` gives a window's [x, y]
function readingOrder(windows, at) {
    return windows.slice().sort(function (a, b) {
        var p = at(a) || [0, 0], q = at(b) || [0, 0];
        return p[1] - q[1] || p[0] - q[0];
    });
}
