pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "shelf.js" as S

// The island shelf (docs/ideas/island-shelf.md): drop files, folders or text on
// the island and they're held there; drag one into any app and it leaves
// (folders stay), with an undo. It holds paths, never copies of your files.
//
// The moment: right after a screenshot, a recording, a finished download or a
// copied image, the island offers it for a few seconds to drag straight out, or
// keep on the shelf. A copied image has no file, so it's written to
// $XDG_RUNTIME_DIR/bead/shelf first (gone at logout).
//   qs -p ~/.local/share/bead ipc call shelf add PATH | moment PATH | list | clear | open | close
Singleton {
    id: root

    property list<var> held: []
    // demo mode: made-up things instead of yours
    readonly property list<var> items: Demo.on ? root.demoItems : held
    readonly property var demoItems: [
        { id: "d1", kind: "image", path: "", name: "mockup-v3.png", text: "" },
        { id: "d2", kind: "folder", path: "", name: "Assets", text: "" },
        { id: "d3", kind: "file", path: "", name: "brief.pdf", text: "" },
        { id: "d4", kind: "video", path: "", name: "walkthrough.mp4", text: "" }
    ]
    readonly property int count: items.length

    readonly property string clipDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/bead/shelf"

    // ── putting things down ──
    // dropped urls: folders are told apart on disk first (a name can't say)
    function drop(urls: var, text: string): void {
        console.log("shelf: dropped", urls.length, "url(s)", urls.length ? String(urls[0]).slice(0, 60) : "", text ? "text" : "");
        const paths = S.pathsOf(urls), web = S.webOf(urls);
        if (paths.length) sorter.ask(paths, root.put);
        web.slice(0, 5).forEach(u => root.fetch(u));
        if (!paths.length && !web.length && text && text.trim()) held = S.add(held, [S.textItem(text, Date.now())]);
    }
    // the file itself, carried by the drag (a browser's image): written to the
    // shelf's folder under its own name
    function dropBytes(name: string, buf: var): void {
        if (!buf || !buf.byteLength) return;
        console.log("shelf: dropped", name, buf.byteLength, "bytes");
        const p = Qt.createQmlObject('import Quickshell.Io; Process { stdinEnabled: true; stdout: StdioCollector {} }', root);
        p.command = ["sh", "-c", 'mkdir -p "$1"; f="$1/$(date +%H%M%S)-$2"; base64 -d > "$f" && [ -s "$f" ] && echo "$f" || rm -f -- "$f"', "sh", root.clipDir, name];
        p.stdout.streamFinished.connect(() => {
            const out = p.stdout.text.trim();
            if (out) root.put([{ path: out, dir: false }]);
            Qt.callLater(() => p.destroy());
        });
        const data = S.base64(buf);
        p.started.connect(() => { p.write(data); p.stdinEnabled = false; }); // then end of input
        p.running = true;
    }
    // a link dragged from a browser: fetched into the shelf's folder and kept as
    // a file (an image, a PDF…); a web page stays a link
    property int fetching: 0
    function fetch(url: string): void {
        fetching++;
        const p = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector {} }', root);
        p.command = ["sh", "-c", 'dir="$1"; url="$2"; name="$3"; mkdir -p "$dir"
            f="$dir/$(date +%H%M%S)-$name"
            t=$(curl -sfL --max-time 30 --max-filesize 200000000 -o "$f" -w "%{content_type}" -- "$url") || { rm -f -- "$f"; exit 1; }
            case $t in text/html*|"") rm -f -- "$f"; echo page; exit 0 ;; esac
            case $f in *.*) ;; *) ext=${t#*/}; ext=${ext%%;*}; mv -- "$f" "$f.$ext"; f="$f.$ext" ;; esac
            echo "$f"', "sh", root.clipDir, url, S.webName(url)];
        p.stdout.streamFinished.connect(() => {
            const out = p.stdout.text.trim();
            root.fetching = Math.max(0, root.fetching - 1);
            if (out === "page") held = S.add(held, [S.textItem(url, Date.now())]);
            else if (out) root.put([{ path: out, dir: false }]);
            else console.log("shelf: couldn't fetch", url.slice(0, 80));
            Qt.callLater(() => p.destroy());
        });
        p.running = true;
    }
    function put(found: var): void {
        held = S.add(held, found.map(f => S.item(f.path, f.dir, Date.now())));
    }
    function carriedOf(formats: var): var { return S.carried(formats); }
    function addPath(path: string): void { if (path) sorter.ask([path], root.put); }

    // ── taking things off ──
    property var undoable: null    // { removed, at }
    property bool droppedBack: false  // a shelf item let go over the island: nothing happened
    signal tookOff(var item)
    // a drag out ended: a file leaves (folders stay); undo puts it back
    function used(id: string): void {
        if (Demo.on) return;
        const r = S.afterDrag(held, id);
        if (!r.removed) return;
        held = r.items;
        undoable = { removed: r.removed, at: r.at };
        undoTimer.restart();
        tookOff(r.removed);
    }
    function remove(id: string): void {
        held = held.filter(i => i.id !== id);
    }
    function undo(): void {
        if (!undoable) return;
        held = S.putBack(held, undoable.removed, undoable.at);
        undoable = null;
    }
    Timer { id: undoTimer; interval: 8000; onTriggered: root.undoable = null }
    function clear(): void {
        if (Demo.on || !held.length) return;
        undoable = null;
        held = [];
    }

    // ── the moment ──
    property var moment: null      // an item, offered for a few seconds
    property real momentLeft: 0    // 1 → 0 over its time (the bar under it)
    NumberAnimation on momentLeft { id: momentRun; from: 1; to: 0; duration: 6500; running: false }
    property bool momentHeld: false   // hovered or being dragged: it stays
    function offer(path: string, isDir: bool): void {
        if (!path || Demo.on) return;
        moment = S.item(path, isDir, Date.now());
        momentTimer.restart();
        momentRun.restart();
    }
    function keepMoment(): void {
        if (!moment) return;
        held = S.add(held, [moment]);
        moment = null;
    }
    function dropMoment(): void { moment = null; }
    Timer {
        id: momentTimer
        interval: 6500
        onTriggered: if (root.momentHeld) restart(); else root.moment = null
    }
    onMomentHeldChanged: {
        if (momentHeld) { momentRun.pause(); return; }
        if (moment) { momentTimer.restart(); momentRun.restart(); }
    }

    // a screenshot also lands on the clipboard: one moment, not two
    property real lastOffer: 0
    function offerFile(path: string): void { lastOffer = Date.now(); offer(path, false); }

    // ── folders or files: asked on disk ──
    QtObject {
        id: sorter
        function ask(paths: var, then: var): void {
            const p = Qt.createQmlObject('import Quickshell.Io; Process { stdout: StdioCollector {} }', root);
            p.command = ["sh", "-c", 'for f; do if [ -d "$f" ]; then echo d; elif [ -e "$f" ]; then echo f; else echo -; fi; done', "sh", ...paths];
            p.stdout.streamFinished.connect(() => {
                const marks = p.stdout.text.split("\n");
                then(paths.map((path, i) => ({ path: path, dir: marks[i] === "d", there: marks[i] === "d" || marks[i] === "f" })).filter(f => f.there));
                Qt.callLater(() => p.destroy());
            });
            p.running = true;
        }
    }

    // ── finished downloads ──
    readonly property string downloads: Quickshell.env("XDG_DOWNLOAD_DIR") || Quickshell.env("HOME") + "/Downloads"
    property var seen: ({})
    property bool primed: false
    FolderListModel {
        id: dl
        folder: "file://" + root.downloads
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Time
        onStatusChanged: if (status === FolderListModel.Ready) root.look()
        onCountChanged: root.look()
    }
    function look(): void {
        if (dl.status !== FolderListModel.Ready) return;
        const fresh = [];
        for (let i = 0; i < dl.count; i++) {
            const name = dl.get(i, "fileName"), path = dl.get(i, "filePath");
            if (seen[path]) continue;
            seen[path] = true;
            if (!primed || S.isPartial(name)) continue;
            const age = Date.now() - dl.get(i, "fileModified").getTime();
            if (age < 60000) fresh.push(path);
        }
        primed = true;
        if (fresh.length) offerFile(fresh[0]);
    }

    // ── copied images: written to a file so apps can take them ──
    Process {
        id: clipWatch
        running: true
        command: ["sh", "-c", 'dir="$1"; mkdir -p "$dir"; exec wl-paste --watch sh -c \'
            t=$(wl-paste --list-types 2>/dev/null)
            printf "%s\\n" "$t" | grep -q passwordManagerHint && exit 0
            m=$(printf "%s\\n" "$t" | grep -m1 -E "^image/(png|jpeg|webp|gif)$") || exit 0
            f="$0/copied-$(date +%H%M%S)-$$.${m#image/}"
            wl-paste --type "$m" > "$f" 2>/dev/null && [ -s "$f" ] && echo "$f" || rm -f "$f"\' "$dir"', "sh", root.clipDir]
        stdout: SplitParser {
            onRead: line => root.copied(line.trim())
        }
        onExited: again.start()
    }
    Timer { id: again; interval: 5000; onTriggered: clipWatch.running = true }
    property bool clipPrimed: false
    function copied(path: string): void {
        if (!clipPrimed) { clipPrimed = true; if (Date.now() - startedAt < 3000) return; } // what was already copied
        if (!path || Date.now() - lastOffer < 3000) return; // a screenshot already offered itself
        if (Hyprland.focusedWorkspace?.hasFullscreen) return; // a game or a video: not now
        offer(path, false);
    }
    // copied images not on the shelf any more go after half an hour (apps read a
    // dropped file straight away; the folder itself goes at logout)
    Timer {
        interval: 10 * 60 * 1000; running: true; repeat: true
        onTriggered: Quickshell.execDetached(["sh", "-c", 'dir="$1"; shift; find "$dir" -maxdepth 1 -name "copied-*" -mmin +30 | while read -r f; do keep=; for h; do [ "$h" = "$f" ] && keep=1; done; [ -z "$keep" ] && rm -f -- "$f"; done', "sh", root.clipDir, ...root.held.map(i => i.path).filter(p => p)])
    }
    readonly property real startedAt: Date.now()

    // the shelf card shown without a hover (IPC: screenshots, a keybind)
    property bool showing: false
    IpcHandler {
        target: "shelf"
        function open(): void { root.showing = true; }
        function close(): void { root.showing = false; }
        function add(path: string): void { root.addPath(path); }
        function moment(path: string): void { root.offerFile(path); }
        function list(): string { return root.items.map(i => i.kind + "\t" + (i.path || i.name)).join("\n") || "empty"; }
        function clear(): void { root.clear(); }
    }
}
