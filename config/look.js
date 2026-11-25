.pragma library
// Customisation (config/Look.qml, Settings → Customise): every option once,
// with its page, group, range and default. The Settings pages are drawn from
// this list, values are checked on the way in (from the file, a preset or a
// pasted look), and a look can be shared as text. Pure: tests/tst_look.qml.

var PAGES = [
    { id: "look", t: "Look & feel", g: "palette", d: "Accent, the frame, fonts and clock" },
    { id: "motion", t: "Motion", g: "animation", d: "How fast and springy things move" },
    { id: "island", t: "Island", g: "pill", d: "Each of the island's states" },
    { id: "popups", t: "Pop-ups", g: "notifications_active", d: "Notification pop-ups, timing and per-app rules" },
    { id: "bar", t: "Bar", g: "view_sidebar", d: "Which buttons show, and the pills" }
];

var SWATCHES = ["#2b7fff", "#8b5cf6", "#ec4899", "#ef4444", "#f97316", "#eab308", "#22c55e", "#14b8a6", "#e5e5e5"];
var APP_RULES = [
    { v: "normal", t: "Normal" }, { v: "corner", t: "Corner only" }, { v: "island", t: "Island only" },
    { v: "sticky", t: "Stays" }, { v: "quiet", t: "History only" }
];

function b(page, group, k, label, def, hint) { return { k: k, page: page, group: group, type: "bool", label: label, hint: hint || "", def: def }; }
function n(page, group, k, label, def, min, max, step, unit, hint) { return { k: k, page: page, group: group, type: "num", label: label, hint: hint || "", def: def, min: min, max: max, step: step, unit: unit || "" }; }
function c(page, group, k, label, def, choices, hint) { return { k: k, page: page, group: group, type: "choice", label: label, hint: hint || "", def: def, choices: choices }; }

