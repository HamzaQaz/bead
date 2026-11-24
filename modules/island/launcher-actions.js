.pragma library
// What Tab offers on a launcher row: the things you can do with an app, an
// open window or a file. Plain logic (tests/tst_launcher_actions.qml);
// LauncherView.qml shows the list and carries the actions out.
//
// row:   { kind, name, running (an app's open windows), ws (a window's workspace) }
// typed: what's in the search box while the actions show: a number picks a
//        workspace, anything else narrows the list
// ctx:   { here: the workspace you're on }

var words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"];

function hasActions(kind) { return kind === "app" || kind === "win" || kind === "file"; }

// the workspace in what was typed ("3", "workspace 7", "ten"): 1 to 10, or 0
function workspaceIn(typed) {
    var m = /^(?:(?:workspace|ws|desktop)\s+)?(\w+)$/.exec(String(typed).trim().toLowerCase());
    if (!m) return 0;
    var n = /^\d+$/.test(m[1]) ? parseInt(m[1]) : words.indexOf(m[1]);
    return n >= 1 && n <= 10 ? n : 0;
}

function actionsFor(row, typed, ctx) {
    var ws = workspaceIn(typed);
    var place = function (id, verb, glyph) {
        return ws ? { id: id, ws: ws, title: verb + " workspace " + ws, sub: row.name, glyph: glyph }
                  : { id: id, ws: 0, title: verb + " workspace…", sub: "Type a number, 1 to 10", glyph: glyph };
    };
    var all = [];
    if (row.kind === "app") {
        all.push({ id: "open", title: "Open " + row.name, sub: "On this workspace", glyph: "open_in_new" });
        all.push({ id: "open_empty", title: "Open on an empty workspace", sub: "The first one with nothing on it", glyph: "add_to_queue" });
        all.push(place("open_on", "Open on", "move_up"));
        if (row.running > 0)
            all.push({ id: "quit", title: "Quit " + row.name, sub: row.running === 1 ? "Closes its window" : "Closes " + row.running + " windows",
                       glyph: "close", confirm: row.running > 1 });
    } else if (row.kind === "win") {
        if (row.ws !== ctx.here)
            all.push({ id: "bring", title: "Bring here", sub: "From workspace " + row.ws, glyph: "call_received" });
        all.push(place("move_to", "Move to", "move_up"));
        all.push({ id: "close", title: "Close", sub: row.name, glyph: "close" });
    } else if (row.kind === "file") {
        all.push({ id: "open", title: "Open", sub: row.name, glyph: "open_in_new" });
        all.push({ id: "folder", title: "Show in its folder", sub: "Opens the folder it's in", glyph: "folder_open" });
        all.push({ id: "copy_path", title: "Copy its path", sub: "To the clipboard", glyph: "content_copy" });
    }
    if (ws) return all.filter(function (a) { return a.ws === ws; });
    var q = String(typed).trim().toLowerCase();
    return q ? all.filter(function (a) { return a.title.toLowerCase().indexOf(q) >= 0; }) : all;
}
