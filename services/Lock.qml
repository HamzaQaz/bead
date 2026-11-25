pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pam
import qs.config

// The lock screen's state: locked or not, the password being typed, and the
// PAM check (bead's pam.d/passwd: pam_unix with faillock, same as Caelestia).
// `bead lock`, the power panel, the launcher and Super+L (global shortcut
// bead:lock) lock; `qs ipc call lock preview` shows the screen for 20 s
// without locking (Esc closes it).
Singleton {
    id: root

    property bool locked: false
    property bool preview: false
    property bool atLogin: false   // this lock is the one at login: the lock screen greets you instead
    readonly property bool shown: locked || preview
    // where each screen's bar clock is (screen name → rect, screen coords),
    // published by the bar as the lock appears: unlocking, the lock clock
    // flies there
    property var barClocks: ({})
    property string password: ""
    property string st: "idle"      // idle | checking | error | success
    property string errorText: ""
    property int failures: 0
    signal shake()

    // Locking first takes a still of each monitor: the lock screen's first frame
    // is then exactly your desktop, which fades away. Without it the lock
    // surface showed black for a frame or two before its capture arrived (a
    // flash). The stills live in a private folder and go on unlock.
    readonly property string stillDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/bead/lock"
    property int stillGen: 0 // bumped per lock, so the images reload
    function lock(): void {
        if (locked || snapping.running) return;
        reset();
        snapping.command = ["sh", "-c", 'd=$1; shift; mkdir -p "$d" && chmod 700 "$d" || exit 1; for o; do grim -t ppm -o "$o" "$d/$o.ppm" & done; wait',
            "sh", stillDir, ...Quickshell.screens.map(s => s.name)];
        snapping.running = true;
        snapGuard.restart();
    }
    function finishLock(): void {
        snapGuard.stop();
        if (locked) return;
        stillGen++;
        locked = true;
    }
    Process { id: snapping; onExited: root.finishLock() }
    Timer { id: snapGuard; interval: 800; onTriggered: root.finishLock() } // never hold a lock up
    function stillFor(name: string): string { return stillGen > 0 ? "file://" + stillDir + "/" + name + ".ppm?" + stillGen : ""; }
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
        onTriggered: {
            root.locked = false; root.preview = false; root.atLogin = false; root.reset();
            Quickshell.execDetached(["sh", "-c", 'rm -f "$1"/*.ppm', "sh", root.stillDir]);
        }
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

    // ── at login ──
    // A machine that logs in by itself (SDDM, LightDM, GDM or greetd autologin,
    // a getty with --autologin) never asked for a password: bead locks as it
    // first starts in the session, so a reboot lands on the lock screen. Once
    // per login (a mark in $XDG_RUNTIME_DIR, which goes at logout), so
    // restarting bead never locks you out. Settings.lockAtLogin: "auto" does
    // this only with autologin, "on" always, "off" never.
    readonly property string loginMark: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/bead/logged-in"
    Process {
        id: atLogin
        command: ["sh", Quickshell.shellPath("services/lock-at-login.sh"), Settings.lockAtLogin, root.loginMark]
        onExited: code => { if (code === 0) { root.atLogin = true; root.lock(); } }
    }
    Component.onCompleted: atLogin.running = true

    Timer { id: previewEnd; interval: 20000; onTriggered: if (!root.locked) { root.preview = false; root.atLogin = false; } }

    IpcHandler {
        target: "lock"
        function lock(): void { root.lock(); }
        function preview(): void { if (!root.locked) { root.reset(); root.preview = true; previewEnd.restart(); } }
        // the same, as it looks at login
        function previewLogin(): void { if (!root.locked) { root.reset(); root.atLogin = true; root.preview = true; previewEnd.restart(); } }
        function isLocked(): bool { return root.locked; }
        // close a preview (never unlocks a real lock)
        function endPreview(): void { if (root.preview && !root.locked) root.leave(); }
    }
    GlobalShortcut {
        appid: "bead"
        name: "lock"
        description: "Lock the screen"
        onPressed: root.lock()
    }
}
