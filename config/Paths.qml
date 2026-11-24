pragma Singleton

import QtQuick
import Quickshell

// Where bead lives: its commands sit next to the shell's folder
// (<prefix>/share/bead → <prefix>/bin), so ~/.local and /usr installs both work.
Singleton {
    readonly property string share: Quickshell.shellPath("").replace(/\/$/, "")
    // (run from a checkout with `make run`: its own bin/)
    readonly property string bin: /\/share\/bead$/.test(share) ? share.replace(/\/share\/bead$/, "/bin") : share + "/bin"
    function cmd(name: string): string { return bin + "/" + name; }
    // Murmur's models (strand downloads them here)
    readonly property string models: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/bead-models"
}
