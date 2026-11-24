import QtQuick
import QtTest
import "../modules/island/launcher-actions.js" as LA

// What Tab offers on a launcher row (modules/island/launcher-actions.js).
TestCase {
    name: "LauncherActions"

    function ids(list) { return list.map(a => a.id); }

    // ── apps ──
    function test_app_not_running_offers_opening_but_not_quitting() {
        const a = LA.actionsFor({ kind: "app", name: "Firefox", running: 0 }, "", { here: 1 });
        compare(ids(a), ["open", "open_empty", "open_on", "uninstall"]);
    }
    function test_app_running_can_be_quit() {
        const a = LA.actionsFor({ kind: "app", name: "Firefox", running: 1 }, "", { here: 1 });
        const quit = a.find(x => x.id === "quit");
        compare(quit.title, "Quit Firefox");
        compare(quit.sub, "Closes its window");
        verify(!quit.confirm);
    }
    function test_quitting_an_app_with_several_windows_asks_first() {
        const quit = LA.actionsFor({ kind: "app", name: "Firefox", running: 3 }, "", { here: 1 }).find(x => x.id === "quit");
        compare(quit.sub, "Closes 3 windows");
        verify(quit.confirm);
    }
    function test_typing_a_number_offers_that_workspace_for_an_app() {
        const a = LA.actionsFor({ kind: "app", name: "Firefox", running: 0 }, "3", { here: 1 });
        compare(a.length, 1);
        compare(a[0].id, "open_on");
        compare(a[0].ws, 3);
        compare(a[0].title, "Open on workspace 3");
    }
    function test_open_on_without_a_number_says_to_type_one() {
        const on = LA.actionsFor({ kind: "app", name: "Firefox", running: 0 }, "", { here: 1 }).find(x => x.id === "open_on");
        compare(on.ws, 0);
        compare(on.title, "Open on workspace…");
    }

    function test_an_app_can_be_uninstalled_after_asking() {
        const u = LA.actionsFor({ kind: "app", name: "Kitty", running: 0 }, "", { here: 1 }).find(x => x.id === "uninstall");
        compare(u.title, "Uninstall Kitty");
        verify(u.confirm);
    }
    function test_uninstall_comes_last() {
        const a = LA.actionsFor({ kind: "app", name: "Kitty", running: 1 }, "", { here: 1 });
        compare(a[a.length - 1].id, "uninstall");
    }

    // ── windows ──
    function test_window_elsewhere_can_be_brought_moved_or_closed() {
        const a = LA.actionsFor({ kind: "win", name: "Firefox", ws: 4 }, "", { here: 1 });
        compare(ids(a), ["bring", "move_to", "close"]);
        compare(a[0].sub, "From workspace 4");
    }
    function test_window_already_here_is_not_offered_bringing() {
        const a = LA.actionsFor({ kind: "win", name: "Firefox", ws: 2 }, "", { here: 2 });
        compare(ids(a), ["move_to", "close"]);
    }
    function test_typing_a_number_offers_moving_a_window_there() {
        const a = LA.actionsFor({ kind: "win", name: "Firefox", ws: 4 }, "2", { here: 1 });
        compare(a.length, 1);
        compare(a[0].id, "move_to");
        compare(a[0].ws, 2);
        compare(a[0].title, "Move to workspace 2");
    }

    // ── files ──
    function test_file_can_be_opened_shown_or_have_its_path_copied() {
        compare(ids(LA.actionsFor({ kind: "file", name: "notes.md" }, "", { here: 1 })), ["open", "folder", "copy_path"]);
    }

    // ── filtering, and rows without actions ──
    function test_typing_words_narrows_the_actions() {
        const a = LA.actionsFor({ kind: "win", name: "Firefox", ws: 4 }, "clo", { here: 1 });
        compare(ids(a), ["close"]);
    }
    function test_other_rows_have_no_actions() {
        for (const kind of ["clip", "emoji", "calc", "ask", "action"]) {
            compare(LA.actionsFor({ kind: kind, name: "x" }, "", { here: 1 }).length, 0);
            verify(!LA.hasActions(kind));
        }
        verify(LA.hasActions("app") && LA.hasActions("win") && LA.hasActions("file"));
    }

    // ── the workspace someone typed ──
    function test_workspace_typed_as_a_number_or_a_word() {
        compare(LA.workspaceIn("3"), 3);
        compare(LA.workspaceIn("workspace 7"), 7);
        compare(LA.workspaceIn("ten"), 10);
    }
    function test_workspace_out_of_range_or_not_a_number_is_none() {
        compare(LA.workspaceIn("0"), 0);
        compare(LA.workspaceIn("11"), 0);
        compare(LA.workspaceIn("close"), 0);
        compare(LA.workspaceIn(""), 0);
    }
}
