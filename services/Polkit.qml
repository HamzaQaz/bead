pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit
import "polkit.js" as P

// bead as your polkit agent: an app asking for admin rights (pkexec, an
// install, the system update) asks in the island, in the same view as
// passkeys (modules/island/PasskeyView.qml), not in a separate dialog.
// The password goes straight to polkit; bead never keeps it.
//
// Only one agent can run per session. If another one already has the seat
// (or registering fails), bead leaves it be; and if no agent is running at
// all, it starts polkit-gnome so admin prompts still work.
Singleton {
    id: root

    // the same shape as services/Passkey.qml, for the island
    // "" | ask | checking | error | success | cancelled
    property string st: ""
    property string errorText: ""
    readonly property bool active: st !== ""
    readonly property bool asking: st === "ask" || st === "checking" || st === "error"
    signal shake()

    readonly property var flow: agent.flow
    // what it's for: bead's own system update says so; anything else, polkit's message
    readonly property string title: Updates.running ? "Update your system" : "Admin access"
    readonly property string program: Updates.running ? "" : P.program(flow?.message ?? "")
    readonly property string subtitle: Updates.running ? "pacman, the AUR and Flatpak need your password" : P.describe(flow?.message ?? "")
    readonly property string detail: flow?.selectedIdentity ? "as " + (flow.selectedIdentity.displayName || "your account") : ""
    readonly property string approveText: "Allow"
    readonly property string icon: "admin_panel_settings"
    readonly property string doneText: st === "success" ? "Allowed" : "Cancelled"

    PolkitAgent { id: agent }

    Connections {
        target: agent
        function onAuthenticationRequestStarted(): void { root.st = "ask"; root.errorText = ""; }
    }
    Connections {
        target: root.flow
        ignoreUnknownSignals: true
        function onIsResponseRequiredChanged(): void {
            if (root.flow?.isResponseRequired && root.st === "checking") {
                root.st = "error";
                root.errorText = root.flow.supplementaryIsError && root.flow.supplementaryMessage ? root.flow.supplementaryMessage : "Wrong password";
                root.shake();
            }
        }
        function onAuthenticationFailed(): void {
            if (root.st !== "checking") return;
            root.st = "error";
            root.errorText = "Wrong password";
            root.shake();
        }
        // the outcome: from polkit's own signals. isCompleted is set before
        // isSuccessful, so reading them at that moment called a right password
        // "Cancelled"; it's only a fallback, read once the flow has settled
        function onAuthenticationSucceeded(): void { root.end("success"); }
        function onAuthenticationRequestCancelled(): void { root.end("cancelled"); }
        function onIsCompletedChanged(): void { if (root.flow?.isCompleted) settle.restart(); }
    }

    function submit(pw: string): void {
        if (!flow || st === "checking") return;
        st = "checking";
        flow.submit(pw);
    }
    function deny(): void {
        if (flow && asking) flow.cancelAuthenticationRequest();
        end("cancelled");
    }
    function end(how: string): void {
        if (!active || st === "success" || st === "cancelled") return;
        st = how;
        hide.restart();
    }
    Timer { id: hide; interval: 1100; onTriggered: root.st = "" }
    Timer {
        id: settle
        interval: 50
        onTriggered: if (root.flow?.isCompleted) root.end(root.flow.isSuccessful ? "success" : root.flow.isCancelled ? "cancelled" : root.st === "checking" ? "success" : "cancelled")
    }
    // the flow went away before saying how it ended: mid-check, polkit took the
    // password (a wrong one or a cancel says so first); while still asking, the
    // program gave up waiting
    onFlowChanged: if (!flow && active) end(st === "checking" ? "success" : "cancelled")

    // nobody answering admin prompts: start polkit-gnome (if it's there)
    Timer {
        interval: 4000
        running: true
        onTriggered: if (!agent.isRegistered) Quickshell.execDetached(["sh", "-c",
            "pgrep -f 'polkit.*agent|hyprpolkitagent|polkit-gnome|polkit-kde|lxpolkit|mate-polkit|soteria' >/dev/null || "
            + "for a in /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 /usr/lib/hyprpolkitagent/hyprpolkitagent; do [ -x \"$a\" ] && exec \"$a\"; done"])
    }
    readonly property bool registered: agent.isRegistered

    // `qs ipc call polkit registered` (bead doctor asks)
    IpcHandler {
        target: "polkit"
        function registered(): bool { return agent.isRegistered; }
    }
}
