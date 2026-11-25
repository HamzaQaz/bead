.pragma library
.import "pkgs.js" as Pkgs

// The App Store (services/Store.qml, modules/store/StoreWindow.qml): search
// results from the repos, Flathub and the AUR (pkgs.js) merged into one per
// app, the repos preferred; need-based search and the store front from bead's
// curated list (data/apps.json); a one-line reason per result.
// Tested in tests/tst_store.qml.

var _source = { repo: 0, flathub: 1, aur: 2 };
// in the AUR: the plain package, then a prebuilt one, then the rest, -git last
function _aurRank(name) { return /-git$/.test(name) ? 3 : /-bin$/.test(name) ? 1 : /-(appimage|nightly|beta|dev)$/.test(name) ? 2 : 0; }
function _norm(s) { return String(s || "").toLowerCase().replace(/-(bin|git|appimage|nightly|beta|dev)$/, "").replace(/[^a-z0-9]/g, ""); }
// a Flatpak id's last part names the app, unless it's a generic word
var _generic = ["client", "desktop", "studio", "app", "application", "editor", "player", "browser", "launcher", "gui", "viewer"];
function _keys(r) {
    if (r.source !== "flathub") return [_norm(r.name)];
    var k = [_norm(r.title)];
    var last = _norm(String(r.name).split(".").pop());
    if (last.length >= 4 && _generic.indexOf(last) < 0 && k.indexOf(last) < 0) k.push(last);
    return k;
}

// results → [{ key, title, desc, best, sources, installed, installedFrom }],
// in the order their first result came
function merge(results) {
    var groups = [], at = {};
    (results || []).forEach(function (r) {
        if (r.source === "repo" && Pkgs.library(r.name)) return;
        var keys = _keys(r).filter(function (k) { return k; });
        var g = null;
        keys.forEach(function (k) { if (g === null && at[k] !== undefined) g = at[k]; });
        if (g === null) { g = groups.length; groups.push([]); }
        groups[g].push(r);
        keys.forEach(function (k) { at[k] = g; });
    });
    return groups.map(function (rs) {
        var sources = rs.slice().sort(function (a, b) {
            return _source[a.source] - _source[b.source] || (a.source === "aur" ? _aurRank(a.name) - _aurRank(b.name) : 0);
        });
        var best = sources[0];
        var fh = sources.filter(function (s) { return s.source === "flathub"; })[0];
        var inst = sources.filter(function (s) { return s.installed; })[0];
        return {
            key: best.source === "flathub" ? _norm(best.title) : _norm(best.name),
            title: fh ? fh.title : best.title || best.name,
            desc: best.desc || (fh ? fh.desc : ""),
            best: best,
            sources: sources,
            installed: !!inst,
            installedFrom: inst ? inst.source : ""
        };
    });
}

function _need(q) { return String(q || "").toLowerCase().trim().replace(/\s+/g, " "); }

// the apps bead suggests for a need ("screen recorder"), by package name
function needs(query, curated) { return ((curated && curated.needs) || {})[_need(query)] || []; }

function _names(app) { return app.sources.map(function (s) { return s.name; }); }

// curated answers to the need first (in the list's order), then the rest as they were
function order(apps, query, curated) {
    var n = needs(query, curated);
    function pos(a) {
        var best = -1;
        _names(a).forEach(function (x) { var i = n.indexOf(x); if (i >= 0 && (best < 0 || i < best)) best = i; });
        return best;
    }
    return apps.map(function (a, i) { return { a: a, p: pos(a), i: i }; })
        .sort(function (x, y) {
            if ((x.p < 0) !== (y.p < 0)) return x.p < 0 ? 1 : -1;
            return (x.p - y.p) || (x.i - y.i);
        })
        .map(function (x) { return x.a; });
}

function _curatedEntry(app, curated) {
    var names = _names(app), hit = null;
    ((curated && curated.categories) || []).forEach(function (c) {
        (c.apps || []).forEach(function (e) { if (!hit && (names.indexOf(e.name) >= 0 || (e.flatpak && names.indexOf(e.flatpak) >= 0))) hit = e; });
    });
    return hit;
}

// why it's here: bead's own line for a curated app, else its summary's first sentence
function reason(app, curated) {
    var e = _curatedEntry(app, curated);
    if (e && e.why) return e.why;
    return String(app.desc || "").split(/\.(\s|$)/)[0].trim();
}

function front(curated) { return (curated && curated.categories) || []; }

// bead-sysupdate's arguments to install one source of an app
function installArgs(s) { return ["install", s.source, s.name]; }

// "install obs" in the launcher → "obs"; anything else → ""
function launcherQuery(text) {
    var m = /^install\s+(.+)$/i.exec(String(text || "").trim());
    return m ? m[1].trim().replace(/\s+/g, " ") : "";
}

