.pragma library

// Is a package real, and does it look safe? The repos are signed by Arch's
// packagers and Flathub reviews its apps; the AUR is anyone's uploads. So for
// the AUR bead reads its facts (bin/bead-pkgcheck asks the AUR's API) and its
// build files (PKGBUILD, .install) for patterns that malware has used. Not a
// guarantee: a heads-up before you build something. Tested in tests/tst_trust.qml.
//
// A result: { level: ok|caution|danger, reasons: [why not ok], notes: [fyi] }

const rank = { ok: 0, caution: 1, danger: 2 };
function worst(a, b) { return rank[b] > rank[a] ? b : a; }

// info: the AUR API's result (null: no such package); now: seconds
function aurRisk(info, now) {
    if (!info) return { level: "danger", reasons: ["It's not in the AUR (a typo, or removed)"], notes: [] };
    const reasons = [], notes = [];
    const age = Math.floor((now - (info.FirstSubmitted || now)) / 86400);
    const votes = info.NumVotes || 0;
    if (age < 30) reasons.push("Added " + age + (age === 1 ? " day ago" : " days ago"));
    if (votes < 5) reasons.push("Only " + votes + (votes === 1 ? " vote" : " votes"));
    if (!info.Maintainer) reasons.push("Nobody maintains it (orphaned)");
    if (info.OutOfDate) notes.push("Flagged out of date");
    if (votes >= 5) notes.push(votes + " votes");
    return { level: reasons.length ? "caution" : "ok", reasons: reasons, notes: notes };
}

// known-bad patterns in build files: [regex, level, what it means]
const patterns = [
    [/\b(curl|wget|fetch)\b[^\n|]*\|\s*(ba|z|da)?sh\b/, "danger", "Runs a script straight from the internet"],
    [/base64\s+(-d|--decode)|b64decode|\bxxd\s+-r/, "danger", "Decodes hidden code"],
    [/\beval\s+["'`]?\$\(/, "danger", "Runs generated code"],
    [/discord(app)?\.com\/api\/webhooks|api\.telegram\.org\/bot|\b(curl|wget)\b[^\n]*(-X\s*POST|--data|-d\s|--upload-file|-F\s)/, "danger", "Sends data somewhere"],
    // your own files: no package has a reason to touch them
    [/(~|\$HOME|\/home\/[^/\s]+)\/\.(bashrc|zshrc|profile|bash_profile|config\/autostart|ssh)/, "danger", "Changes your shell, startup or login files"],
    // the system's: a file shipped in the package ($pkgdir) is pacman's, visible
    // and removed with it; an install script writing there itself is not
    [/^(?!.*\$\{?pkgdir).*(\/etc\/(profile|bash\.bashrc|environment|ld\.so\.preload|sudoers)\b|\/etc\/cron|crontab\s)/, "danger", "Changes the system's startup or login files"],
    [/\$\{?pkgdir\}?["']?\/etc\/cron/, "caution", "Adds a scheduled job"],
    [/\b(nc|ncat|socat)\b[^\n]*\s-e\s|\/dev\/tcp\//, "danger", "Opens a remote shell"],
    // (Chromium's sandbox helper needs it: Chrome, Brave, Electron apps)
    [/^(?!.*chrome-sandbox).*(chmod\s+[0-7]*[4-7][0-7]{3}\b|chmod\s+[ug]\+s\b)/, "caution", "Makes a program run as root (setuid)"],
    [/https?:\/\/\d{1,3}(\.\d{1,3}){3}[:/]/, "caution", "Downloads from a bare IP address"],
    [/pastebin\.com|paste\.ee|hastebin|transfer\.sh|0x0\.st|ghostbin|termbin/, "caution", "Downloads from a paste or file-drop site"],
    [/systemctl\s+(--now\s+)?enable/, "caution", "Turns a service on by itself"]
];

// build file text → [{ level, what, line, text }]
function scan(text) {
    const out = [];
    String(text || "").split("\n").forEach((l, i) => {
        if (/^\s*#/.test(l)) return;
        for (const [re, level, what] of patterns)
            if (re.test(l)) { out.push({ level: level, what: what, line: i + 1, text: l.trim().slice(0, 160) }); break; }
    });
    return out;
}

// the AUR facts and the build file findings together
function verdict(risk, findings) {
    let level = risk.level;
    for (const f of findings || []) level = worst(level, f.level);
    const seen = {};
    const fromScan = (findings || []).filter(f => !seen[f.what] && (seen[f.what] = true)).map(f => f.what + " (line " + f.line + ")");
    return { level: level, reasons: risk.reasons.concat(fromScan), notes: risk.notes || [], findings: findings || [] };
}

// the repos and Flathub: fine when the package exists (signed, reviewed);
// a Flatpak not verified by its developer gets a note
function signed(source, exists, verified) {
    if (!exists) return { level: "danger", reasons: ["It isn't in " + (source === "repo" ? "the repos" : "Flathub")], notes: [] };
    if (source === "flathub" && verified === false) return { level: "ok", reasons: [], notes: ["Not verified by its developer"] };
    return { level: "ok", reasons: [], notes: [] };
}
