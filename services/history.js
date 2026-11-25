.pragma library
// Update history and rollback (services/Updates.qml, modules/bar/UpdatesPanel.qml):
// pacman's log as one entry per transaction, the cached package files an undo
// needs, and held versions bead's updates skip. Pure: the caller reads the
// log, lists the cache and asks pacman what's installed.

var LINE = /^\[([^\]]+)\] \[([A-Z-]+)\] (.*)$/;
var CHANGE = /^(upgraded|downgraded|reinstalled) (\S+) \((\S+) -> (\S+)\)$/;
var ONE = /^(installed|removed) (\S+) \((\S+)\)$/;

// the log → [{ time, command, changes: [{ op, name, from, to }] }], newest first;
// transactions that changed nothing are left out
function parse(text) {
    var out = [], cur = null, command = "";
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var m = LINE.exec(lines[i]);
        if (!m) continue;
        var who = m[2], what = m[3];
        if (who === "PACMAN" && what.indexOf("Running '") === 0) { command = what.slice(9, -1); continue; }
        if (who !== "ALPM") continue;
        if (what === "transaction started") { if (cur && cur.changes.length) out.push(cur); cur = { time: "", command: command, changes: [] }; command = ""; continue; }
        if (what === "transaction completed" || what === "transaction failed") { if (cur && cur.changes.length) out.push(cur); cur = null; continue; }
        if (!cur) continue;
        var c = CHANGE.exec(what), o;
        if (c) o = { op: c[1], name: c[2], from: c[3], to: c[4] };
        else if ((c = ONE.exec(what))) o = c[1] === "installed" ? { op: "installed", name: c[2], from: "", to: c[3] } : { op: "removed", name: c[2], from: c[3], to: "" };
        else continue;
        if (!cur.time) cur.time = m[1];
        cur.changes.push(o);
    }
    if (cur && cur.changes.length) out.push(cur);
    return out.reverse();
}

// what an entry was: from the command that ran it, else from its changes
function label(t) {
    var cmd = t.command || "", ch = t.changes;
    var names = function () { return ch.slice(0, 2).map(function (c) { return c.name; }).join(", ") + (ch.length > 2 ? " and " + (ch.length - 2) + " more" : ""); };
    // by what changed: AUR helpers install every build with pacman -U, so the
    // command can't tell an update from a rollback
    var all = function (op) { return ch.every(function (c) { return c.op === op; }); };
    if (all("downgraded")) return "Rolled back " + names();
    if (/(^|\s)-S\w*u|--sysupgrade/.test(cmd)) return "System update";
    if (all("installed")) return "Installed " + names();
    if (all("removed")) return "Removed " + names();
    return "Updated " + names();
}

// the cached file for a package at a version (exactly that name: "mesa" isn't
// "mesa-utils"), from pacman's cache or an AUR helper's build folder; "" if gone
function cached(name, version, files) {
    var want = name + "-" + version + "-";
    for (var i = 0; i < files.length; i++) {
        var f = files[i], base = f.slice(f.lastIndexOf("/") + 1);
        if (!/\.pkg\.tar\.(zst|xz|gz|bz2)$/.test(base)) continue;
        if (base.indexOf(want) !== 0) continue;
        // what follows is only the architecture
        var rest = base.slice(want.length).replace(/\.pkg\.tar\.\w+$/, "");
        if (/^[A-Za-z0-9_]+$/.test(rest)) return f;
    }
    return "";
}

// undoing an entry (or one package of it): { files: to install with pacman -U,
// missing: old version not cached, changed: updated again since (left alone),
// kept: new in that update (left installed), holds: what to skip from now on }
function undo(t, files, installed, only) {
    var p = { files: [], missing: [], changed: [], kept: [], holds: [] };
    installed = installed || {};
    t.changes.forEach(function (c) {
        if (only && c.name !== only) return;
        if (c.op === "installed") { p.kept.push(c.name); return; }
        if (c.op === "reinstalled") return;
        // it must still be as that update left it (removed: still not installed)
        var now = installed[c.name] || "";
        if (now !== c.to) { p.changed.push(c.name); return; }
        var f = cached(c.name, c.from, files);
        if (!f) { p.missing.push(c.name); return; }
        p.files.push(f);
        if (c.op === "upgraded") p.holds.push({ name: c.name, version: c.to });
    });
    return p;
}

// of the updates waiting ([{ name, to }]), the names to skip: a held version
function ignored(holds, updates) {
    return updates.filter(function (u) {
        return holds.some(function (h) { return h.name === u.name && h.version === u.to; });
    }).map(function (u) { return u.name; });
}

// holds still needed: dropped once a different (newer) version is waiting
function keepHolds(holds, updates) {
    return holds.filter(function (h) {
        var u = updates.filter(function (x) { return x.name === h.name; })[0];
        return !u || u.to === h.version;
    });
}

// a log time ("2026-11-25T00:56:05-0600") as Date (JS wants "-06:00")
function date(time) { return new Date(String(time).replace(/([+-]\d\d)(\d\d)$/, "$1:$2")); }
// in words: "Today 00:56", "Yesterday 23:11", else "Fri 20 Nov"
function when(time, now) {
    var d = date(time), n = now || new Date();
    var day = function (x) { return new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime(); };
    var diff = Math.round((day(n) - day(d)) / 86400000);
    if (diff === 0) return "Today " + Qt.formatTime(d, "HH:mm");
    if (diff === 1) return "Yesterday " + Qt.formatTime(d, "HH:mm");
    return Qt.formatDate(d, "ddd d MMM");
}
