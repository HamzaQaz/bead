pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "pkgs.js" as Pkgs

// bead's installer: search the repos, Flathub and the AUR together, install,
// and remove apps.
//
// Passwords never pass through bead. Repo packages go through pkexec (your
// polkit agent asks); Flatpaks install system-wide and flatpak asks through
// polkit itself; AUR packages are built in a terminal with paru, where you
// read the build file and answer its questions. One install or removal at a
// time; the island shows it as a live activity.
//
// Flathub is searched from a list cached once a day ($XDG_CACHE_HOME/bead/
// flathub.tsv): asking flatpak takes seconds a search.
Singleton {
    id: root

    // ── what's installed ──
    property list<string> packages: []    // pacman -Qq
    property list<string> flatpaks: []  // app ids
    function refreshInstalled(): void { if (!installedProbe.running) installedProbe.running = true; }
    // for the Apps tab: desktop id → package, package → bytes, flatpak id → bytes
    property var owners: ({})
    property var sizes: ({})
    property var flatpakSizes: ({})
    Process {
        id: installedProbe
        running: true
        command: ["sh", "-c", "expac -Q '%n\t%m'; echo '--flatpak--'; flatpak list --app --columns=application,size 2>/dev/null; "
            + "echo '--owners--'; pacman -Qo /usr/share/applications/*.desktop 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [n, rest] = text.split("--flatpak--\n");
                const [f, o] = (rest || "").split("--owners--\n");
                const sizes = {}, pk = [];
                for (const l of (n || "").split("\n")) { const [name, b] = l.split("\t"); if (name) { pk.push(name); sizes[name] = Number(b) || 0; } }
                const fs = {}, fl = [];
                for (const l of (f || "").split("\n")) { const [id, sz] = l.split("\t"); if (id) { fl.push(id); fs[id] = Pkgs.bytes(sz); } }
                root.packages = pk; root.sizes = sizes;
                root.flatpaks = fl; root.flatpakSizes = fs;
                root.owners = Pkgs.parseOwned(o || "");
            }
        }
    }
    // an app (DesktopEntry) for the Apps tab: { e, name, size, used, source }
    function appInfo(e: var): var {
        const fp = flatpaks.includes(e.id);
        const pkg = fp ? e.id : owners[e.id] ?? "";
        return { e: e, name: e.name, pkg: pkg, source: fp ? "flathub" : pkg ? "repo" : "",
                 size: fp ? flatpakSizes[e.id] ?? 0 : sizes[pkg] ?? 0, used: Apps.last[e.id] ?? 0 };
    }

    // ── Flathub, cached ──
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/bead"
    property var catalog: []
    FileView {
        id: catalogFile
        path: root.cacheDir + "/flathub.tsv"
        printErrors: false
        onLoaded: root.catalog = Pkgs.parseCatalog(text())
    }
    Process {
        id: catalogFetch
        // only when the copy is missing or a day old; then reread it
        running: true
        command: ["sh", "-c", 'f="$1"; mkdir -p "$(dirname "$f")"; [ -n "$(find "$f" -mmin -1440 2>/dev/null)" ] && exit 0; '
            + 'flatpak remote-ls --app --columns=application,name,version,description flathub > "$f.new" 2>/dev/null && [ -s "$f.new" ] && mv "$f.new" "$f"',
            "sh", root.cacheDir + "/flathub.tsv"]
        onExited: catalogFile.reload()
    }

    // ── popularity, so the apps most people use come first: pkgstats for the
    // repos (top 10,000) and Flathub's installs last month, fetched once a day
    // into the cache folder as "name\tnumber" lines (needs python3 to read the
    // JSON; without it, results just aren't ordered by popularity) ──
    property var pop: ({ repo: Pkgs.parsePop(popRepo.loaded ? popRepo.text() : ""), flathub: Pkgs.parsePop(popFlathub.loaded ? popFlathub.text() : "") })
    FileView { id: popRepo; path: root.cacheDir + "/pop-repo.tsv"; printErrors: false }
    FileView { id: popFlathub; path: root.cacheDir + "/pop-flathub.tsv"; printErrors: false }
    Process {
        id: popFetch
        running: true
        // $2 and $3: the Python that turns each JSON answer into "name\tnumber" lines
        command: ["sh", "-c", 'd="$1"; mkdir -p "$d"; command -v python3 >/dev/null || exit 0; '
            + 'fresh() { [ -n "$(find "$1" -mmin -1440 2>/dev/null)" ]; }; '
            + 'fresh "$d/pop-repo.tsv" || { curl -sf --max-time 30 "https://pkgstats.archlinux.de/api/packages?limit=10000&offset=0" '
            + '| python3 -I -c "$2" > "$d/pop-repo.tsv.new" && [ -s "$d/pop-repo.tsv.new" ] && mv "$d/pop-repo.tsv.new" "$d/pop-repo.tsv"; }; '
            + 'fresh "$d/pop-flathub.tsv" || { : > "$d/pop-flathub.tsv.new"; for p in $(seq 1 20); do '
            + 'curl -sf --max-time 20 "https://flathub.org/api/v2/collection/popular?page=$p&per_page=250" | python3 -I -c "$3" >> "$d/pop-flathub.tsv.new" || break; done; '
            + '[ -s "$d/pop-flathub.tsv.new" ] && mv "$d/pop-flathub.tsv.new" "$d/pop-flathub.tsv"; }; true',
            "sh", root.cacheDir,
            "import json,sys\nfor p in json.load(sys.stdin)['packagePopularities']: print(p['name'], p['popularity'], sep='\\t')",
            "import json,sys\nh=json.load(sys.stdin).get('hits',[])\nfor a in h: print(a['app_id'], a.get('installs_last_month') or 0, sep='\\t')\nsys.exit(0 if h else 1)"]
        onExited: { popRepo.reload(); popFlathub.reload(); }
    }

    // ── search ──
    property string query: ""
    property var repoHits: []
    property var aurHits: []
    readonly property var flathubHits: Pkgs.searchFlathub(catalog, query, flatpaks, 200)
    readonly property bool searching: repoSearch.running || aurSearch.running
    readonly property var results: query ? Pkgs.rank([...repoHits, ...flathubHits, ...aurHits], query, pop).slice(0, 40) : []
    function search(q: string): void {
        q = q.trim();
        if (q === query) return;
        query = q;
        repoHits = []; aurHits = [];
        repoSearch.running = false; aurSearch.running = false;
        if (q.length < 2) return;
        searchSoon.restart();
    }
    Timer {
        id: searchSoon
        interval: 220 // while typing, only the last one runs
        onTriggered: {
            // expac and paru take a regex: the query is matched as plain text
            const re = root.query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
            repoSearch.command = ["expac", "-Ss", "%r\t%n\t%v\t%m\t%d", re];
            aurSearch.command = ["paru", "-Ssa", "--limit", "25", "--", root.query];
            repoSearch.running = true;
            aurSearch.running = true;
        }
    }
    Process {
        id: repoSearch
        stdout: StdioCollector { onStreamFinished: root.repoHits = Pkgs.parseRepo(text, root.packages).slice(0, 300) }
    }
    Process {
        id: aurSearch
        stdout: StdioCollector { onStreamFinished: root.aurHits = Pkgs.parseAur(text, root.packages) }
    }

    // ── install / remove ──
    property var job: null   // { id, verb, name, title, source }
    readonly property bool busy: job !== null
    signal installed(var result)

    function label(r: var): string { return r.title || r.name; }

    function install(r: var): string {
        if (busy) return "Busy with " + label(job);
        if (r.installed) return label(r) + " is already installed";
        if (r.source === "aur") {
            // built in a terminal: paru shows the build file and asks its questions there
            Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/bead-term", "--title", "Build " + r.name, "--", "sh", "-c",
                'paru -S -- "$1"; echo; printf "Done. Press Enter to close… "; read _', "sh", r.name]);
            afterTerminal.restart();
            return "Building " + r.name + " in a terminal";
        }
        const cmd = r.source === "repo"
            ? ["pkexec", "pacman", "-S", "--noconfirm", "--needed", "--", r.name]
            : ["flatpak", "install", "-y", "--noninteractive", "flathub", r.name];
        start({ id: "install:" + r.name, verb: "Installing", done: "Installed", name: r.name, title: label(r), source: r.source, result: r }, cmd);
        return "Installing " + label(r);
    }

    // remove the package an app comes from (resolved from its .desktop file)
    function remove(o: var): string {
        if (busy) return "Busy with " + label(job);
        const cmd = o.kind === "flatpak" ? ["flatpak", "uninstall", "-y", "--noninteractive", ...(o.user ? ["--user"] : []), o.name]
            : o.kind === "pacman" ? ["pkexec", "pacman", "-Rns", "--noconfirm", "--", o.name] : null;
        if (!cmd) return "Can't tell what installed " + (o.title || o.name);
        start({ id: "remove:" + o.name, verb: "Removing", done: "Removed", name: o.name, title: o.title || o.name, source: o.kind }, cmd);
        return "Removing " + (o.title || o.name);
    }

    // which package an app comes from: { kind: "pacman"|"flatpak"|"", name, user }
    function ownerOf(desktopId: string, cb: var): void {
        const p = ownerProbe.createObject(root, { cb: cb, command: ["sh", "-c", root.ownerScript, "sh", desktopId] });
        p.running = true;
    }
    readonly property string ownerScript: 'id="$1"; f="$id.desktop"; '
        + 'for d in /var/lib/flatpak/exports/share/applications "$HOME/.local/share/flatpak/exports/share/applications"; do '
        + '  [ -e "$d/$f" ] && { case "$d" in "$HOME"*) echo "flatpak $id user";; *) echo "flatpak $id";; esac; exit 0; }; done; '
        + 'for d in /usr/share/applications /usr/local/share/applications; do '
        + '  [ -e "$d/$f" ] && { p=$(pacman -Qqo "$d/$f" 2>/dev/null) && echo "pacman $p"; exit 0; }; done; echo none'
    Component {
        id: ownerProbe
        Process {
            id: op
            property var cb
            stdout: StdioCollector {
                onStreamFinished: {
                    const f = text.trim().split(" ");
                    op.cb({ kind: f[0] === "none" ? "" : f[0], name: f[1] || "", user: f[2] === "user" });
                    op.destroy();
                }
            }
        }
    }

    function start(j: var, cmd: var): void {
        job = j;
        Activities.set(j.id, j.verb === "Removing" ? "delete" : "download", j.verb + " " + j.title, -1);
        runner.lastText = "";
        runner.command = cmd;
        runner.running = true;
    }
    Process {
        id: runner
        property string lastText: ""
        stdout: SplitParser { splitMarker: "\n"; onRead: line => runner.step(line) }
        stderr: SplitParser { splitMarker: "\n"; onRead: line => { if (line.trim()) runner.lastText = line.trim(); } }
        function step(line: string): void {
            const p = Pkgs.progress(line.replace(/\r/g, "\n").split("\n").pop());
            if (!p || !root.job) return;
            const frac = p.pct >= 0 ? p.pct / 100 : p.of > 0 ? (p.step - 1) / p.of : -1;
            Activities.set(root.job.id, "", root.job.verb + " " + root.job.title, frac);
        }
        onExited: code => {
            const j = root.job;
            root.job = null;
            if (!j) return;
            // 126/127: pkexec's prompt was dismissed or not allowed
            const why = code === 126 || code === 127 ? "cancelled" : runner.lastText || "failed";
            Activities.end(j.id, code === 0, code === 0 ? j.done + " " + j.title : j.title + ": " + why);
            root.refreshInstalled();
            if (code === 0 && j.result) { root.installed(j.result); root.offerOpen(j); }
        }
    }

    // installed: a notification with Open, when the package brought an app
    function offerOpen(j: var): void {
        const find = j.source === "flathub"
            ? 'for d in /var/lib/flatpak/exports/share/applications; do [ -e "$d/$1.desktop" ] && echo "$d/$1.desktop"; done'
            : 'pacman -Qql -- "$1" 2>/dev/null | grep -m1 "^/usr/share/applications/.*\\.desktop$"';
        opener.command = ["sh", "-c", 'f=$(' + find + '); [ -n "$f" ] || exit 0; '
            + 'a=$(timeout 600 notify-send -a "bead" -i system-software-install -A open=Open "$2" "Installed from $3"); '
            + '[ "$a" = open ] && exec gio launch "$f"', "sh", j.name, j.title, j.source === "flathub" ? "Flathub" : "the repos"];
        opener.running = true;
    }
    Process { id: opener }
    // an AUR build: look again once the terminal has had a while
    Timer { id: afterTerminal; interval: 120000; onTriggered: root.refreshInstalled() }
}
