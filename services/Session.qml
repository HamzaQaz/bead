pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Session actions shared by the power panel and the launcher's > actions,
// plus uptime for the panel's header.
Singleton {
    id: root

    readonly property string sessionId: Quickshell.env("XDG_SESSION_ID") || ""
    readonly property list<var> actions: [
        { id: "lock", title: "Lock", sub: "Lock the screen", glyph: "lock" },
        { id: "suspend", title: "Suspend", sub: "Sleep, keeping your session", glyph: "bedtime", cmd: ["systemctl", "suspend"] },
        { id: "logout", title: "Log out", sub: "End this session", glyph: "logout", confirm: true, cmd: ["loginctl", "terminate-session", sessionId] },
        { id: "reboot", title: "Reboot", sub: "Restart the computer", glyph: "restart_alt", confirm: true, cmd: ["systemctl", "reboot"] },
        { id: "shutdown", title: "Shut down", sub: "Power off the computer", glyph: "power_settings_new", confirm: true, cmd: ["systemctl", "poweroff"] }
    ]
    function run(a: var): void {
        if (a.id === "lock") Lock.lock(); // bead's own lock screen
        else Quickshell.execDetached(a.cmd);
    }

    readonly property string user: Quickshell.env("USER") || ""
    property string realName: ""   // from /etc/passwd ("Ada Lovelace"); "" if none
    readonly property string firstName: realName.split(" ")[0] || user
    Process {
        running: true
        command: ["sh", "-c", 'getent passwd "$(id -un)" | cut -d: -f5 | cut -d, -f1']
        stdout: StdioCollector { onStreamFinished: root.realName = text.trim() }
    }
    property string host: ""
    property real uptime: 0 // seconds
    readonly property string uptimeText: {
        const m = Math.floor(uptime / 60), h = Math.floor(m / 60), d = Math.floor(h / 24);
        if (d > 0) return `up ${d} day${d > 1 ? "s" : ""}, ${h % 24} h`;
        if (h > 0) return `up ${h} h ${m % 60} min`;
        return `up ${m} min`;
    }
    function refresh(): void { uptimeFile.reload(); }

    FileView { id: hostFile; path: "/etc/hostname"; onLoaded: root.host = text().trim() }
    FileView { id: uptimeFile; path: "/proc/uptime"; onLoaded: root.uptime = parseFloat(text()) || 0 }
    Timer { interval: 60000; running: true; repeat: true; onTriggered: uptimeFile.reload() }
}
