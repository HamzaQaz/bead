pragma Singleton

import QtQuick
import Quickshell
import qs.config
import Quickshell.Hyprland
import Quickshell.Io

// Special workspaces (scratchpads), as Caelestia's `caelestia toggle` did:
// toggling one launches its app into it if that isn't running, gathers the
// app's windows into it, and otherwise shows/hides it. "specialws" toggles
// whichever special the focused monitor shows (or "special").
// Each app: match (any of these; every key inside must match, strings by
// substring), command (launched when nothing matches), move (gather windows).
Singleton {
    id: root

    readonly property var apps: ({
        music: [
            { match: [{ class: "Spotify" }, { initialTitle: "Spotify" }, { initialTitle: "Spotify Free" }, { initialTitle: "Spotify Premium" }], command: ["spotify"], move: true },
            { match: [{ class: "feishin" }], move: true }
        ],
        communication: [
            { match: [{ class: "discord" }], command: ["discord"], move: true },
            { match: [{ class: "whatsapp" }], move: true }
        ],
        todo: [
            { match: [{ class: "Todoist" }], command: ["todoist"], move: true }
        ],
        sysmon: [
            { match: [{ class: "btop", title: "btop", workspace: { name: "special:sysmon" } }], command: [Paths.cmd("bead-term"), "--class", "btop", "--title", "btop", "--", "sh", "-c", 'btop; exec "${SHELL:-sh}"'] }
        ],
        bitwarden: [
            { match: [{ class: "Bitwarden" }], command: ["bitwarden-desktop"], move: true }
        ]
    })

    // which commands exist (checked once): name -> bool
    property var installed: ({})
    Process {
        running: true
        command: ["sh", "-c", 'for c in "$@"; do command -v "$c" >/dev/null && echo "$c"; done', "sh",
            ...new Set([].concat(...Object.values(root.apps)).filter(a => a.command).map(a => a.command[0]))]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = {};
                for (const c of text.split("\n")) if (c) m[c] = true;
                root.installed = m;
            }
        }
    }

    function dispatch(lua: string): void { Hyprland.dispatch(lua); }
    function q(s: string): string { return JSON.stringify(s); } // a Lua-safe string literal

    // Caelestia's is_subset: every key in `want` matches `have`
    function matches(have: var, want: var): bool {
        for (const k in want) {
            if (!(k in have)) return false;
            const w = want[k], h = have[k];
            if (typeof w === "object" && !Array.isArray(w)) { if (!h || !matches(h, w)) return false; }
            else if (typeof w === "string") { if (String(h).indexOf(w) < 0) return false; }
            else if (w !== h) return false;
        }
        return true;
    }

    property list<string> queue: []
    function toggle(name: string): void {
        queue = [...queue, name];
        if (!clients.running) clients.running = true;
    }

    Process {
        id: clients
        // clients, then monitors (fresh, for "specialws")
        command: ["sh", "-c", "hyprctl -j clients; printf '\\036'; hyprctl -j monitors"]
        // a toggle that arrived after the output was read but before exit
        onExited: if (root.queue.length) running = true
        stdout: StdioCollector {
            onStreamFinished: {
                const [c, m] = text.split("\x1e");
                let list = [], mons = [];
                try { list = JSON.parse(c); mons = JSON.parse(m); } catch (e) {}
                const todo = Array.from(root.queue); // a copy: the property is live
                root.queue = [];
                for (const name of todo) root.run(name, list, mons);
            }
        }
    }

    function run(name: string, list: var, mons: var): void {
        if (name === "specialws") {
            const m = mons.find(x => x.focused);
            const cur = (m?.specialWorkspace?.name ?? "").replace(/^special:/, "") || "special";
            dispatch(`hl.dsp.workspace.toggle_special(${q(cur)})`);
            return;
        }
        let spawned = false;
        for (const app of apps[name] ?? []) {
            const hit = c => app.match.some(want => matches(c, want));
            if (app.command && installed[app.command[0]] && !list.some(hit)) {
                const cmd = app.command.map(a => /^[\w@%+=:,./-]+$/.test(a) ? a : "'" + a.replace(/'/g, "'\\''") + "'").join(" ");
                dispatch(`hl.dsp.exec_cmd(${q(`[workspace special:${name}] ${cmd}`)})`);
                spawned = true;
            }
            if (app.move)
                for (const c of list)
                    if (hit(c) && c.workspace?.name !== "special:" + name)
                        dispatch(`hl.dsp.window.move({ window = ${q("address:" + c.address)}, workspace = ${q("special:" + name)}, follow = false })`);
        }
        if (!spawned) dispatch(`hl.dsp.workspace.toggle_special(${q(name)})`);
    }

    // keybinds: hl.dsp.global("bead:special-<name>")
    GlobalShortcut { appid: "bead"; name: "special-music"; description: "Music workspace"; onPressed: root.toggle("music") }
    GlobalShortcut { appid: "bead"; name: "special-communication"; description: "Communication workspace"; onPressed: root.toggle("communication") }
    GlobalShortcut { appid: "bead"; name: "special-todo"; description: "Todo workspace"; onPressed: root.toggle("todo") }
    GlobalShortcut { appid: "bead"; name: "special-sysmon"; description: "System monitor workspace"; onPressed: root.toggle("sysmon") }
    GlobalShortcut { appid: "bead"; name: "special-bitwarden"; description: "Bitwarden workspace"; onPressed: root.toggle("bitwarden") }
    GlobalShortcut { appid: "bead"; name: "specialws"; description: "Toggle the current special workspace"; onPressed: root.toggle("specialws") }

    // `qs ipc call special toggle music`
    IpcHandler {
        target: "special"
        function toggle(name: string): void { root.toggle(name || "specialws"); }
    }
}
