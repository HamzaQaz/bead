.pragma library

// Reading a system update's output (bin/bead-sysupdate, shown by the island's
// UpdateView): stages, the package being worked on, overall progress and
// errors. Tested in tests/tst_sysupdate.qml.

// one line → { kind: stage|step|download|build|error|log, ... }
function parse(line) {
    const l = line || "";
    let m;
    if ((m = /^@@stage (\w+)/.exec(l))) return { kind: "stage", stage: m[1] };
    // pacman: "( 3/12) upgrading firefox   [----]" (its "checking …" steps aren't packages)
    if ((m = /^\(\s*(\d+)\/(\d+)\)\s+(upgrading|installing|reinstalling|downgrading|removing)\s+(\S+)/.exec(l)))
        return { kind: "step", i: +m[1], n: +m[2], verb: m[3], name: m[4] };
    // the same through a pipe: "upgrading firefox..." (no counter: i = 0, n = 0)
    if ((m = /^(upgrading|installing|reinstalling|downgrading|removing) (\S+)\.\.\.$/.exec(l)))
        return { kind: "step", i: 0, n: 0, verb: m[1], name: m[2] };
    // flatpak: " 2/5… org.mozilla.firefox stable u flathub 120.3 MB"
    if ((m = /^\s*(?:Updating\s+)?(\d+)\/(\d+)…?\s+([A-Za-z][\w-]*(?:\.[\w-]+){2,})/.exec(l)))
        return { kind: "step", i: +m[1], n: +m[2], verb: "updating", name: m[3] };
    if ((m = /^\s*(\S+?)-[^-\s]+-[^-\s]+-(?:x86_64|any|i686|aarch64)\s+downloading/.exec(l)))
        return { kind: "download", name: m[1] };
    if ((m = /^==> Making package: (\S+)/.exec(l))) return { kind: "build", name: m[1] };
    if (/^error:|^==> ERROR:|^error: |Request dismissed|Not authorized|^Error:/.test(l)) return { kind: "error", text: l.replace(/^(==> )?(error|ERROR|Error):\s*/, "") };
    return { kind: "log" };
}

const order = ["repo", "aur", "flatpak"];

// overall 0–1: each stage weighted by its listed packages; within one, i of n
// (capped: pacman counts dependencies too)
function progress(counts, stage, i, n) {
    const total = order.reduce((a, s) => a + (counts[s] || 0), 0);
    if (total === 0 || stage === "done") return 1;
    const at = order.indexOf(stage);
    if (at < 0) return 0;
    const before = order.slice(0, at).reduce((a, s) => a + (counts[s] || 0), 0);
    const here = counts[stage] || 0;
    const within = n > 0 ? Math.min(here, here * i / n) : 0;
    return (before + within) / total;
}

// a package's friendly name: "org.mozilla.firefox" → "firefox",
// "visual-studio-code-bin" → "visual studio code"
function pretty(name) {
    let n = name || "";
    if (/^[\w-]+(\.[\w-]+){2,}$/.test(n)) n = n.split(".").pop();
    return n.replace(/-(bin|git|stable)$/, "").replace(/[-_]+/g, " ");
}
