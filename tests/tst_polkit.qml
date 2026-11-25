import QtQuick
import QtTest
import "../services/polkit.js" as P

// What a polkit request is for, in a few words (services/polkit.js).
TestCase {
    name: "Polkit"

    function test_the_program_pkexec_runs() {
        compare(P.program("Authentication is needed to run `/usr/bin/true' as the super user"), "true");
        compare(P.program("Authentication is needed to run `/usr/bin/pacman -S firefox' as the super user"), "pacman");
    }
    function test_wrappers_are_skipped() {
        compare(P.program("Authentication is needed to run `/usr/bin/stdbuf -oL -eL pacman -Syu' as the super user"), "pacman");
        compare(P.program("Authentication is needed to run `/usr/bin/env FOO=1 /usr/bin/flatpak update' as the super user"), "flatpak");
    }
    function test_no_program_in_the_message() {
        compare(P.program("Authentication is required to install software"), "");
        compare(P.program(""), "");
    }
    function test_a_short_description() {
        compare(P.describe("Authentication is needed to run `/usr/bin/true' as the super user"), "true wants to run as administrator");
        compare(P.describe("Authentication is required to install software"), "Authentication is required to install software");
    }
}