// ── an install's progress, from bead-sysupdate install's output ──
// phase: auth (the password) → download → (build, AUR) → install → done | failed
function installStart() { return { phase: "auth", n: 0, dl: 0, i: 0, pct: -1, error: "" }; }
function installStep(st, line) {
    var s = Object.assign({}, st), l = String(line || ""), m;
    if (/^@@done/.test(l)) { s.phase = "done"; return s; }
    if (/^@@fail/.test(l)) { s.phase = "failed"; return s; }
    if ((m = /^Packages \((\d+)\)/.exec(l))) { s.n = +m[1]; s.phase = "download"; return s; }
    if (/^\s*\S+-x86_64\s+downloading|^\s*\S+-any\s+downloading/.test(l)) { s.dl++; s.phase = "download"; return s; }
    if (/^(installing|upgrading|reinstalling|downgrading) \S+\.\.\.$|^\(\s*\d+\/\d+\) installing/.test(l)) { s.i++; s.phase = "install"; return s; }
    if (/^==> Making package:/.test(l)) { s.phase = "build"; return s; }
    if ((m = /^\s*Installing\b.*?(\d{1,3})%/.exec(l))) { s.pct = Math.min(100, +m[1]); s.phase = "download"; return s; }
    if ((m = /^(?:==> )?(?:error|ERROR|Error):\s*(.*)$/.exec(l))) { s.error = m[1]; return s; }
    return s;
}
// 0–1: flatpak's own percent; pacman's downloads are the first half, installs the second
function installFraction(st) {
    if (st.phase === "done") return 1;
    if (st.pct >= 0) return st.pct / 100;
    if (!st.n) return 0;
    // nothing downloaded (all cached, a rollback): installing is the whole bar
    if (!st.dl && st.phase === "install") return Math.min(1, st.i / st.n);
    return Math.min(1, (Math.min(st.dl, st.n) + Math.min(st.i, st.n)) / (2 * st.n));
}

// what to call it: a pick's own title, else the merged one
function title(app, curated) {
    var e = _curatedEntry(app, curated);
    return e && e.title ? e.title : app.title;
}

// editor's choice: bead's notes on a few picks, matched to the apps found
function editors(apps, curated) {
    var out = [];
    ((curated && curated.editors) || []).forEach(function (e) {
        var a = (apps || []).filter(function (x) { return _names(x).indexOf(e.name) >= 0; })[0];
        if (a) out.push({ app: a, note: e.note });
    });
    return out;
}

// ── an app's details sheet (bin/bead-appinfo's answer → what the sheet shows) ──
// info: { repo?: { url, license, version, size }, aur?: { name, url, votes,
// maintainer, updated }, flathub?: { id, description (HTML), homepage, vcs,
// bugtracker, developer, license } }; summary: the one line we already have
function _plain(html) {
    return String(html || "")
        .replace(/<li[^>]*>/gi, "\n• ").replace(/<\/li>/gi, "")
        .replace(/<\/p>\s*/gi, "\n\n").replace(/<br\s*\/?>/gi, "\n")
        .replace(/<[^>]+>/g, "")
        .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'")
        .replace(/[ \t]+/g, " ").replace(/\n /g, "\n").replace(/\n{3,}/g, "\n\n").trim();
}
var _code = /^https?:\/\/(www\.)?(github\.com|gitlab\.com|codeberg\.org|git\.sr\.ht|sr\.ht|bitbucket\.org|invent\.kde\.org|gitlab\.gnome\.org|gitlab\.freedesktop\.org)\//i;
function details(info, summary) {
    info = info || {};
    var r = info.repo || {}, a = info.aur || {}, f = info.flathub || {};
    var links = [], seen = {};
    function add(label, url) {
        if (!url) return;
        var k = String(url).replace(/\/+$/, "").toLowerCase();
        if (seen[k]) return;
        seen[k] = true;
        links.push({ label: label, url: url });
    }
    var home = f.homepage || r.url || a.url || "";
    if (home && _code.test(home)) add("Source code", home); else add("Website", home);
    add("Source code", f.vcs || ([r.url, a.url].filter(function (u) { return u && _code.test(u); })[0] || ""));
    add("Report a bug", f.bugtracker);
    if (f.id) add("Flathub", "https://flathub.org/apps/" + f.id);
    if (a.name) add("AUR page", "https://aur.archlinux.org/packages/" + a.name);
    var facts = [];
    function fact(label, value) { if (value !== undefined && value !== null && value !== "") facts.push({ label: label, value: String(value) }); }
    fact("Version", r.version || f.version || a.version);
    fact("License", r.license || f.license || a.license);
    if (r.size) fact("Size", Pkgs.size(r.size));
    if (a.name) { fact("Votes", a.votes); fact("Maintainer", a.maintainer || "none (orphaned)"); }
    if (a.updated) fact("Updated", new Date(a.updated * 1000).toLocaleDateString());
    return { description: _plain(f.description) || summary || "", links: links, facts: facts, developer: f.developer || "", screenshot: f.screenshot || "", icon: f.icon || "" };
}
