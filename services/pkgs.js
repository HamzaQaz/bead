.pragma library

// bead's installer: reading what pacman (via expac), paru and flatpak print,
// searching a cached Flathub list, and ranking results across the three.
// A result is { source: "repo"|"aur"|"flathub", name, title, version, desc,
// installed, size (bytes, repos), votes (AUR), outdated (AUR), repo }.

function _lines(t) { return String(t || "").split("\n").filter(function (l) { return l.length > 0; }); }
function _has(list, name) { return (list || []).indexOf(name) >= 0; }

// expac -Ss '%r\t%n\t%v\t%m\t%d' <query>: the first repo listing a name wins,
// as pacman would pick it
function parseRepo(text, installed) {
    var seen = {}, out = [];
    _lines(text).forEach(function (l) {
        var f = l.split("\t");
        if (f.length < 5 || seen[f[1]]) return;
        seen[f[1]] = true;
        out.push({ source: "repo", repo: f[0], name: f[1], title: "", version: f[2], size: Number(f[3]) || 0,
                   desc: f.slice(4).join("\t"), installed: _has(installed, f[1]) });
    });
    return out;
}

// paru -Ssa <query>: "aur/name version [+votes ~pop] [Installed] [Out-of-date: …]"
// then an indented description line
function parseAur(text, installed) {
    var out = [];
    _lines(text).forEach(function (l) {
        var m = /^aur\/(\S+)\s+(\S+)\s+\[\+(\d+)[^\]]*\](.*)$/.exec(l);
        if (m) {
            out.push({ source: "aur", name: m[1], title: "", version: m[2], votes: Number(m[3]), desc: "",
                       installed: /\[Installed/i.test(m[4]) || _has(installed, m[1]), outdated: /Out-of-date/i.test(m[4]) });
        } else if (/^\s+/.test(l) && out.length && !out[out.length - 1].desc) {
            out[out.length - 1].desc = l.trim();
        }
    });
    return out;
}

// flatpak remote-ls --app --columns=application,name,version,description flathub
function parseCatalog(text) {
    return _lines(text).map(function (l) {
        var f = l.split("\t");
        return { id: f[0], title: f[1] || f[0], version: f[2] || "", desc: f[3] || "" };
    }).filter(function (a) { return a.id && a.id.indexOf(".") > 0; });
}

function searchFlathub(catalog, query, installed, limit) {
    var q = String(query || "").toLowerCase().trim();
    if (!q) return [];
    var out = [];
    (catalog || []).forEach(function (a) {
        var hay = (a.id + " " + a.title + " " + a.desc).toLowerCase();
        if (hay.indexOf(q) < 0) return;
        out.push({ source: "flathub", name: a.id, title: a.title, version: a.version, desc: a.desc, installed: _has(installed, a.id) });
    });
    return out.slice(0, limit || 40);
}

var _sourceOrder = { repo: 0, flathub: 1, aur: 2 };

// "name\tnumber" lines (bead's cached popularity lists) → { name: number }
function parsePop(text) {
    var out = {};
    _lines(text).forEach(function (l) {
        var f = l.split("\t");
        if (f[0] && f.length > 1) out[f[0]] = Number(f[1]) || 0;
    });
    return out;
}

function _log(v, top) { return v > 0 ? Math.max(0, Math.min(1, Math.log(v + 1) / Math.log(top))) : 0; }

// How popular a result is, 0..1: repos by pkgstats (% of Arch users who have
// it), Flathub by last month's installs, the AUR by votes, kept below the
// top since nobody reviews it. pop = { repo: {...}, flathub: {...} }
function popularity(r, pop) {
    pop = pop || {};
    // as if 100% of Arch users were a top Flatpak's 250k installs a month
    if (r.source === "repo") return _log(((pop.repo || {})[r.name] || 0) * 2500, 250000) * (library(r.name) ? 0.4 : 1);
    if (r.source === "flathub") return _log((pop.flathub || {})[r.name] || 0, 250000);
    return _log(r.votes || 0, 5000) * 0.8;
}

// A package most people get as a dependency, not on purpose: pkgstats counts
// those too (libxmlb is on 88% of systems), so their popularity counts less
function library(name) {
    return /^(lib(?!re)|lib32-|python-|python2-|ruby-|perl-|lua-|haskell-|nodejs-|rust-|go-|java-|qt[56]-|kf[56]-|gst-|xorg-|x11-)|-(libs|docs?|headers|data|common)$/.test(name);
}

// How well a result matches: 0 its name (or title) is the query, 1 it starts
// with it, 2 the name has it somewhere, 3 a word in the description starts
// with it, 4 only a run of letters somewhere does ("blobs" for "obs")
function _score(r, q) {
    var name = String(r.name || "").toLowerCase(), title = String(r.title || "").toLowerCase();
    if (name === q || title === q) return 0; // (a Flatpak's id never is; its title can be)
    if (name.indexOf(q) === 0 || title.indexOf(q) === 0) return 1;
    if (name.indexOf(q) >= 0 || title.indexOf(q) >= 0) return 2;
    var words = String(r.desc || "").toLowerCase().split(/[^a-z0-9+]+/);
    return words.some(function (w) { return w.indexOf(q) === 0; }) ? 3 : 4;
}

