pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam

// Passkey approvals for keyhold, shown in the island.
//
// keyhold calls `ipc call passkey request <json>` with
//   { id, action, rpId, rpName, user, nonce, timeout, socket }
// and listens on `socket` (a unix socket in its private runtime dir). The
// password is checked here through PAM (pam.d/keyhold: pam_unix, no faillock);
// the answer goes back over that socket as "approved <nonce>", "denied" or
// "timeout". Three wrong passwords deny.
Singleton {
    id: root

    property var req: null
    // "" | ask | checking | error | success | cancelled
    property string st: ""
    property string errorText: ""
    property int failures: 0
    readonly property int maxFailures: 3
    readonly property bool active: st !== ""
    readonly property bool asking: st === "ask" || st === "checking" || st === "error"
    readonly property bool registering: req?.action === "register"
    signal shake()

    IpcHandler {
        target: "passkey"
        function request(spec: string): string {
            if (root.asking) return "busy";
            let r;
            try { r = JSON.parse(spec); } catch (e) { return "bad request"; }
            if (!r.nonce || !r.socket) return "bad request";
            root.req = r;
            root.failures = 0;
            root.errorText = "";
            root.st = "ask";
            closeTimer.stop();
            timeout.interval = Math.max(5, r.timeout || 90) * 1000;
            timeout.restart();
            return "ok";
        }
        function cancel(id: string): void { if (root.req?.id === id && root.asking) root.finish(false, "timeout"); }
        function ping(): string { return "ok"; }
    }

    property string password: ""
    function submit(pw: string): void {
        if (st !== "ask" && st !== "error") return;
        if (!pw) { shake(); return; }
        password = pw;
        st = "checking";
        pam.start();
    }
    function deny(): void { if (asking) finish(false, "denied"); }

    PamContext {
        id: pam
        config: "keyhold"
        configDirectory: Quickshell.shellPath("pam.d")
        onResponseRequiredChanged: if (responseRequired) { respond(root.password); root.password = ""; }
        onCompleted: res => {
            root.password = "";
            if (!root.asking) return;
            if (res === PamResult.Success) { root.finish(true, ""); return; }
            root.failures++;
            const left = root.maxFailures - root.failures;
            root.errorText = res === PamResult.Error ? "Couldn't check your password."
                : left <= 0 ? "Too many attempts." : `Wrong password · ${left} ${left === 1 ? "try" : "tries"} left`;
            root.st = "error";
            root.shake();
            if (left <= 0) giveUp.start();
        }
    }
    Timer { id: giveUp; interval: 1200; onTriggered: root.finish(false, "denied") }
    Timer { id: timeout; onTriggered: root.finish(false, "timeout") }

    function finish(ok: bool, why: string): void {
        if (!asking) return;
        timeout.stop();
        giveUp.stop();
        if (pam.active) pam.abort();
        password = "";
        reply(ok ? "approved " + req.nonce : why);
        st = ok ? "success" : "cancelled";
        closeTimer.restart();
    }
    Timer { id: closeTimer; interval: 1400; onTriggered: { root.st = ""; root.req = null; } }

    // answer keyhold over its socket
    property string pending: ""
    function reply(msg: string): void {
        pending = msg;
        sock.connected = false;
        sock.path = req.socket;
        sock.connected = true;
    }
    Socket {
        id: sock
        onConnectedChanged: {
            if (!connected || !root.pending) return;
            write(root.pending + "\n");
            flush();
            root.pending = "";
            connected = false;
        }
    }
}
