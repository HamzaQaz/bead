import QtQuick
import QtTest
import "../services/doctor.js" as Doc

// Reading `bead-doctor --tsv` (services/doctor.js) for Settings and the welcome.
TestCase {
    name: "Doctor"

    readonly property string sample: "ok\tcore\thyprland\tHyprland is running\tLog in\t\n"
        + "missing\tcore\tpolkit\tA polkit agent is running\tInstall hyprpolkitagent\thyprpolkitagent\n"
        + "missing\tcore\tfd\tfd (file search)\tInstall fd\tfd\n"
        + "missing\tcore\thypr-lua\tHyprland uses a Lua config\tUpdate Hyprland\t\n"
        + "missing\textra\tsatty\tsatty\tInstall satty\tsatty\n"
        + "missing\tmurmur\tmodels\tMurmur's models\tRe-run ./install.sh\t\n"
        + "garbage line\n"

    function test_lines_become_checks() {
        const c = Doc.parse(sample);
        compare(c.length, 6);
        compare(c[1], { ok: false, need: "core", id: "polkit", what: "A polkit agent is running", fix: "Install hyprpolkitagent", pkg: "hyprpolkitagent" });
        verify(c[0].ok);
    }
    function test_problems_core_first() {
        compare(Doc.problems(Doc.parse(sample)).map(c => c.id), ["polkit", "fd", "hypr-lua", "satty", "models"]);
    }
    function test_packages_to_install_are_the_missing_ones_with_a_package() {
        compare(Doc.packages(Doc.parse(sample)), ["hyprpolkitagent", "fd", "satty"]);
        compare(Doc.packages(Doc.parse(sample), true), ["hyprpolkitagent", "fd"]);   // core only
    }
    function test_a_summary_line() {
        compare(Doc.summary(Doc.parse(sample)), "3 things bead needs are missing");
        compare(Doc.summary(Doc.parse("ok\tcore\ta\tA\t\t\nmissing\tcore\tb\tB\tfix\tb\n")), "1 thing bead needs is missing");
        compare(Doc.summary(Doc.parse("ok\tcore\ta\tA\t\t\nmissing\textra\tb\tB\tfix\tb\n")), "All set · 1 optional extra missing");
        compare(Doc.summary(Doc.parse("ok\tcore\ta\tA\t\t\n")), "All set");
    }
}
