.pragma library
// Widgets (services/Widgets.qml, Settings → Widgets): something you keep an eye
// on, made from a template. Each template turns its few fields into a command
// (an argv list, so nothing you type is run through a shell unless the
// template is a command) and reads that command's output back into what's
// shown: { value, icon, tone, progress }. Pure: tests/tst_widgets.qml.

var MAX_PINNED = 4;
var TONES = ["", "success", "warning", "error"];

// the templates, in the order Settings offers them
var TEMPLATES = [
    { id: "server", name: "Server up", icon: "dns", every: 30,
      hint: "A host to ping, or a URL to load.",
      fields: [{ key: "target", label: "Host or URL", placeholder: "192.0.2.10 or https://example.com" }] },
    { id: "number", name: "Number from a URL", icon: "tag", every: 60,
      hint: "Loads JSON from the URL and shows one field of it.",
      fields: [{ key: "url", label: "URL", placeholder: "https://api.example.com/status" },
               { key: "path", label: "Field", placeholder: "players.online" },
               { key: "unit", label: "After the number", placeholder: "players", optional: true }] },
    { id: "github", name: "GitHub", icon: "rocket_launch", every: 120,
      hint: "Uses your gh login.",
      fields: [{ key: "repo", label: "Repository", placeholder: "owner/name" },
               { key: "show", label: "Show", choices: [{ v: "ci", t: "Last CI run" }, { v: "prs", t: "Open pull requests" }, { v: "release", t: "Latest release" }] }] },
    { id: "toggle", name: "Toggle", icon: "toggle_on", every: 30,
      hint: "It's on while the check command succeeds. A click runs the other command.",
      fields: [{ key: "check", label: "Is it on? (command)", placeholder: "systemctl is-active --quiet wg-quick@wg0" },
               { key: "on", label: "Turn on", placeholder: "systemctl start wg-quick@wg0" },
               { key: "off", label: "Turn off", placeholder: "systemctl stop wg-quick@wg0" }] },
    { id: "command", name: "Command", icon: "terminal", every: 60,
      hint: "Shows the first line it prints, or JSON with value, icon, tone and progress.",
      fields: [{ key: "cmd", label: "Command", placeholder: "uptime -p" }] }
];

function template(id) {
    for (var i = 0; i < TEMPLATES.length; i++) if (TEMPLATES[i].id === id) return TEMPLATES[i];
    return null;
}

function _str(x, max) { return typeof x === "string" ? x.trim().slice(0, max || 400) : ""; }

// a widget from the file, checked: unknown templates and missing fields drop it
function clean(w) {
    if (!w || typeof w !== "object") return null;
    var t = template(w.template);
    var id = _str(w.id, 40);
    if (!t || !id) return null;
    var f = {};
    var src = w.fields && typeof w.fields === "object" ? w.fields : {};
    for (var i = 0; i < t.fields.length; i++) {
        var d = t.fields[i];
        var v = _str(src[d.key]);
        if (d.choices) { var ok = d.choices.some(function (c) { return c.v === v; }); v = ok ? v : d.choices[0].v; }
        if (!v && !d.optional) return null;
        f[d.key] = v;
    }
    var every = Math.round(Number(w.every));
    return {
        id: id, template: t.id, fields: f,
        label: _str(w.label, 40) || t.name,
        icon: _str(w.icon, 40) || t.icon,
        every: Number.isFinite(every) && every >= 5 ? Math.min(every, 86400) : t.every,
        pinned: w.pinned === true
    };
}
function cleanAll(list) {
    var out = [], seen = {};
    (Array.isArray(list) ? list : []).forEach(function (w) {
        var c = clean(w);
        if (c && !seen[c.id]) { seen[c.id] = true; out.push(c); }
    });
    return out;
}
// a new widget's id: the template plus a number not taken yet
function newId(templateId, list) {
    var n = 1;
    var taken = (list || []).map(function (w) { return w.id; });
    while (taken.indexOf(templateId + "-" + n) >= 0) n++;
    return templateId + "-" + n;
}

