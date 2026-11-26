pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

// Your phone, through KDE Connect (docs/ideas/phone-link.md), from
// bin/bead-phone: pairing, battery, ringing it, sending it links and files.
// Its notifications need nothing here: the daemon posts them as ordinary
// desktop notifications, so bead's pop-ups and history show them.
//   qs -p ~/.local/share/bead ipc call phone status | ring | ping | send URL-OR-PATH
Singleton {
    id: root

    property string state: ""        // ready | off ("" before the helper says)
    property string name: ""         // what this computer is called on the phone
    property string firewall: ""     // open | closed | unknown | none
    property string wall: ""         // ufw | firewalld
    // what opens it (shown to copy: it needs your password, so you run it)
    readonly property string fixCommand: wall === "firewalld"
        ? "sudo firewall-cmd --permanent --add-service=kdeconnect && sudo firewall-cmd --reload"
        : "sudo ufw allow 1714:1764/udp && sudo ufw allow 1714:1764/tcp"
    property list<var> devices: []   // { id, name, kind, reachable, pair, battery, charging, can }

    readonly property bool ready: state === "ready"
    // demo mode: a made-up phone
    readonly property var demoPhone: ({ id: "demo", name: "Pixel 9", kind: "phone", reachable: true, pair: "paired", battery: 76, charging: false, can: ["battery", "ping", "ring", "share"] })
    readonly property list<var> shown: Demo.on ? [demoPhone] : devices
    // the one bead talks about: paired and near, else paired
    readonly property var phone: shown.find(d => d.pair === "paired" && d.reachable) ?? shown.find(d => d.pair === "paired") ?? null
    readonly property bool near: !!phone && phone.reachable
    readonly property list<var> asking: devices.filter(d => d.pair === "incoming")

    function can(what: string): bool { return near && (phone.can ?? []).includes(what); }
    function send(c: string): void { if (helper.running) helper.write(c + "\n"); }
    function refresh(): void { send("refresh"); }
    function pair(id: string): void { send("pair " + id); }
    function unpair(id: string): void { send("unpair " + id); }
    function accept(id: string): void { send("accept " + id); }
    function reject(id: string): void { send("reject " + id); }
    function cancel(id: string): void { send("cancel " + id); }
    function ring(): void { if (can("ring") && !Demo.on) send("ring " + phone.id); }
    function ping(): void { if (can("ping") && !Demo.on) send("ping " + phone.id); }
    // a link, or a file's path
    function share(what: string): void { if (what && can("share") && !Demo.on) send("share " + phone.id + " " + what.replace(/\n/g, " ")); }

    Process {
        id: helper
        running: true
        stdinEnabled: true
        command: [Paths.cmd("bead-phone")]
        stdout: SplitParser {
            onRead: line => {
                let m;
                try { m = JSON.parse(line); } catch (e) { return; }
                if (m.type === "status") {
                    root.state = m.state;
                    root.name = m.name || "";
                    root.firewall = m.firewall || "";
                    root.wall = m.wall || "";
                } else if (m.type === "devices") {
                    root.devices = m.devices ?? [];   // a pairing request also comes as the daemon's own notification
                }
            }
        }
        onExited: { root.state = ""; root.devices = []; restart.start(); }
    }
    Timer { id: restart; interval: 5000; onTriggered: helper.running = true }

    IpcHandler {
        target: "phone"
        function status(): string {
            if (!root.ready) return root.state || "starting";
            if (!root.shown.length) return "no phones (firewall " + root.firewall + ")";
            return root.shown.map(d => d.name + ": " + d.pair + (d.reachable ? ", near" : ", away")
                + (d.battery !== null && d.battery !== undefined ? ", " + d.battery + "%" + (d.charging ? " charging" : "") : "")).join("\n");
        }
        function ring(): void { root.ring(); }
        function ping(): void { root.ping(); }
        function send(what: string): void { root.share(what); }
    }
}
