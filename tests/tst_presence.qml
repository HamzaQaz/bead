import QtQuick
import QtTest
import "../services/presence.js" as P

// Which project Discord presence names (services/presence.js): only from
// editors and terminals, and only a project name, never a file or a path.
TestCase {
    name: "Presence"

    function test_vscode_names_the_folder() {
        compare(P.project("code", "Bar.qml - bead - Visual Studio Code"), "bead");
        compare(P.project("codium", "bead - VSCodium"), "bead");
    }
    function test_zed_names_the_project() {
        compare(P.project("dev.zed.Zed", "bead — modules/bar/Bar.qml"), "bead");
    }
    function test_a_terminal_in_a_projects_folder() {
        compare(P.project("kitty", "~/Projects/bead/modules"), "bead");
        compare(P.project("foot", "nvim ~/Projects/bead-site/src/index.html"), "bead-site");
    }
    function test_a_terminal_elsewhere_names_nothing() {
        compare(P.project("kitty", "~/Downloads"), "");
        compare(P.project("kitty", "Keybinds for emojis"), "");
    }
    function test_other_apps_name_nothing() {
        compare(P.project("helium", "~/Projects/secret - Search"), "");
        compare(P.project("", ""), "");
    }
}