function _isUrl(s) { return /^https?:\/\//i.test(s); }

// what to run, as argv
function command(w) {
    var f = w.fields;
    switch (w.template) {
    case "server":
        return _isUrl(f.target)
            ? ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code} %{time_total}", "--max-time", "4", "--", f.target]
            : ["ping", "-c", "1", "-W", "2", "--", f.target];
    case "number":
        return ["curl", "-sfL", "--max-time", "4", "--", f.url];
    case "github":
        if (f.show === "prs") return ["gh", "pr", "list", "-R", f.repo, "--state", "open", "--json", "number", "-L", "100"];
        if (f.show === "release") return ["gh", "release", "view", "-R", f.repo, "--json", "tagName,publishedAt"];
        return ["gh", "run", "list", "-R", f.repo, "-L", "1", "--json", "status,conclusion,workflowName"];
    case "toggle":
        return ["sh", "-c", f.check];
    case "command":
        return ["sh", "-c", f.cmd];
    }
    return null;
}
// what a click runs (only toggles have one); `on` is what it shows now
function action(w, on) {
    if (w.template !== "toggle") return null;
    return ["sh", "-c", on ? w.fields.off : w.fields.on];
}

function _get(o, path) {
    var parts = path.split(".");
    for (var i = 0; i < parts.length; i++) {
        if (o === null || o === undefined) return undefined;
        var k = parts[i];
        o = Array.isArray(o) && /^\d+$/.test(k) ? o[Number(k)] : o[k];
    }
    return o;
}
function _num(x) {
    if (typeof x !== "number" || !Number.isFinite(x)) return String(x);
    if (Math.abs(x) < 1000) return String(Math.round(x * 100) / 100);
    return String(Math.round(x)).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}
function _line(s) { return String(s || "").split("\n").map(function (l) { return l.trim(); }).filter(function (l) { return l; })[0] || ""; }

// a command's output, read: { value, tone, icon?, progress?, on? }
function parse(w, out, code) {
    var f = w.fields;
    out = String(out || "");
    switch (w.template) {
    case "server":
        if (_isUrl(f.target)) {
            var m = /^(\d{3}) ([\d.]+)/.exec(out.trim());
            if (!m || m[1] === "000") return { value: "down", tone: "error" };
            var ms = Math.round(parseFloat(m[2]) * 1000);
            var c = Number(m[1]);
            return c < 400 ? { value: "up · " + ms + " ms", tone: "success" } : { value: "HTTP " + c, tone: "warning" };
        }
        if (code !== 0) return { value: "down", tone: "error" };
        var t = /time[=<]([\d.]+) ?ms/.exec(out);
        return { value: t ? "up · " + Math.round(parseFloat(t[1])) + " ms" : "up", tone: "success" };
    case "number":
        if (code !== 0) return { value: "no answer", tone: "warning" };
        var j;
        try { j = JSON.parse(out); } catch (e) { return { value: "not JSON", tone: "warning" }; }
        var v = _get(j, f.path);
        if (v === undefined || v === null || typeof v === "object") return { value: "no " + f.path, tone: "warning" };
        return { value: _num(v) + (f.unit ? " " + f.unit : ""), tone: "" };
    case "github":
        if (code !== 0) return { value: "gh failed", tone: "warning" };
        var g;
        try { g = JSON.parse(out); } catch (e) { return { value: "gh failed", tone: "warning" }; }
        if (f.show === "prs") { var n = Array.isArray(g) ? g.length : 0; return { value: n === 1 ? "1 PR" : n + " PRs", tone: "" }; }
        if (f.show === "release") return g && g.tagName ? { value: g.tagName, tone: "" } : { value: "none", tone: "" };
        var r = Array.isArray(g) ? g[0] : null;
        if (!r) return { value: "no runs", tone: "" };
        if (r.status !== "completed") return { value: "running", tone: "", progress: -1 };
        if (r.conclusion === "success") return { value: "passing", tone: "success" };
        if (r.conclusion === "cancelled" || r.conclusion === "skipped") return { value: r.conclusion, tone: "" };
        return { value: "failing", tone: "error" };
    case "toggle":
        return code === 0 ? { value: "on", tone: "success", on: true } : { value: "off", tone: "", on: false };
    case "command":
        var s = out.trim();
        if (s.charAt(0) === "{") {
            try {
                var o = JSON.parse(s);
                var res = { value: o.value === undefined ? "" : String(o.value), tone: TONES.indexOf(o.tone) >= 0 ? o.tone : "" };
                if (typeof o.icon === "string" && o.icon) res.icon = o.icon;
                if (typeof o.progress === "number") res.progress = Math.max(-1, Math.min(1, o.progress));
                return res;
            } catch (e) {}
        }
        var line = _line(s);
        if (code !== 0) return { value: line || "failed (" + code + ")", tone: "error" };
        return { value: line || "—", tone: "" };
    }
    return { value: "", tone: "" };
}

// the island's chips: the pinned ones, at most MAX_PINNED, and how many more
function chips(list) {
    var p = (list || []).filter(function (w) { return w.pinned; });
    return { shown: p.slice(0, MAX_PINNED), more: Math.max(0, p.length - MAX_PINNED) };
}
