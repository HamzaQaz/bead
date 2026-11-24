pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Notification history and Do Not Disturb.
//
// Every notification is recorded here. A popup timing out leaves it in the
// history; dismissing it (swipe, click, clear) or the app closing it removes it.
// While the app keeps the notification open its object stays attached, so its
// actions (Reply…) still work from the history. The history (without the live
// objects) is saved to $XDG_STATE_HOME/bead/notifications.json.
Singleton {
    id: root

    readonly property int limit: 100
    property list<var> entries: []      // newest first
    property bool dnd: false
    property bool panelOpen: false
    property int serial: 0

    // a new notification popped up (not held by DND or the open panel)
    signal posted(var entry)

    // ── the digest: what came in while Do Not Disturb was on. When it ends,
    // `missed` says what arrived (the island offers it), and the history shows
    // them first, under "While you were away", until the panel's next closed ──
    property real dndSince: 0     // when DND went on (saved: a restart keeps it)
    property real awayFrom: 0     // the stretch the history shows first
    property real awayTo: 0
    signal missed(var list)
    function away(e: var): bool { return awayFrom > 0 && e.time >= awayFrom && e.time <= awayTo; }
    onDndChanged: {
        if (!loaded) return;
        saveTimer.restart();
        if (dnd) { dndSince = Date.now(); return; }
        const from = dndSince;
        dndSince = 0;
        const list = from ? entries.filter(e => e.time >= from) : [];
        if (!list.length) return;
        awayFrom = from;
        awayTo = Date.now();
        missed(list);
    }
    onPanelOpenChanged: if (!panelOpen && awayFrom) { awayFrom = 0; awayTo = 0; }

    // live notification objects by entry key (not saved)
    property var live: ({})

    function record(n: Notification): var {
        const e = {
            key: Date.now() * 1000 + (++serial % 1000),
            time: Date.now(),
            appName: n.appName,
            summary: n.summary,
            body: n.body,
            appIcon: n.appIcon,
            image: n.image,
            urgency: n.urgency,
            actions: n.actions.map(a => ({ id: a.identifier, label: a.text }))
        };
        live[e.key] = n;
        // the app closed it (read elsewhere, replaced…): drop it
        n.closed.connect(() => { if (root.live[e.key] === n) { delete root.live[e.key]; root.drop(e.key); } });
        entries = [e, ...entries].slice(0, limit);
        return e;
    }

    // a replaced notification (same id, new text) updates its entry
    function refresh(key: real): void {
        const n = live[key];
        if (!n) return;
        entries = entries.map(e => e.key === key ? Object.assign({}, e, { summary: n.summary, body: n.body, image: n.image, time: Date.now() }) : e);
    }

    function notif(key: real): Notification { return live[key] ?? null; }

    // run an action ("default" = clicking it) if the app still has it open
    function invoke(key: real, action: string): bool {
        const a = notif(key)?.actions.find(x => x.identifier === action);
        if (a) a.invoke();
        return !!a;
    }

    // remove from the history and tell the app it was dismissed
    function remove(key: real): void {
        const n = live[key];
        delete live[key];
        if (n) n.dismiss();
        drop(key);
    }
    function drop(key: real): void {
        entries = entries.filter(e => e.key !== key);
    }
    // every entry of one app (by name)
    function removeApp(app: string): void {
        // plain keys first: elements read from the entries list point into it
        // by position, so removing as we go would hit the wrong ones
        const keys = entries.filter(e => e.appName === app).map(e => e.key);
        for (const k of keys) remove(k);
    }
    function clear(): void {
        const all = live;
        live = {};          // so the closed handlers below don't edit entries mid-way
        entries = [];
        for (const k in all) all[k]?.dismiss();
    }

    // ── persistence ──
    property bool loaded: false
    onEntriesChanged: if (loaded) saveTimer.restart()
    Timer {
        id: saveTimer
        interval: 800
        onTriggered: store.setText(JSON.stringify({
            dnd: root.dnd,
            dndSince: root.dndSince,
            // images from image-data hints don't survive a restart
            entries: root.entries.map(e => Object.assign({}, e, {
                image: /^(\/|file:)/.test(e.image ?? "") ? e.image : "",
                actions: []
            }))
        }))
    }
    FileView {
        id: store
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/bead/notifications.json"
        blockLoading: true
        printErrors: false
        atomicWrites: true
        onLoaded: {
            try {
                const d = JSON.parse(text());
                root.entries = d.entries ?? [];
                root.dnd = !!d.dnd;
                root.dndSince = root.dnd ? (d.dndSince || Date.now()) : 0;
            } catch (e) {}
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true // first run: no file yet
    }
}
