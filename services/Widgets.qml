pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "widgets.js" as W

// Widgets (docs/ideas/island-widgets.md): things you keep an eye on, built in
// Settings → Widgets from a template and saved in ~/.config/bead/widgets.json.
// Each runs its command every so often (5 s at most, then it's "timed out"),
// and what it prints becomes a value with an icon and a tone. The pinned ones
// sit on the resting island, all of them on the dashboard's Widgets tab.
//   qs -p ~/.local/share/bead ipc call widgets list | refresh [ID]
Singleton {
    id: root

    readonly property var templates: W.TEMPLATES
    readonly property int maxPinned: W.MAX_PINNED

    // what's saved, checked (services/widgets.js)
    property list<var> config: []
    // what each one last showed: id → { value, tone, icon?, progress?, on?, at }
    property var results: ({})
    // the two together, in your order
    readonly property var items: config.map(w => Object.assign({}, w, { value: "…", tone: "" }, results[w.id] || {}))
    readonly property var chips: W.chips(items)
    readonly property var pinned: chips.shown

    // ── changes (Settings) ──
    function add(templateId: string, fields: var, label: string, pinned: bool): string {
        const id = W.newId(templateId, config);
        const w = W.clean({ id: id, template: templateId, fields: fields, label: label, pinned: pinned });
        if (!w) return "";
        config = [...config, w];
        save();
        return id;
    }
    function update(id: string, changes: var): void {
        config = config.map(w => w.id === id ? (W.clean(Object.assign({}, w, changes)) || w) : w);
        save();
        refresh(id);
    }
    function remove(id: string): void {
        config = config.filter(w => w.id !== id);
        const r = Object.assign({}, results); delete r[id]; results = r;
        save();
    }
    function move(id: string, by: int): void {
        const i = config.findIndex(w => w.id === id), j = i + by;
        if (i < 0 || j < 0 || j >= config.length) return;
        const l = config.slice(); const t = l[i]; l[i] = l[j]; l[j] = t;
        config = l;
        save();
    }
    function setPinned(id: string, on: bool): void { update(id, { pinned: on }); }

    // ask every runner (or one) to run now
    signal refreshRequested(string id)
    function refresh(id: string): void { refreshRequested(id || ""); }

    // a click: toggles flip, the rest refresh
    function activate(id: string): void {
        const w = items.find(x => x.id === id);
        if (!w) return;
        const a = W.action(w, w.on === true);
        if (!a) { refresh(id); return; }
        const r = Object.assign({}, results); r[id] = Object.assign({}, r[id] || {}, { value: "…", tone: "" }); results = r;
        actionProc.target = id;
        actionProc.command = a;
        actionProc.running = true;
    }
    Process {
        id: actionProc
        property string target
        onExited: root.refresh(target)
    }

    function setResult(id: string, res: var): void {
        const r = Object.assign({}, results);
        r[id] = Object.assign({ at: Date.now() }, res);
        results = r;
    }

    // ── the preview (Settings): one run of an unsaved widget ──
    property var preview: null      // { value, tone, … } or null while it runs
    property bool previewing: false
    function test(templateId: string, fields: var): void {
        const w = W.clean({ id: "preview", template: templateId, fields: fields });
        if (!w) { preview = { value: "fill in the fields", tone: "" }; return; }
        previewRun.widget = w;
        previewRun.start();
    }
    Runner {
        id: previewRun
        onDone: res => { root.preview = res; root.previewing = false; }
        onStarted: { root.previewing = true; root.preview = null; }
    }

    // ── one runner per widget ──
    Instantiator {
        model: root.config
        delegate: Runner {
            id: run
            required property var modelData
            widget: modelData
            onDone: res => root.setResult(modelData.id, res)
            Component.onCompleted: start()
            property Timer tick: Timer {
                interval: run.modelData.every * 1000
                running: true
                repeat: true
                onTriggered: run.start()
            }
            property Connections asked: Connections {
                target: root
                function onRefreshRequested(id) { if (!id || id === run.modelData.id) run.start(); }
            }
        }
    }

    component Runner: QtObject {
        id: runner
        property var widget
        signal done(var res)
        signal started()
        property string out: ""
        property int code: -1
        property bool gotOut: false
        property bool gotCode: false
        property bool over: true     // this run has reported (or timed out): late output is ignored

        function start(): void {
            if (proc.running || !widget) return;
            const argv = W.command(widget);
            if (!argv) return;
            out = ""; code = -1; gotOut = false; gotCode = false; over = false;
            proc.command = argv;
            proc.running = true;
            timeout.restart();
            started();
        }
        function finish(): void {
            if (over || !gotOut || !gotCode) return;
            over = true;
            timeout.stop();
            done(W.parse(widget, out, code));
        }

        property Process proc: Process {
            stdout: StdioCollector { onStreamFinished: { runner.out = text; runner.gotOut = true; runner.finish(); } }
            onExited: code => { runner.code = code; runner.gotCode = true; runner.finish(); }
        }
        property Timer timeout: Timer {
            interval: 5000
            onTriggered: {
                runner.over = true;
                runner.proc.running = false;
                runner.done({ value: "timed out", tone: "warning" });
            }
        }
    }

    // ── the file ──
    property bool loaded: false
    function save(): void { if (loaded) file.setText(JSON.stringify({ widgets: config }, null, 2)); }
    FileView {
        id: file
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/bead/widgets.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: { try { root.config = W.cleanAll(JSON.parse(text()).widgets); } catch (e) {} root.loaded = true; }
        onLoadFailed: root.loaded = true
    }

    IpcHandler {
        target: "widgets"
        function list(): string { return root.items.map(w => w.id + "\t" + w.label + "\t" + w.value + (w.pinned ? "\tpinned" : "")).join("\n"); }
        function refresh(id: string): void { root.refresh(id); }
        function click(id: string): void { root.activate(id); }
    }
}
