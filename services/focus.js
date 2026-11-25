.pragma library
// Focus modes (services/Focus.qml, Settings → Focus modes): a mode is a set of
// changes made together (a look preset, Do Not Disturb with some apps let
// through, night light, a wallpaper), turned on by hand, on a schedule, or
// while an app is open. Pure: tests/tst_focus.qml.

var ICONS = ["work", "sports_esports", "bedtime", "menu_book", "code", "brush", "headphones", "self_improvement", "school", "videocam"];
var DAYS = [{ v: 1, t: "M" }, { v: 2, t: "T" }, { v: 3, t: "W" }, { v: 4, t: "T" }, { v: 5, t: "F" }, { v: 6, t: "S" }, { v: 0, t: "S" }];

var DEFAULTS = [
    { id: "work", name: "Work", icon: "work", preset: "focus", dnd: true, allow: [],
      schedule: { on: false, days: [1, 2, 3, 4, 5], from: "09:00", to: "17:00" } },
    { id: "game", name: "Game", icon: "sports_esports", preset: "minimal", dnd: true, allow: ["discord"], apps: ["steam_app_*"] },
    { id: "night", name: "Night", icon: "bedtime", preset: "calm", nightLight: "on",
      schedule: { on: false, days: [0, 1, 2, 3, 4, 5, 6], from: "22:00", to: "07:00" } }
];

function _time(t, def) { return typeof t === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(t) ? t : def; }
function _strings(a, max) {
    return Array.isArray(a) ? a.filter(function (x) { return typeof x === "string" && x.trim() && x.length <= (max || 80); }).map(function (x) { return x.trim(); }) : [];
}

// a mode, checked (null if it isn't one)
function clean(m) {
    if (!m || typeof m !== "object") return null;
    var id = typeof m.id === "string" ? m.id.replace(/[^a-z0-9_-]/gi, "").slice(0, 32) : "";
    var name = typeof m.name === "string" ? m.name.trim().slice(0, 32) : "";
    if (!id || !name) return null;
    var s = m.schedule && typeof m.schedule === "object" ? m.schedule : {};
    var days = Array.isArray(s.days) ? s.days.filter(function (d) { return d === Math.floor(d) && d >= 0 && d <= 6; }) : [];
    var wp = m.wallpaper && typeof m.wallpaper === "object" && (typeof m.wallpaper.path === "string" || typeof m.wallpaper.id === "string")
        ? (m.wallpaper.id ? { id: String(m.wallpaper.id) } : { path: String(m.wallpaper.path) }) : null;
    return {
        id: id, name: name,
        icon: ICONS.indexOf(m.icon) >= 0 ? m.icon : "self_improvement",
        preset: typeof m.preset === "string" ? m.preset.slice(0, 40) : "",
        dnd: m.dnd === true,
        allow: _strings(m.allow),
        nightLight: m.nightLight === "on" || m.nightLight === "off" ? m.nightLight : "",
        wallpaper: wp,
        schedule: { on: s.on === true, days: days, from: _time(s.from, "09:00"), to: _time(s.to, "17:00") },
        apps: _strings(m.apps, 120)
    };
}
function cleanAll(list) {
    var out = [], seen = {};
    (Array.isArray(list) ? list : []).forEach(function (m) {
        var c = clean(m);
        if (c && !seen[c.id]) { seen[c.id] = true; out.push(c); }
    });
    return out;
}
// an id for a new mode named this
function newId(name, modes) {
    var base = String(name || "mode").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "mode", id = base, i = 2;
    while (modes.some(function (m) { return m.id === id; })) id = base + "-" + i++;
    return id;
}

function _min(t) { var p = t.split(":"); return +p[0] * 60 + +p[1]; }
// is a schedule on at this moment? (one past midnight belongs to the day it starts)
function inSchedule(s, date) {
    if (!s || !s.on) return false;
    var now = date.getHours() * 60 + date.getMinutes(), from = _min(s.from), to = _min(s.to), day = date.getDay();
    if (from === to) return false;
    if (from < to) return s.days.indexOf(day) >= 0 && now >= from && now < to;
    if (now >= from) return s.days.indexOf(day) >= 0;
    return now < to && s.days.indexOf((day + 6) % 7) >= 0;
}

// window classes against a mode's apps ("steam_app_*"; the whole name, any case)
function appMatches(patterns, classes) {
    return patterns.some(function (p) {
        var re = new RegExp("^" + p.toLowerCase().replace(/[.+?^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*") + "$");
        return classes.some(function (c) { return re.test(String(c).toLowerCase()); });
    });
}

// the mode that should be on by itself: an open app first, then a schedule (in order); "" none
function auto(modes, date, classes) {
    for (var i = 0; i < modes.length; i++) if (modes[i].apps.length && appMatches(modes[i].apps, classes)) return modes[i].id;
    for (var j = 0; j < modes.length; j++) if (inSchedule(modes[j].schedule, date)) return modes[j].id;
    return "";
}

// your choice (manual: a mode's id, "off", or null) holds until the automatic
// answer changes; then it's dropped and the automatic one applies
function resolve(st, autoNow) {
    var manual = st.manual;
    if (autoNow !== st.lastAuto) manual = null;
    var active = manual === null || manual === undefined ? autoNow : manual === "off" ? "" : manual;
    return { active: active, manual: manual === undefined ? null : manual, lastAuto: autoNow };
}

// Do Not Disturb in this mode: does this app's notification get through?
function letsThrough(m, app) {
    if (!m) return false;
    var a = String(app || "").toLowerCase();
    return m.allow.some(function (x) { return x.toLowerCase() === a; });
}

// what a mode does, in words (presetNames: id → name)
function summary(m, presetNames) {
    var out = [];
    if (m.preset) out.push((presetNames[m.preset] || m.preset) + " look");
    if (m.dnd) out.push("Do Not Disturb" + (m.allow.length ? " (" + m.allow.slice(0, 2).join(", ") + (m.allow.length > 2 ? " +" + (m.allow.length - 2) : "") + " get" + (m.allow.length === 1 ? "s" : "") + " through)" : ""));
    if (m.nightLight) out.push("Night light " + m.nightLight);
    if (m.wallpaper) out.push("its wallpaper");
    return out.length ? out.join(" · ") : "Changes nothing yet";
}

// when it turns on by itself, in words
function when(m) {
    var out = [];
    if (m.schedule.on && m.schedule.days.length) {
        var d = m.schedule.days.length === 7 ? "Every day" : JSON.stringify(m.schedule.days.slice().sort()) === "[1,2,3,4,5]" ? "Weekdays"
            : JSON.stringify(m.schedule.days.slice().sort()) === "[0,6]" ? "Weekends"
            : DAYS.filter(function (x) { return m.schedule.days.indexOf(x.v) >= 0; }).map(function (x) { return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][x.v]; }).join(", ");
        out.push(d + " " + m.schedule.from + "–" + m.schedule.to);
    }
    if (m.apps.length) out.push("while " + m.apps.slice(0, 2).join(", ") + (m.apps.length > 2 ? "…" : "") + " is open");
    return out.join(" · ");
}
