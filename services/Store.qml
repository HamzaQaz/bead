pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import "store.js" as S
import "pkgs.js" as Pkgs
import "trust.js" as T

// The App Store (modules/store/StoreWindow.qml): search the repos, Flathub and
// the AUR as one list of apps (services/Packages.qml searches; store.js
// merges, the repos preferred), need-based search and a store front from
// bead's picks (data/apps.json), and installing on the island's update card
// (Updates.installApp → bead-sysupdate install).
Singleton {
    id: root

    property bool open: false
    signal showApp(var app)   // the window opens its details sheet
    signal scrollBy(real px)  // the window scrolls (smoothly) by this much
    property string query: ""
    function show(q: string): void {
        open = true;
        search(q ?? "");
    }
    // typing: wait for a pause, then search once (clearing is at once)
    property string pending: ""
    function search(q: string): void {
        pending = q ?? "";
        if (pending.trim().length < 2) { typing.stop(); run(); }
        else typing.restart();
    }
    Timer { id: typing; interval: 140; onTriggered: root.run() }
    function run(): void {
        if (pending === query) return;
        query = pending;
        Packages.search(query);
        lookupNeeds();
    }

    // ── bead's picks ──
    property var curated: ({ categories: [], needs: {} })
    FileView {
        id: appsFile
        path: Paths.share + "/data/apps.json"
        watchChanges: true
        onFileChanged: reload()
        printErrors: false
        onLoaded: { try { root.curated = JSON.parse(text()); root.lookupFront(); } catch (e) {} }
    }
    // every pick, as one list (the parsed JSON comes back as a QML list: no flatMap)
    function picks(): var { const out = []; for (const c of Array.from(curated.categories ?? [])) for (const a of Array.from(c.apps ?? [])) out.push(a); return out; }
    // a pick's results: the repo's package if it's there, else Flathub, else the AUR
    property var frontHits: []
    property var needHits: []
    function lookup(names: var, cb: var): void {
        if (!names.length) { cb([]); return; }
        const p = lookupProc.createObject(root, { cb: cb, names: names, command: ["expac", "-S", "%r\t%n\t%v\t%m\t%d", ...names] });
        p.running = true;
    }
    Component {
        id: lookupProc
        Process {
            id: lp
            property var cb
            property var names: []
            stdout: StdioCollector {
                onStreamFinished: {
                    const repo = Pkgs.parseRepo(text, Packages.packages);
                    lp.cb(repo);
                    lp.destroy();
                }
            }
        }
    }
    // picks the repos lack: their Flatpak (from the cached Flathub list), else the AUR
    function fill(names: var, repo: var): var {
        const out = [...repo];
        const entries = picks();
        for (const n of names) {
            if (repo.some(r => r.name === n)) continue;
            const e = entries.find(x => x.name === n);
            const fp = e?.flatpak ? Packages.catalog.find(a => a.id === e.flatpak) : null;
            if (fp) out.push({ source: "flathub", name: fp.id, title: fp.title, version: fp.version, desc: fp.desc, installed: Packages.flatpaks.includes(fp.id) });
            else out.push({ source: "aur", name: n, title: e?.title || n, desc: e?.why || "", installed: Packages.packages.includes(n) });
        }
        return out;
    }
    function lookupFront(): void {
        const names = picks().map(a => a.name);
        lookup(names, repo => root.frontHits = root.fill(names, repo));
    }
    // only the newest lookup may land (an older, slower one would bring back stale picks)
    property int needSeq: 0
    function lookupNeeds(): void {
        const names = S.needs(query, curated);
        const seq = ++needSeq;
        needHits = [];
        lookup(names, repo => { if (seq === root.needSeq) root.needHits = root.fill(names, repo); });
    }

    // ── what the window shows ──
    // the store front: each category's picks, as apps
    readonly property var frontApps: S.merge(frontHits.map(r => Object.assign({}, r, { installed: r.source === "flathub" ? Packages.flatpaks.includes(r.name) : Packages.packages.includes(r.name) })))
    // editor's choice: bead's notes on a few picks ({ app, note })
    readonly property var editors: S.editors(frontApps, curated)
    readonly property var front: {
        const apps = frontApps;
        return S.front(curated).map(c => ({
            id: c.id, title: c.title, icon: c.icon,
            apps: Array.from(c.apps).map(e => apps.find(a => a.sources.some(s => s.name === e.name || s.name === e.flatpak))).filter(Boolean)
        }));
    }
    readonly property bool searching: Packages.searching
    // what the list shows: worked out once per burst of changes (repo, Flathub, AUR
    // and the picks land at different moments), not once per change
    readonly property var resultsNow: query.trim().length < 2 ? []
        : S.order(S.merge([...needHits, ...Packages.results]), query, curated).slice(0, 30)
    property var results: []
    onResultsNowChanged: settle.restart()
    Timer { id: settle; interval: 60; onTriggered: root.results = root.resultsNow }
    function reason(app: var): string { return S.reason(app, curated); }
    // its name: a pick's title, else an installed app's own name, else the package's
    function title(app: var): string {
        const t = S.title(app, curated);
        if (t !== app.title || app.best.source === "flathub") return t;
        const e = app.installed ? DesktopEntries.heuristicLookup(app.best.name) : null;
        return e?.name || t;
    }

    // an app's icon: its theme icon (by package, Flatpak id or name), else none
    function icon(app: var): string {
        if (!app?.sources) return "";
        for (const s of app.sources) {
            const p = Quickshell.iconPath(s.name, true);
            if (p) return p;
        }
        return Quickshell.iconPath(app.key, true) || "";
    }
    function size(s: var): string { return s.size > 0 ? Pkgs.size(s.size) : ""; }

    // ── installing ──
    function install(app: var, src: var): bool {
        const s = src ?? app.best;
        return Updates.installApp({ title: title(app), name: s.name, source: s.source, icon: icon(app) });
    }
    readonly property string installing: Updates.job && Updates.running ? Updates.job.name : ""
    Connections {
        target: Updates
        function onAppInstalled(): void { Packages.refreshInstalled(); }
    }
    function openApp(j: var): void {
        if (j.source === "flathub") { Quickshell.execDetached(["flatpak", "run", j.name]); return; }
        Quickshell.execDetached(["sh", "-c", 'f=$(pacman -Qql -- "$1" 2>/dev/null | grep -m1 "^/usr/share/applications/.*\\.desktop$"); [ -n "$f" ] && exec gio launch "$f"', "sh", j.name]);
    }
    function openInstalled(app: var): void {
        const s = app.sources.find(x => x.installed) ?? app.best;
        openApp({ name: s.name, source: s.source });
    }
    // ── an app's details (the sheet): bead-appinfo asks pacman, the AUR and Flathub ──
    property var info: ({})          // app key → details (store.js) | "loading"
    function details(app: var): void {
        if (info[app.key] && info[app.key] !== "failed") return;
        const i = Object.assign({}, info); i[app.key] = "loading"; info = i;
        const args = [];
        const repo = app.sources.find(s => s.source === "repo");
        const aur = app.sources.find(s => s.source === "aur");
        // a Flathub id: its own, else the pick's, else one in the Flathub list with the same title
        const e = picks().find(x => app.sources.some(s => s.name === x.name));
        const fh = app.sources.find(s => s.source === "flathub")?.name || e?.flatpak
            || Packages.catalog.find(c => c.title.toLowerCase() === S.title(app, curated).toLowerCase())?.id || "";
        if (repo) args.push("repo", repo.name);
        if (aur) args.push("aur", aur.name);
        if (fh) args.push("flathub", fh);
        const p = infoProc.createObject(root, { key: app.key, summary: S.reason(app, curated), command: [Paths.cmd("bead-appinfo"), ...args] });
        p.running = true;
    }
    Component {
        id: infoProc
        Process {
            id: ip
            property string key
            property string summary
            stdout: StdioCollector {
                onStreamFinished: {
                    let d = "failed";
                    try { d = S.details(JSON.parse(text), ip.summary); } catch (e) {}
                    const i = Object.assign({}, root.info); i[ip.key] = d; root.info = i;
                    ip.destroy();
                }
            }
        }
    }
    function openLink(url: string): void { Qt.openUrlExternally(url); }

    // ── Editor's choice, for bead's maintainer only (bin/bead-editors decides) ──
    property bool maintainer: false
    Process {
        running: true
        command: [Paths.cmd("bead-editors"), "check"]
        stdout: StdioCollector { onStreamFinished: root.maintainer = text.startsWith("yes") }
    }
    // the pick an app is (its entry in data/apps.json), and its Editor's choice note
    function pickOf(app: var): var { return app ? picks().find(x => app.sources.some(s => s.name === x.name || s.name === x.flatpak)) ?? null : null; }
    function editorNote(app: var): string {
        const p = pickOf(app);
        return p ? (Array.from(curated.editors ?? []).find(e => e.name === p.name)?.note ?? "") : "";
    }
    property string editorError: ""
    function setEditor(app: var, note: string, on: bool): void {
        const p = pickOf(app);
        if (!p) return;
        editorError = "";
        editorProc.command = on ? [Paths.cmd("bead-editors"), "add", p.name, note] : [Paths.cmd("bead-editors"), "remove", p.name];
        editorProc.running = true;
    }
    Process {
        id: editorProc
        stdout: StdioCollector { id: edOut }
        stderr: StdioCollector { id: edErr }
        onExited: code => {
            if (code !== 0) root.editorError = (edErr.text || edOut.text).trim().split("\n").pop();
            appsFile.reload();
        }
    }

    // ── is an AUR package real, and does it look safe? (bead-pkgcheck, trust.js) ──
    property var trust: ({})        // name → { level, reasons, notes } | "checking"
    function checkAur(name: string): void {
        if (trust[name]) return;
        const t = Object.assign({}, trust); t[name] = "checking"; trust = t;
        const p = trustProc.createObject(root, { name: name, command: [Paths.cmd("bead-pkgcheck"), "aur", name] });
        p.running = true;
    }
    Component {
        id: trustProc
        Process {
            id: tp
            property string name
            stdout: StdioCollector {
                onStreamFinished: {
                    let v = { level: "caution", reasons: ["Couldn't reach the AUR to check it"], notes: [] };
                    try {
                        const p = JSON.parse(text)[0];
                        let found = [];
                        for (const f in p.files ?? {}) found = found.concat(T.scan(p.files[f]));
                        v = T.verdict(T.aurRisk(p.exists ? p.info : null, Date.now() / 1000), found);
                    } catch (e) {}
                    const t = Object.assign({}, root.trust); t[tp.name] = v; root.trust = t;
                    tp.destroy();
                }
            }
        }
    }
    // an AUR package's build file, to read before building it
    function buildFile(name: string): void { Qt.openUrlExternally("https://aur.archlinux.org/cgit/aur.git/tree/PKGBUILD?h=" + encodeURIComponent(name)); }

    IpcHandler {
        target: "store"
        function open(q: string): void { root.show(q); }
        function close(): void { root.open = false; }
        // open an app's details sheet (by package name or Flatpak id, from the store front)
        function detail(name: string): string {
            root.open = true;
            const a = root.frontApps.find(x => x.sources.some(s => s.name === name));
            if (a) root.showApp(a);
            return a ? S.title(a, root.curated) : "not in the picks";
        }
        // scroll the store by px, as the wheel would; returns where it lands
        function scroll(px: real): void { root.scrollBy(px); }
        // the AUR check for a package (runs it if needed): its verdict as JSON
        function check(name: string): string { root.checkAur(name); return JSON.stringify(root.trust[name] ?? null); }
        function results(): string { return JSON.stringify(root.results.slice(0, 10).map(a => ({ title: a.title, from: a.best.source, name: a.best.name, why: root.reason(a), others: a.sources.length - 1 }))); }
    }
}
