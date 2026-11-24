pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "focusnav.js" as Nav
import qs.components
import qs.config
import qs.services

// The dashboard's insides: a tab bar (springy highlight pill, scroll to switch)
// flanked by volume and brightness sliders, and pages that slide between tabs:
// Dashboard, Media, Performance, Weather, Timers, Wallpapers, Settings.
Item {
    id: root

    required property var clock            // SystemClock
    required property MprisPlayer player
    required property ShellScreen screen   // for its brightness
    property int tab: 0                    // shown tab (owner keeps it)
    signal pick(MprisPlayer p)
    signal select(int tab)
    signal close()

    // ── the keyboard (focusnav.js). Only when it was opened by key: then 1-7 and
    // Ctrl+Tab switch tabs, arrows move a ring to the nearest control that way
    // (Left/Right adjust a slider or a choice instead), Enter or Space presses
    // it, Tab steps through in reading order, Esc closes. A control is a stop
    // if it has `focusStop: true`, with focusPress() and maybe focusAdjust(dir).
    // The ring shows from the first key and goes when the mouse moves ──
    property bool keys: false      // the ring is showing
    property Item cur: null        // the control it's on
    function takeKeys(): void { cur = null; keys = false; forceActiveFocus(); }
    onTabChanged: cur = null
    onVisibleChanged: if (!visible) { cur = null; keys = false; }
    // the stops on screen now: { x, y, w, h, item }
    function stops(): var {
        const out = [];
        const walk = it => {
            if (!it || !it.visible || it.opacity < 0.05) return;
            if (it.focusStop === true && it.width > 0 && it.height > 0) {
                const p = it.mapToItem(root, 0, 0);
                if (p.x + it.width > 4 && p.x < root.width - 4 && p.y + it.height > 4 && p.y < root.height - 4)
                    out.push({ x: p.x, y: p.y, w: it.width, h: it.height, item: it });
                return;
            }
            const kids = it.children;
            for (let i = 0; i < kids.length; i++) walk(kids[i]);
        };
        walk(root);
        return out;
    }
    function go(pickNext: var): void {
        const all = stops();
        const from = all.find(r => r.item === cur) ?? null;
        // the first key puts the ring on the tab's first control, under the tab bar
        const to = from || !all.length ? pickNext(all, from) : (Nav.order(all.filter(r => r.y > 56))[0] ?? Nav.order(all)[0]);
        if (to) { cur = to.item; ring.place(); }
        keys = !!cur;
    }
    readonly property var keyNames: ({ [Qt.Key_Left]: "Left", [Qt.Key_Right]: "Right", [Qt.Key_Up]: "Up", [Qt.Key_Down]: "Down",
        [Qt.Key_Tab]: "Tab", [Qt.Key_Backtab]: "Tab", [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Return", [Qt.Key_Space]: "Space", [Qt.Key_Escape]: "Escape" })
    Keys.onPressed: e => {
        const field = root.Window.activeFocusItem;
        const editing = !!field && field !== root && field.cursorPosition !== undefined;
        const name = keyNames[e.key] ?? (/^[1-9\[\]t]$/.test(e.text) ? e.text : "");
        if (root.handle(name, editing, !!(e.modifiers & Qt.ControlModifier), !!(e.modifiers & Qt.ShiftModifier) || e.key === Qt.Key_Backtab))
            e.accepted = true;
    }
    // one key, by name ("Down", "Return", "3", "]"…): what a real key press does,
    // and what `qs ipc call dashboard key <name>` sends. True when it was used.
    function handle(name: string, editing: bool, ctrl: bool, shift: bool): bool {
        // a control with keys of its own (the calendar) gets the first go
        if (!editing && keys && cur && typeof cur.focusKey === "function" && cur.focusKey(name)) { ring.place(); return true; }
        const a = Nav.action(name, { tabs: tabs.length, tab: tab, editing: editing,
            adjustable: !!cur && typeof cur.focusAdjust === "function", ctrl: ctrl, shift: shift });
        switch (a.type) {
        case "tab": root.select(a.index); break;
        case "move": go((all, from) => Nav.nearest(all, from, a.dir)); break;
        case "step": go((all, from) => Nav.step(all, from, a.dir)); break;
        case "adjust": keys = true; cur.focusAdjust(a.dir); break;
        case "press": if (cur && keys && typeof cur.focusPress === "function") cur.focusPress(); break;
        case "leave": root.forceActiveFocus(); break;
        case "close": root.close(); break;
        default: return false;
        }
        return true;
    }
    HoverHandler { onPointChanged: if (root.keys) root.keys = false } // the mouse takes over: no ring
    Rectangle {
        id: ring
        z: 100
        visible: opacity > 0.01
        opacity: root.keys && root.cur ? 1 : 0
        color: "transparent"
        border.width: 2
        border.color: Theme.tone("action")
        property rect at: Qt.rect(0, 0, 0, 0)
        function place(): void {
            const c = root.cur;
            if (!c || !c.visible) { root.cur = null; return; }
            const p = c.mapToItem(root, 0, 0);
            at = Qt.rect(p.x, p.y, c.width, c.height);
            radius = (c.focusRadius ?? c.radius ?? Math.min(c.width, c.height) / 2) + 4;
        }
        x: at.x - 4; y: at.y - 4
        width: at.width + 8; height: at.height + 8
        Behavior on x { SpringAnimation { spring: 5; damping: 0.4; epsilon: 0.2 } }
        Behavior on y { SpringAnimation { spring: 5; damping: 0.4; epsilon: 0.2 } }
        Behavior on width { SpringAnimation { spring: 5; damping: 0.4; epsilon: 0.2 } }
        Behavior on height { SpringAnimation { spring: 5; damping: 0.4; epsilon: 0.2 } }
        Behavior on opacity { NumberAnimation { duration: 140 } }
        // it follows its control while things settle (a tab sliding in, a list reflowing)
        Timer { interval: 120; repeat: true; running: ring.visible; onTriggered: ring.place() }
    }

    readonly property var tabs: [
        { name: "Dashboard", icon: "dashboard" },
        { name: "Media", icon: "queue_music" },
        { name: "Performance", icon: "monitoring" },
        { name: "Weather", icon: "partly_cloudy_day" },
        { name: "Timers", icon: "timer" },
        { name: "Wallpapers", icon: "wallpaper" },
        { name: "Settings", icon: "settings" }
    ]

    // ── a small horizontal slider: icon (click) + track (drag / scroll) + value ──
    component QuickSlider: Row {
        id: qs
        property string icon: ""
        property real value: 0
        property bool dim: false
        signal moved(real v)
        signal nudged(int dir)
        signal iconClicked()
        readonly property bool focusStop: true   // Left/Right nudge it, Enter its icon (mute)
        readonly property real focusRadius: 19
        function focusAdjust(dir: int): void { qs.nudged(dir); }
        function focusPress(): void { qs.iconClicked(); }
        spacing: 8
        height: 38
        readonly property color tone: dim ? Theme.neutral : Theme.tone("action")

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 30; height: 30; radius: 15
            color: Qt.alpha(qs.tone, iconMa.containsMouse ? 0.22 : 0.12)
            Behavior on color { ColorAnimation { duration: 150 } }
            Icon { anchors.centerIn: parent; name: qs.icon; size: 17; fill: 1; color: qs.tone }
            MouseArea { id: iconMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: qs.iconClicked() }
        }
        Item {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: 110; height: 20
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: area.containsMouse || area.pressed ? 8 : 6
                radius: height / 2
                color: Qt.alpha(qs.tone, 0.16)
                Behavior on height { NumberAnimation { duration: 150 } }
                Rectangle {
                    height: parent.height
                    radius: height / 2
                    width: Math.max(height, parent.width * Math.max(0, Math.min(1, qs.value)))
                    color: qs.tone
                    Behavior on width { SpringAnimation { spring: area.pressed ? 9 : 4.5; damping: area.pressed ? 0.45 : 0.28; epsilon: 0.2 } }
                }
            }
            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                function at(x: real): real { return Math.max(0, Math.min(1, x / width)); }
                onPressed: e => qs.moved(at(e.x))
                onPositionChanged: e => { if (pressed) qs.moved(at(e.x)); }
                onWheel: e => qs.nudged(e.angleDelta.y > 0 ? 1 : -1)
            }
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            font.pixelSize: 11
            font.weight: Font.Medium
            font.features: { "tnum": 1 }
            color: Theme.text
            text: qs.dim ? "off" : Math.round(qs.value * 100)
        }
    }

    // volume, left of the tabs
    QuickSlider {
        x: 22
        y: 12
        icon: Audio.muted || Audio.volume <= 0 ? "volume_off" : Audio.volume < 0.5 ? "volume_down" : "volume_up"
        value: Audio.muted ? 0 : Audio.volume
        dim: Audio.muted
        onMoved: v => Audio.setVolume(v)
        onNudged: dir => Audio.setVolume(Audio.volume + dir * 0.05)
        onIconClicked: Audio.toggleMute()
    }
    // brightness, right of the tabs
    QuickSlider {
        anchors.right: parent.right
        anchors.rightMargin: 22
        y: 12
        visible: Brightness.has(root.screen)
        icon: "light_mode"
        value: Brightness.values[root.screen?.name ?? ""] ?? 0.5
        onMoved: v => Brightness.set(root.screen, v)
        onNudged: dir => Brightness.change(root.screen, dir * 5)
    }

    // ── tab bar ──
    Item {
        id: bar
        anchors.horizontalCenter: parent.horizontalCenter
        y: 12
        width: tabRow.width
        height: 38

        Rectangle { // the highlight pill springs to the current tab
            readonly property Item target: tabRow.children[root.tab] ?? null
            x: target?.x ?? 0
            width: target?.width ?? 0
            height: parent.height
            radius: height / 2
            color: Qt.alpha(Theme.text, 0.09)
            Behavior on x { SpringAnimation { spring: 4; damping: 0.32; epsilon: 0.2 } }
            Behavior on width { SpringAnimation { spring: 4; damping: 0.32; epsilon: 0.2 } }
        }

        Row {
            id: tabRow
            height: parent.height
            Repeater {
                model: root.tabs
                Item {
                    id: tb
                    required property var modelData
                    required property int index
                    readonly property bool current: root.tab === index
                    readonly property bool focusStop: true
                    readonly property real focusRadius: height / 2
                    function focusPress(): void { root.select(tb.index); }
                    // only the current tab shows its name; it slides open as you switch
                    width: tbRow.implicitWidth + 24
                    height: parent.height
                    Row {
                        id: tbRow
                        anchors.centerIn: parent
                        spacing: tb.current ? 7 : 0
                        Behavior on spacing { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: tb.modelData.icon
                            size: 19
                            fill: tb.current ? 1 : 0
                            color: tb.current ? Theme.text : Theme.subtext
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        Text {
                            id: tbName
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: Theme.text
                            text: tb.modelData.name
                            clip: true
                            width: tb.current ? implicitWidth : 0
                            opacity: tb.current ? 1 : 0
                            Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 200 } }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.select(tb.index)
                    }
                }
            }
        }
        WheelHandler {
            onWheel: e => root.select(Math.max(0, Math.min(root.tabs.length - 1, root.tab + (e.angleDelta.y < 0 ? 1 : -1))))
        }
    }

    // ── pages: only two ever move. Switching tabs, the new page glides in
    // from the side of its tab while the old one drifts the other way and
    // fades out early, however far apart the tabs are (no pages in between
    // flash past). A switch mid-way (scrolling through tabs) takes over from
    // wherever the outgoing page had got to. ──
    Item {
        id: pages
        x: 20
        y: 64
        width: root.width - 40
        height: root.height - 64 - 20

        property int cur: root.tab   // the page arriving (or shown)
        property int prev: -1        // the page leaving
        property int dir: 1          // +1: the new tab is to the right
        property real t: 1           // 0 → 1 over a switch
        property real outFrom: 1     // how visible the leaving page was when it started leaving

        Connections {
            target: root
            function onTabChanged(): void {
                if (root.tab === pages.cur) return;
                pages.outFrom = pages.t;
                pages.prev = pages.cur;
                pages.dir = root.tab > pages.cur ? 1 : -1;
                pages.cur = root.tab;
                swap.restart();
            }
        }
        NumberAnimation { id: swap; target: pages; property: "t"; from: 0; to: 1; duration: 520; easing.type: Easing.OutQuint }

        component Page: Item {
            property int index: 0
            readonly property bool arriving: index === pages.cur
            readonly property bool leaving: index === pages.prev && pages.t < 1 && !arriving
            width: pages.width
            height: pages.height
            x: arriving ? pages.dir * 64 * (1 - pages.t) : leaving ? -pages.dir * 40 * pages.t : 0
            opacity: arriving ? Math.min(1, pages.t * 1.25) : leaving ? pages.outFrom * Math.max(0, 1 - pages.t * 2.4) : 0
            scale: arriving ? 0.975 + 0.025 * pages.t : leaving ? 1 - 0.03 * pages.t : 1
            z: arriving ? 1 : 0
            visible: opacity > 0.01
            enabled: arriving
        }

        Page {
            index: 0
            DashTab { anchors.fill: parent; clock: root.clock; player: root.player }
        }
        Page {
            index: 1
            MediaTab { anchors.fill: parent; player: root.player; onPick: p => root.pick(p) }
        }
        Page {
            index: 2
            PerfTab { anchors.fill: parent }
        }
        Page {
            index: 3
            WeatherTab { anchors.fill: parent }
        }
        Page {
            index: 4
            TimersTab { anchors.fill: parent }
        }
        Page {
            index: 5
            WallpapersTab { anchors.fill: parent }
        }
        Page {
            index: 6
            SettingsTab { anchors.fill: parent }
        }
    }

    // ── the hint strip: while the ring shows, the keys its control takes,
    // in the margin under the pages ──
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height - 17
        font.family: Theme.font
        font.pixelSize: 10
        color: Qt.alpha(Theme.text, 0.45)
        opacity: root.keys ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: 160 } }
        text: {
            const c = root.cur;
            return Nav.hints(c ? { press: typeof c.focusPress === "function", adjust: typeof c.focusAdjust === "function", calendar: !!c.focusCalendar } : null);
        }
    }
}
