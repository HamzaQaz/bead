pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Installed apps (.desktop entries), fuzzy search, and how often each was
// launched from the launcher (saved to $XDG_STATE_HOME/bead/launcher.json) so
// the ones you use float up.
Singleton {
    id: root

    readonly property list<DesktopEntry> all: DesktopEntries.applications.values
        .filter(e => !e.noDisplay)
        .filter((e, i, a) => a.findIndex(x => x.id === e.id) === i)
    property var counts: ({})
    property var last: ({})   // app id -> when it was last launched

    // fuzzy score of query q against text t (both lower case); 0 = no match
    // The desktop entry for a window's app id / class. An app's own
    // StartupWMClass wins: a heuristic match by name can pick a different app
    // (class "orca" is the Orca IDE, not the Orca screen reader's icon).
    function entryFor(id: string): var {
        if (!id) return null;
        const l = id.toLowerCase();
        return DesktopEntries.applications.values.find(e => (e.startupClass ?? "").toLowerCase() === l)
            ?? DesktopEntries.heuristicLookup(id);
    }
    function iconFor(id: string): string {
        if (!id) return "";
        return iconPath(entryFor(id)?.icon || id.toLowerCase());
    }
    // an entry's Icon= value: a theme name, or (allowed by the spec) a file path
    function iconPath(icon: string): string {
        if (!icon) return "";
        if (icon.startsWith("/")) return "file://" + icon.split("/").map(encodeURIComponent).join("/");
        return Quickshell.iconPath(icon, true);
    }

    function score(q: string, t: string): real {
        if (!t) return 0;
        if (t === q) return 120;
        if (t.startsWith(q)) return 100 - Math.min(20, t.length - q.length);
        const words = t.split(/[\s\-_.]+/);
        if (words.some(w => w.startsWith(q))) return 80;
        // initials: "vsc" -> visual studio code
        if (q.length > 1 && words.map(w => w[0] ?? "").join("").startsWith(q)) return 75;
        const at = t.indexOf(q);
        if (at >= 0) return 60 - Math.min(15, at);
        // in-order subsequence, fewer gaps is better
        let i = 0, gaps = 0, last = -1;
        for (let k = 0; k < t.length && i < q.length; k++) {
            if (t[k] === q[i]) { if (last >= 0) gaps += k - last - 1; last = k; i++; }
        }
        if (i === q.length) return Math.max(5, 40 - gaps * 2);
        // a near miss, for speech ("course forge" is CurseForge): letters and
        // digits only, within a typo or two of the whole name or one word
        return 45 * Math.max(similar(q, t), ...words.map(w => similar(q, w)));
    }
    // 0-1: how alike two names are by edit distance (Damerau: a swap is one
    // edit), ignoring spaces and punctuation; under 0.75 counts as nothing
    function similar(a: string, b: string): real {
        a = a.replace(/[^a-z0-9]/g, ""); b = b.replace(/[^a-z0-9]/g, "");
        if (a.length < 4 || b.length < 4 || Math.abs(a.length - b.length) > 3) return 0;
        const d = [];
        for (let i = 0; i <= a.length; i++) { d.push([i]); for (let j = 1; j <= b.length; j++) d[i].push(i ? 0 : j); }
        for (let i = 1; i <= a.length; i++) for (let j = 1; j <= b.length; j++) {
            const cost = a[i - 1] === b[j - 1] ? 0 : 1;
            d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost);
            if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
        }
        const sim = 1 - d[a.length][b.length] / Math.max(a.length, b.length);
        return sim >= 0.75 ? sim : 0;
    }

    function search(query: string): list<var> {
        const q = query.trim().toLowerCase();
        const used = e => counts[e.id] ?? 0;
        if (!q) {
            // the five you opened last, then the rest by how often
            const recent = all.filter(e => last[e.id]).sort((a, b) => last[b.id] - last[a.id]).slice(0, 5);
            const rest = all.filter(e => !recent.includes(e)).sort((a, b) => used(b) - used(a) || a.name.localeCompare(b.name));
            return recent.concat(rest);
        }
        const out = [];
        for (const e of all) {
            const s = Math.max(
                score(q, e.name.toLowerCase()),
                0.75 * score(q, (e.genericName ?? "").toLowerCase()),
                0.7 * Math.max(0, ...(e.keywords ?? []).map(k => score(q, k.toLowerCase()))),
                0.5 * score(q, (e.id ?? "").toLowerCase()));
            if (s > 0) out.push({ e: e, s: s + Math.log2(1 + used(e)) * 6 });
        }
        return out.sort((a, b) => b.s - a.s).map(x => x.e);
    }

    function launch(e: DesktopEntry): void {
        used(e);
        e.execute();
    }
    // open it on workspace `ws` (Hyprland's exec rule), wherever you are now
    function launchOn(e: DesktopEntry, ws: int): void {
        used(e);
        const cmd = e.command.map(a => /^[\w@%+=:,./-]+$/.test(a) ? a : "'" + a.replace(/'/g, "'\\''") + "'").join(" ");
        Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.exec_cmd(${JSON.stringify(`[workspace ${ws}] ${cmd}`)})`]);
    }
    function used(e: DesktopEntry): void {
        const c = Object.assign({}, counts);
        c[e.id] = (c[e.id] ?? 0) + 1;
        counts = c;
        last = Object.assign({}, last, { [e.id]: Date.now() });
    }

    property bool loaded: false
    onCountsChanged: if (loaded) saveTimer.restart()
    onLastChanged: if (loaded) saveTimer.restart()
    Timer { id: saveTimer; interval: 500; onTriggered: store.setText(JSON.stringify({ counts: root.counts, last: root.last })) }
    FileView {
        id: store
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/bead/launcher.json"
        blockLoading: true
        printErrors: false
        atomicWrites: true
        onLoaded: { try { const d = JSON.parse(text()); root.counts = d.counts ?? {}; root.last = d.last ?? {}; } catch (e) {} root.loaded = true; }
        onLoadFailed: root.loaded = true
    }
}