var SCHEMA = [
    // ── look & feel ──
    { k: "accent", page: "look", group: "Colour", type: "color", label: "Accent colour", hint: "Buttons, rings and highlights; empty follows the wallpaper", def: "" },
    c("look", "Colour", "frameColor", "Frame colour", "theme", [{ v: "theme", t: "Theme" }, { v: "black", t: "Black" }, { v: "accent", t: "Accent tint" }], "The screen frame, the island and the pop-ups"),
    n("look", "Colour", "frameOpacity", "Frame opacity", 1, 0.5, 1, 0.05, "%", "Let the desktop show through the frame and island"),
    n("look", "Colour", "subtext", "Secondary text", 0.8, 0.4, 1, 0.05, "%", "How strong dimmer text is"),
    n("look", "Shape", "frameThickness", "Frame thickness", 10, 0, 24, 1, "px", "The border around the screen"),
    { k: "font", page: "look", group: "Text", type: "font", label: "Font", hint: "bead's text everywhere", def: "Inter" },
    b("look", "Text", "clock24", "24-hour clock", true, "The bar and the island"),

    // ── motion ──
    b("motion", "Animation", "motionOn", "Animations", true, "Off: things change at once"),
    n("motion", "Animation", "speed", "Speed", 1, 0.5, 2, 0.1, "×", "Higher is faster"),
    n("motion", "Animation", "bounce", "Bounce", 1, 0, 2, 0.1, "×", "0 settles without overshoot, 2 is extra springy"),
    b("motion", "Details", "ripple", "Colour ripple", true, "A new wallpaper's colours ripple out from the island"),
    b("motion", "Details", "trayPop", "Pinned apps pop in", true, "Pinning a tray app grows the bar's pill"),
    b("motion", "Details", "hoverGrow", "Buttons react to hover", true, "The bar's buttons lift a little under the pointer"),

    // ── island ──
    n("island", "Resting", "islandRestH", "Height", 34, 26, 44, 1, "px"),
    n("island", "Resting", "islandRestMinW", "Smallest width", 132, 80, 260, 2, "px"),
    n("island", "Resting", "islandRadius", "Roundness", 28, 0, 40, 1, "px", "Its corners, in every state"),
    n("island", "Resting", "islandGoo", "Melt into the frame", 16, 0, 32, 1, "px", "How softly it joins the top edge"),
    b("island", "Resting", "islandClock", "Clock", true),
    b("island", "Resting", "islandWeather", "Weather", true),
    b("island", "Resting", "islandMedia", "What's playing", true, "The cover and title while music plays"),
    b("island", "Resting", "islandLive", "Live activities", true, "Timers, Discord and running tasks (recording always shows)"),

    b("island", "Hover & dashboard", "islandHover", "Open on hover", true, "Else only by click or shortcut"),
    n("island", "Hover & dashboard", "islandHoverDelay", "Hover delay", 220, 0, 1000, 20, "ms"),
    n("island", "Hover & dashboard", "islandLeaveDelay", "Close delay", 300, 100, 2000, 50, "ms", "After the pointer leaves"),
    b("island", "Hover & dashboard", "islandHoverMedia", "Music card first", true, "While music plays, hovering shows the player"),
    n("island", "Hover & dashboard", "islandOpenW", "Dashboard width", 900, 860, 1100, 10, "px"),
    n("island", "Hover & dashboard", "islandOpenH", "Dashboard height", 340, 320, 460, 10, "px"),

    b("island", "Pop-ups on the island", "islandNotifs", "Notifications", true, "A glance at each new one"),
    n("island", "Pop-ups on the island", "islandNotifMs", "Notification time", 3500, 1500, 8000, 250, "ms"),
    n("island", "Pop-ups on the island", "islandNotifW", "Notification width", 400, 320, 560, 10, "px"),
    b("island", "Pop-ups on the island", "islandLevels", "Volume and brightness", true),
    n("island", "Pop-ups on the island", "islandLevelMs", "Level time", 1600, 800, 4000, 100, "ms"),
    n("island", "Pop-ups on the island", "islandLevelW", "Level width", 330, 240, 440, 10, "px"),
    b("island", "Pop-ups on the island", "islandWorkspaces", "Workspace switches", true),
    n("island", "Pop-ups on the island", "islandToastScale", "Toast time", 1, 0.5, 3, 0.1, "×", "Caps Lock, copied links, finished tasks"),
    b("island", "Pop-ups on the island", "islandMediaPeek", "New song", true, "Peek at the track when it changes"),
    n("island", "Pop-ups on the island", "islandMediaPeekMs", "New song time", 5000, 2000, 10000, 250, "ms"),

    b("island", "Music glow", "islandGlow", "Glow", true, "A halo in the cover's colour while music plays"),
    n("island", "Music glow", "islandGlowStrength", "Glow strength", 0.32, 0.05, 0.7, 0.01, "%"),

    // ── pop-ups ──
    b("popups", "Where", "popCorner", "Corner pop-ups", true, "Off: notifications only peek on the island"),
    c("popups", "Where", "popScreen", "Screen", "island", [{ v: "island", t: "Island's" }, { v: "focused", t: "Focused" }], "Which monitor they appear on"),
    n("popups", "Size & shape", "popWidth", "Width", 350, 280, 520, 10, "px"),
    n("popups", "Size & shape", "popRadius", "Roundness", 16, 4, 28, 1, "px"),
    n("popups", "Size & shape", "popGoo", "Melt together", 20, 0, 40, 1, "px", "How stacked pop-ups blend into one shape"),
    n("popups", "Size & shape", "popGap", "Gap", 6, 0, 20, 1, "px"),
    n("popups", "Timing", "popMs", "How long they stay", 6000, 2000, 20000, 500, "ms"),
    b("popups", "Timing", "popRespectApp", "Apps choose their own time", true, "Use the time an app asks for, when it does"),
    b("popups", "Timing", "popCriticalSticky", "Urgent ones stay", true, "Until you dismiss them"),
    b("popups", "Timing", "popAutoExpand", "Open the text by itself", true, "Else on hover"),
    n("popups", "Timing", "popExpandDelay", "Open the text after", 700, 0, 3000, 100, "ms"),
    n("popups", "Stacking", "popMax", "At most on screen", 4, 1, 8, 1, ""),
    b("popups", "Stacking", "popMerge", "Combine an app's", true, "A new one from the same app takes the last one's place"),
    b("popups", "Stacking", "popFullscreenDots", "Dots while fullscreen", true, "Games and videos get a dot, not a pop-up"),
    b("popups", "Content", "popImages", "Pictures and icons", true),
    b("popups", "Content", "popActions", "App buttons", true, "Reply, Mark read…"),
    b("popups", "Content", "popLater", "Later button", true, "Snooze one to come back"),
    b("popups", "Content", "popSound", "Sound", false, "A short chime with each one"),
    c("popups", "Content", "popSoundName", "Which sound", "message", [{ v: "message", t: "Message" }, { v: "bell", t: "Bell" }, { v: "complete", t: "Chime" }]),
    { k: "popApps", page: "popups", group: "Per app", type: "apps", label: "Per-app rules", hint: "How each app's notifications show", def: {} },

    // ── bar ──
    b("bar", "Buttons", "barUtils", "Utilities", true),
    b("bar", "Buttons", "barUpdates", "Updates", true, "While updates are waiting"),
    b("bar", "Buttons", "barDiscord", "Discord", true, "While it's connected"),
    b("bar", "Buttons", "barMessages", "Messages", true, "WhatsApp / Telegram, when on"),
    b("bar", "Buttons", "barTray", "Tray apps", true),
    b("bar", "Buttons", "barClock", "Clock", true),
    b("bar", "Buttons", "barSound", "Sound", true),
    b("bar", "Buttons", "barBattery", "Device batteries", true),
    b("bar", "Buttons", "barWifi", "Wi-Fi", true),
    b("bar", "Buttons", "barBluetooth", "Bluetooth", true),
    b("bar", "Buttons", "barPower", "Power", true),
    n("bar", "Pills", "barPillOpacity", "Pill shading", 0.05, 0, 0.2, 0.01, "%", "The faint backing behind each group"),
    n("bar", "Pills", "barGap", "Space between pills", 6, 0, 20, 1, "px")
];

