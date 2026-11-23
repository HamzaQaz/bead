pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pam

// The lock screen's state: locked or not, the password being typed, and the
// PAM check (bead's pam.d/passwd: pam_unix with faillock, same as Caelestia).
// `bead lock`, the power panel, the launcher and Super+L (global shortcut
// bead:lock) lock; `qs ipc call lock preview` shows the screen for 20 s
// without locking (Esc closes it).
Singleton {
    id: root

    property bool locked: false
    property bool preview: false
    readonly property bool shown: locked || preview
    property string password: ""
    property string st: "idle"      // idle | checking | error | success
    property string errorText: ""
    property int failures: 0
    signal shake()

    function lock(): void {
        if (locked) return;
        reset();
        locked = true;
    }
    function reset(): void { password = ""; st = "idle"; errorText = ""; failures = 0; }

    function submit(): void {
        if (st === "checking" || st === "success") return;
        if (preview && !locked) { leave(); return; }
        if (!password) return;
        st = "checking";
        errorText = "";
        pam.start();
    }
    // success: let the screen play its exit, then unlock
    function leave(): void { st = "success"; exitTimer.restart(); }
    Timer {
        id: exitTimer
        interval: 470 // the screen's exit takes 440 ms
        onTriggered: { root.locked = false; root.preview = false; root.reset(); }
    }

    PamContext {
        id: pam
        config: "passwd"
        configDirectory: Quickshell.shellPath("pam.d")
        onResponseRequiredChanged: if (responseRequired) { respond(root.password); }
        onPamMessage: if (!responseRequired && messageIsError) root.errorText = message
        onCompleted: res => {
            root.password = "";
            if (res === PamResult.Success) { root.leave(); return; }
            root.failures++;
            if (res !== PamResult.Failed || !root.errorText)
                root.errorText = res === PamResult.Error ? "Couldn't check the password" : "Wrong password";
            root.st = "error";
            root.shake();
        }
        onError: e => { root.password = ""; root.errorText = "Couldn't check the password"; root.st = "error"; root.shake(); }
    }

    Timer { id: previewEnd; interval: 20000; onTriggered: if (!root.locked) root.preview = false }

    IpcHandler {
        target: "lock"
        function lock(): void { root.lock(); }
        function preview(): void { if (!root.locked) { root.reset(); root.preview = true; previewEnd.restart(); } }
        function isLocked(): bool { return root.locked; }
    }
    GlobalShortcut {
        appid: "bead"
        name: "lock"
        description: "Lock the screen"
        onPressed: root.lock()
    }
}
