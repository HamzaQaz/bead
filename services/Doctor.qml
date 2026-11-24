pragma Singleton

import QtQuick
import Quickshell
import qs.config
import Quickshell.Io
import "doctor.js" as Doc

// What bead needs on this machine (bin/bead-doctor --tsv, read by doctor.js):
// for Settings' check card and the welcome's last step. install() fixes the
// missing packages with pacman through pkexec (polkit asks for the password,
// bead never sees it), with progress on the island, then looks again.
Singleton {
    id: root

    property var checks: []
    property bool checking: false
    property bool installing: false
    readonly property var problems: Doc.problems(checks)
    readonly property var packages: Doc.packages(checks)
    readonly property string summary: checks.length ? Doc.summary(checks) : ""
    readonly property bool coreOk: checks.length > 0 && !problems.some(c => c.need === "core")

    function check(): void { if (!probe.running) { checking = true; probe.running = true; } }
    Process {
        id: probe
        command: [Paths.cmd("bead-doctor"), "--tsv"]
        stdout: StdioCollector { onStreamFinished: { root.checks = Doc.parse(text); root.checking = false; } }
    }

    function install(pkgs: var): void {
        if (installing || !pkgs.length) return;
        installing = true;
        Activities.set("doctor", "download", "Installing " + pkgs.length + (pkgs.length === 1 ? " package" : " packages"), -1);
        installer.command = ["pkexec", "pacman", "-S", "--noconfirm", "--needed", "--", ...pkgs];
        installer.running = true;
    }
    Process {
        id: installer
        onExited: code => {
            root.installing = false;
            // 126/127: the password prompt was dismissed
            Activities.end("doctor", code === 0, code === 0 ? "Installed" : code === 126 || code === 127 ? "Cancelled" : "Install failed");
            root.check();
        }
    }
}