var PRESETS = [
    { id: "bead", name: "bead", d: "The defaults", values: {} },
    { id: "minimal", name: "Minimal", d: "Quiet, flat and small", values: {
        bounce: 0, islandGlow: false, islandGoo: 8, islandRadius: 18, islandWeather: false, islandMediaPeek: false,
        frameThickness: 6, popGoo: 8, popMax: 2, popLater: false, barPillOpacity: 0, ripple: false } },
    { id: "showcase", name: "Showcase", d: "Big, glowing and springy", values: {
        bounce: 1.6, speed: 0.9, islandGlowStrength: 0.55, islandGoo: 24, islandRadius: 34, popGoo: 30,
        frameThickness: 12, islandRestH: 38, popRadius: 22 } },
    { id: "calm", name: "Calm", d: "Slow, gentle, fewer interruptions", values: {
        speed: 0.7, bounce: 0.3, islandHoverDelay: 460, popMs: 9000, islandNotifs: false, popAutoExpand: false, islandMediaPeek: false } },
    { id: "snappy", name: "Snappy", d: "Fast and responsive", values: {
        speed: 1.6, bounce: 0.5, islandHoverDelay: 80, islandLeaveDelay: 150, popExpandDelay: 200, islandLevelMs: 1000 } },
    { id: "focus", name: "Focus", d: "One pop-up at a time, nothing extra", values: {
        popMax: 1, popMs: 3000, islandNotifs: false, islandWorkspaces: false, islandMediaPeek: false, islandLive: false,
        barDiscord: false, barMessages: false } }
];

var _byKey = {};
SCHEMA.forEach(function (o) { _byKey[o.k] = o; });
function entry(k) { return _byKey[k] || null; }

