.pragma library

// `bead-doctor --tsv`: status \t need \t id \t what \t fix \t package per line.

function parse(text) {
    return String(text || "").split("\n").map(function (l) { return l.split("\t"); })
        .filter(function (f) { return f.length >= 6 && (f[0] === "ok" || f[0] === "missing"); })
        .map(function (f) { return { ok: f[0] === "ok", need: f[1], id: f[2], what: f[3], fix: f[4], pkg: f[5] }; });
}

// what's missing, core first (each group in the doctor's own order)
function problems(checks) {
    var bad = checks.filter(function (c) { return !c.ok; });
    return bad.filter(function (c) { return c.need === "core"; }).concat(bad.filter(function (c) { return c.need !== "core"; }));
}

// the packages that would fix what's missing (core only if asked), once each
function packages(checks, coreOnly) {
    var out = [];
    problems(checks).forEach(function (c) {
        if (c.pkg && (!coreOnly || c.need === "core") && out.indexOf(c.pkg) < 0) out.push(c.pkg);
    });
    return out;
}

function summary(checks) {
    var bad = problems(checks), core = bad.filter(function (c) { return c.need === "core"; }).length, rest = bad.length - core;
    if (core) return core + (core === 1 ? " thing bead needs is missing" : " things bead needs are missing");
    return rest ? "All set · " + rest + " optional extra" + (rest === 1 ? "" : "s") + " missing" : "All set";
}