// Best first: an exact name (repo, then Flathub, then the AUR), then the most
// popular, a name that starts with (or has) the query counting for a little
// more, a word in the description for the same, a mere run of letters for less
var _closeness = [0, 0.1, 0.05, 0, 0];
function rank(results, query, pop) {
    var q = String(query || "").toLowerCase().trim();
    return results.map(function (r, i) {
        var s = _score(r, q);
        return { r: r, exact: s === 0 ? 0 : 1, k: _closeness[s] + popularity(r, pop) * (s === 4 ? 0.3 : 1), o: _sourceOrder[r.source] || 0, i: i };
    }).sort(function (a, b) {
        if (a.exact !== b.exact) return a.exact - b.exact;
        // exact names: the repo's own first (it's what you'd mean), then by popularity
        if (a.exact === 0) return a.o - b.o || b.k - a.k || a.i - b.i;
        return b.k - a.k || a.o - b.o || a.i - b.i;
    })
      .map(function (x) { return x.r; });
}

// One line of an install's output: {step, of, pct, text}, or null if it says
// nothing about progress. pct is -1 when the line has none.
function progress(line) {
    var l = String(line || "").trim();
    if (!l || /^::/.test(l)) return null;
    var step = /^\(\s*(\d+)\/(\d+)\)\s*(.*)$/.exec(l);
    var pct = /(\d{1,3})%/.exec(l);
    if (!step && !pct) return null;
    var text = step ? step[3] : l.replace(/[█▉▊▋▌▍▎▏░▒▓#\-]+/g, " ").replace(/\d{1,3}%.*$/, "").replace(/\s+/g, " ").trim();
    text = text.charAt(0).toUpperCase() + text.slice(1);
    return { step: step ? Number(step[1]) : -1, of: step ? Number(step[2]) : -1, pct: pct ? Math.min(100, Number(pct[1])) : -1, text: text };
}

// Packages after which the computer should be restarted: kernels, graphics
// drivers, microcode, the init system and the C library
function restartAfter(name) {
    return /^(linux(-(cachyos|zen|lts|hardened|rt)[a-z0-9-]*)?(-headers)?|nvidia(-[a-z0-9-]+)?|systemd|glibc|lib32-glibc|mesa|lib32-mesa|(amd|intel)-ucode)$/.test(name);
}

// checkupdates and paru -Qua print "name old -> new"; flatpak remote-ls
// --updates --app --columns=application,version prints "id\tversion"
function parseUpdates(repoText, aurText, flatpakText) {
    var out = [];
    function arrows(text, source) {
        _lines(text).forEach(function (l) {
            var m = /^(\S+)\s+(\S+)\s+->\s+(\S+)/.exec(l);
            if (m) out.push({ source: source, name: m[1], from: m[2], to: m[3], restart: restartAfter(m[1]) });
        });
    }
    arrows(repoText, "repo");
    arrows(aurText, "aur");
    _lines(flatpakText).forEach(function (l) {
        var f = l.split("\t");
        if (f[0] && f[0].indexOf(".") > 0) out.push({ source: "flathub", name: f[0], from: "", to: f[1] || "", restart: false });
    });
    return out;
}

function size(bytes) {
    if (!bytes) return "";
    var units = ["B", "KB", "MB", "GB"], i = 0, v = bytes;
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
    return (v >= 10 || i < 2 ? Math.round(v) : Math.round(v * 10) / 10) + " " + units[i];
}

// ── the Apps tab ──

// pacman -Qo /usr/share/applications/*.desktop: desktop id → package
function parseOwned(text) {
    var out = {};
    _lines(text).forEach(function (l) {
        var m = /\/([^\/]+)\.desktop is owned by (\S+)/.exec(l);
        if (m) out[m[1]] = m[2];
    });
    return out;
}

// "1.2 GB", "512.0 kB" (flatpak list's sizes) → bytes
function bytes(text) {
    var m = /([\d.]+)\s*([kKMGT]?)B/.exec(String(text || ""));
    if (!m) return 0;
    var mult = { "": 1, k: 1024, K: 1024, M: 1048576, G: 1073741824, T: 1099511627776 }[m[2]];
    return Math.round(parseFloat(m[1]) * mult);
}

// by "size" (biggest first), "used" (most recent first) or "name"
function sortApps(apps, by) {
    return apps.slice().sort(function (a, b) {
        if (by === "size" && b.size !== a.size) return b.size - a.size;
        if (by === "used" && b.used !== a.used) return b.used - a.used;
        return String(a.name).localeCompare(String(b.name));
    });
}

function ago(t, now) {
    if (!t) return "Never opened from bead";
    var m = Math.round((now - t) / 60000);
    if (m < 60) return "Opened " + Math.max(1, m) + " min ago";
    var h = Math.round(m / 60);
    if (h < 24) return "Opened " + h + " h ago";
    var d = Math.round(h / 24);
    return d === 1 ? "Opened yesterday" : "Opened " + d + " days ago";
}