// a value for an option, or its default when it doesn't fit
function clean(o, v) {
    switch (o.type) {
    case "bool": return typeof v === "boolean" ? v : o.def;
    case "num": {
        if (typeof v !== "number" || !isFinite(v)) return o.def;
        var x = Math.min(o.max, Math.max(o.min, v));
        x = o.min + Math.round((x - o.min) / o.step) * o.step;
        x = Math.min(o.max, x);
        return Math.round(x * 1e6) / 1e6;
    }
    case "choice": return o.choices.some(function (ch) { return ch.v === v; }) ? v : o.def;
    case "color": return typeof v === "string" && /^(#[0-9a-fA-F]{6})?$/.test(v) ? v.toLowerCase() : o.def;
    case "font": return typeof v === "string" && v.trim() && v.length <= 64 && !/[<>"\\]/.test(v) ? v.trim() : o.def;
    case "apps": {
        var out = {};
        if (!v || typeof v !== "object" || Array.isArray(v)) return out;
        for (var a in v) if (a && a.length <= 80 && APP_RULES.some(function (r) { return r.v === v[a]; }) && v[a] !== "normal") out[a] = v[a];
        return out;
    }
    }
    return o.def;
}

function _same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }

// stored (only changes, or anything) → every option, checked
function load(obj) {
    var v = {};
    obj = obj && typeof obj === "object" ? obj : {};
    SCHEMA.forEach(function (o) { v[o.k] = o.k in obj ? clean(o, obj[o.k]) : (typeof o.def === "object" ? {} : o.def); });
    return v;
}
function set(values, k, x) {
    var o = entry(k);
    if (!o) return values;
    var v = Object.assign({}, values);
    v[k] = clean(o, x);
    return v;
}
// the keys that differ from the defaults (on one page, or all)
function changed(values, page) {
    return SCHEMA.filter(function (o) { return (!page || o.page === page) && !_same(values[o.k], o.def); }).map(function (o) { return o.k; });
}
function diff(values) {
    var d = {};
    changed(values).forEach(function (k) { d[k] = values[k]; });
    return d;
}
function resetPage(values, page) {
    var v = Object.assign({}, values);
    SCHEMA.forEach(function (o) { if (o.page === page) v[o.k] = typeof o.def === "object" ? {} : o.def; });
    return v;
}

// a preset (built-in id, or a saved one by name) as full values; null if none
function preset(id, saved) {
    var p = PRESETS.filter(function (x) { return x.id === id; })[0];
    if (p) return load(p.values);
    if (saved && saved[id]) return load(saved[id]);
    return null;
}
// which preset these values are exactly ("" for none)
function matching(values, saved) {
    var mine = diff(values);
    for (var i = 0; i < PRESETS.length; i++) if (_same(diff(load(PRESETS[i].values)), mine)) return PRESETS[i].id;
    for (var name in saved || {}) if (_same(diff(load(saved[name])), mine)) return name;
    return "";
}

// ── sharing ──
function exportText(values, name) {
    return JSON.stringify({ bead: "look", version: 1, name: name || "My look", values: diff(values) }, null, 2);
}
function importText(text) {
    var o;
    try { o = JSON.parse(String(text || "").trim()); } catch (e) { return { ok: false, error: "That isn't a bead look (not JSON)" }; }
    if (!o || o.bead !== "look" || typeof o.values !== "object") return { ok: false, error: "That isn't a bead look" };
    var name = typeof o.name === "string" && o.name.trim() ? o.name.trim().slice(0, 40) : "Imported look";
    return { ok: true, name: name, values: load(o.values) };
}

// ── motion ──
// the spring with its overshoot scaled: 0 is the settle curve, 1 sileo's, 2 twice the overshoot
function blend(spring, settle, bounce) { return settle + (spring - settle) * bounce; }
function duration(ms, v) { return v.motionOn === false ? 1 : Math.max(1, Math.round(ms / (v.speed || 1))); }

// ── searching settings ──
function search(q) {
    var words = String(q || "").toLowerCase().split(/\s+/).filter(Boolean);
    if (!words.length) return [];
    return SCHEMA.filter(function (o) {
        var hay = (o.label + " " + o.hint + " " + o.group + " " + o.k).toLowerCase();
        return words.every(function (w) { return hay.indexOf(w) >= 0; });
    });
}
