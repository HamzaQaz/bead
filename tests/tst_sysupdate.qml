import QtQuick
import QtTest
import "../services/sysupdate.js" as U

// Reading an update's output (services/sysupdate.js): which stage it's in,
// which package it's on, how far along it is, and what went wrong.
TestCase {
    name: "SysUpdate"

    function test_a_stage_marker() {
        compare(U.parse("@@stage aur").kind, "stage");
        compare(U.parse("@@stage aur").stage, "aur");
    }
    function test_a_pacman_upgrade_step() {
        const s = U.parse("( 3/12) upgrading firefox                         [-------]");
        compare(s.kind, "step");
        compare(s.i, 3);
        compare(s.n, 12);
        compare(s.verb, "upgrading");
        compare(s.name, "firefox");
    }
    function test_installing_and_reinstalling_count_too() {
        compare(U.parse("(1/2) installing lib32-glibc").name, "lib32-glibc");
        compare(U.parse("(2/2) reinstalling bead-shell-git").verb, "reinstalling");
    }
    function test_a_step_without_a_counter() {
        // pacman's output through a pipe (no terminal, no progress bar)
        const s = U.parse("upgrading firefox...");
        compare(s.kind, "step");
        compare(s.i, 0);
        compare(s.name, "firefox");
        compare(U.parse("installing lib32-glibc...").name, "lib32-glibc");
    }
    function test_pacmans_checks_are_not_package_steps() {
        compare(U.parse("(12/12) checking keys in keyring").kind, "log");
        compare(U.parse("(3/12) checking package integrity").kind, "log");
    }
    function test_a_download() {
        const s = U.parse(" firefox-133.0-1-x86_64 downloading...");
        compare(s.kind, "download");
        compare(s.name, "firefox");
    }
    function test_a_flatpak_step() {
        const s = U.parse(" 2/5… org.mozilla.firefox stable u flathub 120.3 MB");
        compare(s.kind, "step");
        compare(s.i, 2);
        compare(s.n, 5);
        compare(s.name, "org.mozilla.firefox");
    }
    function test_an_aur_build() {
        const s = U.parse("==> Making package: spotify 1:1.2.50-1 (Sun 24 Nov 2026)");
        compare(s.kind, "build");
        compare(s.name, "spotify");
    }
    function test_errors() {
        compare(U.parse("error: failed to commit transaction (conflicting files)").kind, "error");
        compare(U.parse("==> ERROR: A failure occurred in build().").kind, "error");
        compare(U.parse("Request dismissed").kind, "error");
    }
    function test_anything_else_is_log() {
        compare(U.parse(":: Synchronizing package databases...").kind, "log");
        compare(U.parse("").kind, "log");
    }

    // overall progress: stages weighted by how many packages each has
    function test_progress_through_the_stages() {
        const counts = { repo: 10, aur: 2, flatpak: 0 };
        compare(U.progress(counts, "repo", 0, 10), 0);
        compare(U.progress(counts, "repo", 5, 10), 5 / 12);
        compare(U.progress(counts, "aur", 1, 2), 11 / 12);
        compare(U.progress(counts, "done", 0, 0), 1);
    }
    function test_progress_with_nothing_to_do_is_done() {
        compare(U.progress({ repo: 0, aur: 0, flatpak: 0 }, "repo", 0, 0), 1);
    }
    function test_progress_never_goes_past_a_stage() {
        // pacman counts dependencies too: 14 steps for 10 listed updates
        compare(U.progress({ repo: 10, aur: 2, flatpak: 0 }, "repo", 14, 14), 10 / 12);
    }

    // which app a package belongs to, for its name and icon
    function test_friendly_names() {
        compare(U.pretty("org.mozilla.firefox"), "firefox");
        compare(U.pretty("visual-studio-code-bin"), "visual studio code");
        compare(U.pretty("lib32-mesa"), "lib32 mesa");
    }
}
