pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.config
import "messengers.js" as M

// WhatsApp and Telegram, both optional (Settings → Notifications): an inbox
// made from the notifications they already show, from their desktop apps or
// from web.whatsapp.com / web.telegram.org in a browser. No account, no API,
// nothing sent anywhere. So, like Discord: bead hears only what the app shows
// as a notification (muted chats and notifications turned off stay silent).
// Opening a chat clicks its notification (the app jumps to it); Reply types
// straight back when the app's notification offers one (Telegram's does),
// else it opens the chat.
Singleton {
    id: root

    readonly property var on: [Settings.whatsapp ? "whatsapp" : "", Settings.telegram ? "telegram" : ""].filter(Boolean)
    readonly property bool enabled: on.length > 0

    // chats read in bead: "app/chat" → read up to (ms); saved
    property var read: ({})
    readonly property var inbox: enabled ? M.inbox(Notifs.entries, read, on) : []
    readonly property int count: inbox.reduce((n, i) => n + i.count, 0)
    function countOf(app: string): int { return inbox.filter(i => i.app === app).reduce((n, i) => n + i.count, 0); }

    readonly property var names: ({ whatsapp: "WhatsApp", telegram: "Telegram" })
    readonly property var glyphs: ({ whatsapp: "chat", telegram: "send" })

    function markRead(item: var): void {
        const r = Object.assign({}, read);
        r[item.id] = item.time;
        read = r;
        saver.restart();
    }
    function readAll(): void {
        const r = Object.assign({}, read);
        for (const i of inbox) r[i.id] = i.time;
        read = r;
        saver.restart();
    }

    // a chat's newest notification the app still has open
    function liveOf(item: var): var {
        for (const k of item.keys) { const n = Notifs.notif(k); if (n) return n; }
        return null;
    }
    function canReply(item: var): bool { return !!liveOf(item)?.hasInlineReply; }

    // open the chat: its notification's own click, else the app or the site
    function open(item: var): void {
        const n = liveOf(item);
        const act = n?.actions.find(a => a.identifier === "default");
        if (act) act.invoke();
        else if (item.app === "telegram") Quickshell.execDetached(["sh", "-c", 'for e in org.telegram.desktop telegram-desktop com.ayugram.desktop; do gtk-launch "$e" 2>/dev/null && exit 0; done; xdg-open https://web.telegram.org']);
        else Quickshell.execDetached(["sh", "-c", 'for e in com.rtosta.zapzap whatsapp-for-linux; do gtk-launch "$e" 2>/dev/null && exit 0; done; xdg-open https://web.whatsapp.com']);
        markRead(item);
    }
    function reply(item: var, text: string): bool {
        const n = liveOf(item);
        if (!n?.hasInlineReply || !text) return false;
        n.sendInlineReply(text);
        markRead(item);
        return true;
    }

    FileView {
        id: file
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/bead/messengers.json"
        printErrors: false
        onLoaded: { try { root.read = JSON.parse(text()).read ?? {}; } catch (e) {} }
    }
    Timer {
        id: saver
        interval: 1000
        onTriggered: {
            // keep it small: only the last 200 chats
            const keep = Object.entries(root.read).sort((a, b) => b[1] - a[1]).slice(0, 200);
            file.setText(JSON.stringify({ read: Object.fromEntries(keep) }));
        }
    }

    IpcHandler {
        target: "messengers"
        function inbox(): string { return JSON.stringify(root.inbox); }
        function readAll(): void { root.readAll(); }
    }
}
