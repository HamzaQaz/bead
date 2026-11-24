pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services
import "overview.js" as Ov

// Workspace overview (Super+Tab): a card per workspace with live thumbnails of
// its windows where they really sit. Click a card to go there, a thumbnail to
// focus that window; drag a thumbnail onto another card (or the "+" after the
// last one, for a new workspace) to move it. ←/→ and Enter, 1-9 to jump, ↓/↑
// to pick a window in the card; on the picked (or hovered) window f floats,
// x closes and p pins it. Esc closes.
Item {
    id: root
    signal close()

    readonly property real gap: 12
    readonly property real pad: 18
    // the island's window clips: stay inside it (passed in). Cards shrink to fit
    // every workspace in view (to 150; past that the strip scrolls)
    property real maxW: 940
    readonly property real cardW: {
        const n = Math.max(1, spaces.length);
        return Math.round(Math.max(150, Math.min(236, (maxW - pad * 2 - (n - 1) * gap) / n)));
    }
    // workspaces that have windows, plus the one you're on; special ones left out
    readonly property list<var> spaces: Hyprland.workspaces.values
        .filter(w => w.id > 0 && (w.toplevels.values.length > 0 || w.focused))
        .sort((a, b) => a.id - b.id)
    property int current: 0
    // what the pointer is over (a window's title, or a workspace), shown under the cards
    property string caption: ""
    readonly property bool multiMonitor: Quickshell.screens.length > 1
    // the wallpaper's still (Caelestia keeps one even for live wallpapers), behind each card
    readonly property string wallPath: Wallpaper.stillPath
    // staggered entrance, replayed on every open
    property real enter: 0
    NumberAnimation { id: enterAnim; target: root; property: "enter"; from: 0; to: 1; duration: 520 }
    readonly property real cardH: {
        let r = 9 / 16; // the tallest monitor's shape
        for (const w of spaces) { const m = mon(w); if (m.w > 0) r = Math.max(r, m.h / m.w); }
        return Math.round(cardW * Math.min(r, 0.75));
    }
    readonly property real newW: 44   // the "+" drop target after the last card
    readonly property real wantW: Math.min(pad * 2 + spaces.length * (cardW + gap) + newW, maxW)
    readonly property real wantH: pad + 22 + 8 + cardH + 10 + 18 + pad

    // a workspace's monitor, in logical pixels
    function mon(w: var): var {
        const o = w?.monitor?.lastIpcObject ?? {};
        const s = o.scale || 1;
        const rot = (o.transform ?? 0) % 2 === 1;
        return { x: o.x ?? 0, y: o.y ?? 0, w: (rot ? o.height : o.width) / s || 0, h: (rot ? o.width : o.height) / s || 0 };
    }
    function go(i: int): void {
        const w = spaces[i];
        if (!w) return;
        close();
        Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ workspace = "${w.id}" })`]);
    }
    function focusWindow(t: var): void {
        close();
        const a = String(t.address);
        Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.focus({ window = "address:${a.startsWith("0x") ? a : "0x" + a}" })`]);
    }
    // called on open: fresh positions, and start on the workspace you're on
    function reset(): void {
        Hyprland.refreshMonitors();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshToplevels();
        current = Math.max(0, spaces.findIndex(w => w.focused));
        caption = "";
        pick = -1;
        hoverWin = null;
        enterAnim.restart();
    }

    // ── a window to act on: ↓/↑ picks one in the selected card (in reading
    // order), else the one under the pointer ──
    property int pick: -1
    property var hoverWin: null
    onCurrentChanged: pick = -1
    readonly property var curWins: Ov.readingOrder((spaces[current]?.toplevels.values ?? []).filter(t => !t.lastIpcObject?.hidden), t => t.lastIpcObject?.at)
    readonly property var picked: pick >= 0 ? curWins[pick] ?? null : hoverWin
    function addr(t: var): string { const a = String(t.address); return "address:" + (a.startsWith("0x") ? a : "0x" + a); }
    property var floatedToPin: ({})   // windows floated only so they could be pinned
    function act(kind: string, t: var): void {
        if (!t) return;
        const name = t.title || t.wayland?.appId || "window";
        const w = `window = "${addr(t)}"`;
        if (kind === "float") { Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.window.float({ action = "toggle", ${w} })`]); caption = (t.lastIpcObject?.floating ? "Tiled " : "Floating ") + name; }
        else if (kind === "pin") {
            // Hyprland pins only floating windows: float a tiled one first,
            // and tile it again when it's unpinned
            const ipc = t.lastIpcObject ?? {};
            const key = addr(t);
            const pin = `hl.dsp.window.pin({ ${w} })`;
            const fl = `hl.dsp.window.float({ action = "toggle", ${w} })`;
            if (ipc.pinned) {
                const back = !!floatedToPin[key];
                Quickshell.execDetached(["sh", "-c", back ? 'hyprctl dispatch "$1" && hyprctl dispatch "$2"' : 'hyprctl dispatch "$1"', "sh", pin, fl]);
                const f = Object.assign({}, floatedToPin); delete f[key]; floatedToPin = f;
                caption = "Unpinned " + name;
            } else {
                Quickshell.execDetached(["sh", "-c", ipc.floating ? 'hyprctl dispatch "$2"' : 'hyprctl dispatch "$1" && hyprctl dispatch "$2"', "sh", fl, pin]);
                if (!ipc.floating) { const f = Object.assign({}, floatedToPin); f[key] = true; floatedToPin = f; }
                caption = "Pinned " + name;
            }
        }
        else if (kind === "close") { Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.window.close({ ${w} })`]); caption = "Closed " + name; if (hoverWin === t) hoverWin = null; }
        refreshTimer.restart();
    }
    function focusField(): void { keys.forceActiveFocus(); }

    // ── drag a window onto another card to move it there (you stay put) ──
    property var dragging: null     // the HyprlandToplevel being dragged
    property real dragW: 0
    property real dragH: 0
    property point dragPos: Qt.point(0, 0)
    property int dropIndex: -1
    function cardAt(p: point): int {
        if (p.y < strip.y || p.y > strip.y + strip.height) return -1;
        const x = p.x - strip.x + strip.contentX;
        const i = Math.floor(x / (cardW + gap));
        const into = x - i * (cardW + gap);
        if (i === spaces.length) return into <= newW ? i : -1;   // the "+"
        return i >= 0 && i < spaces.length && into <= cardW ? i : -1;
    }
    function moveWindow(t: var, w: var): void {
        Quickshell.execDetached(["hyprctl", "dispatch", `hl.dsp.window.move({ workspace = "${w.id}", window = "${addr(t)}", follow = false })`]);
        if (spaces.indexOf(w) >= 0) current = spaces.indexOf(w);
        caption = "Moved to workspace " + (w.name || w.id);
        refreshTimer.restart();
    }
    // onto a workspace of its own: the lowest free number (it opens on the
    // monitor you're on, as a new workspace does in Hyprland)
    function moveToNew(t: var): void {
        moveWindow(t, { id: Ov.freeWorkspace(Hyprland.workspaces.values.map(w => w.id)) });
    }
    // positions come from Hyprland's IPC snapshot: take a fresh one after a move
    Timer { id: refreshTimer; interval: 180; onTriggered: { Hyprland.refreshWorkspaces(); Hyprland.refreshToplevels(); } }

    // a key, from the keyboard or `qs ipc call overview key <name>`; true if used
    function handle(key: int, mods: int): bool {
        const n = root.spaces.length;
        if (key === Qt.Key_Escape || key === Qt.Key_Tab && (mods & Qt.MetaModifier)) root.close();
        else if (key === Qt.Key_Right || key === Qt.Key_Tab) root.current = (root.current + 1) % Math.max(1, n);
        else if (key === Qt.Key_Left || key === Qt.Key_Backtab) root.current = (root.current - 1 + n) % Math.max(1, n);
        else if (key === Qt.Key_Down) root.pick = Ov.step(root.pick, root.curWins.length, 1);
        else if (key === Qt.Key_Up) root.pick = Ov.step(root.pick, root.curWins.length, -1);
        else if (key === Qt.Key_Return || key === Qt.Key_Enter) { if (root.pick >= 0 && root.picked) root.focusWindow(root.picked); else root.go(root.current); }
        else if (key === Qt.Key_F && !mods) root.act("float", root.picked);
        else if (key === Qt.Key_X && !mods) root.act("close", root.picked);
        else if (key === Qt.Key_P && !mods) root.act("pin", root.picked);
        else if (key >= Qt.Key_1 && key <= Qt.Key_9) {
            const i = root.spaces.findIndex(w => w.id === key - Qt.Key_0);
            if (i >= 0) root.go(i);
        } else return false;
        return true;
    }
    function press(name: string): bool {
        const k = { left: Qt.Key_Left, right: Qt.Key_Right, up: Qt.Key_Up, down: Qt.Key_Down, enter: Qt.Key_Return, esc: Qt.Key_Escape, f: Qt.Key_F, x: Qt.Key_X, p: Qt.Key_P }[name]
            ?? (/^[1-9]$/.test(name) ? Qt.Key_0 + Number(name) : 0);
        return k ? handle(k, 0) : false;
    }

    Item {
        id: keys
        focus: true
        Keys.onPressed: e => { if (root.handle(e.key, e.modifiers)) e.accepted = true; }
    }

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.pad - 2
        width: parent.width - root.pad * 2
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        font.pixelSize: 12
        opacity: root.enter
        text: root.caption || (root.picked ? (root.picked.title || "Window") + "  ·  f float  ·  x close  ·  p pin" + (root.pick >= 0 ? "  ·  Enter focus" : "")
            : "←/→ choose  ·  ↓ pick a window  ·  Enter go  ·  drag a window to move it")
    }

    Flickable {
        id: strip
        x: root.pad
        y: root.pad
        width: root.width - root.pad * 2
        height: 22 + 8 + root.cardH + 4
        contentWidth: row.width
        interactive: contentWidth > width
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        // keep the selected card in view
        readonly property real target: Math.max(0, Math.min(contentWidth - width, root.current * (root.cardW + root.gap) - (width - root.cardW) / 2))
        onTargetChanged: contentX = target
        Behavior on contentX { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        Row {
            id: row
            spacing: root.gap
            Repeater {
                model: root.spaces
                Column {
                    id: card
                    required property var modelData
                    required property int index
                    readonly property bool sel: index === root.current
                    readonly property var m: root.mon(modelData)
                    spacing: 8
                    // each card rises in a little after the one before
                    readonly property real t: Math.max(0, Math.min(1, (root.enter * 520 - index * 45) / 260))
                    opacity: t
                    transform: Translate { y: 10 * (1 - card.t) * (1 - card.t) }
                    Row { // label: number, and a dot on the one you're on
                        x: 4
                        spacing: 6
                        height: 22
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: card.sel ? Theme.text : Theme.subtext
                            text: card.modelData.name || card.modelData.id
                        }
                        Rectangle {
                            visible: card.modelData.focused
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6; height: 6; radius: 3
                            color: Theme.tone("action")
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            font.pixelSize: 11
                            visible: root.multiMonitor
                            text: card.modelData.monitor?.name ?? ""
                        }
                    }
                    Rectangle {
                        id: frame
                        width: root.cardW
                        height: root.cardH
                        radius: 14
                        color: Qt.alpha(Theme.text, cardMa.containsMouse ? 0.09 : 0.05)
                        readonly property bool dropTarget: !!root.dragging && root.dropIndex === card.index
                        border.width: card.sel || dropTarget ? 2 : 1
                        border.color: dropTarget ? Theme.tone("success") : card.sel ? Theme.tone("action") : Qt.alpha(Theme.text, 0.08)
                        scale: dropTarget ? 1.03 : card.sel ? 1 : 0.97
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        readonly property real k: card.m.w > 0 ? Math.min(width / card.m.w, height / card.m.h) : 0
                        MouseArea {
                            id: cardMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: { root.current = card.index; root.caption = "Go to workspace " + (card.modelData.name || card.modelData.id); }
                            onExited: root.caption = ""
                            onClicked: root.go(card.index)
                        }
                        ClippingRectangle { // the wallpaper, dimmed so windows stand out
                            anchors.fill: parent
                            anchors.margins: frame.border.width
                            radius: frame.radius - frame.border.width
                            color: "transparent"
                            visible: wallImg.status === Image.Ready
                            Image {
                                id: wallImg
                                anchors.fill: parent
                                source: root.wallPath ? "file://" + root.wallPath : ""
                                sourceSize: Qt.size(root.cardW * 2, root.cardH * 2)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                opacity: 0.55
                            }
                        }
                        Item { // the monitor, scaled into the card
                            anchors.centerIn: parent
                            width: card.m.w * frame.k
                            height: card.m.h * frame.k
                            clip: true
                            Repeater {
                                model: card.modelData.toplevels.values
                                Rectangle {
                                    id: thumb
                                    required property var modelData
                                    readonly property var o: modelData.lastIpcObject ?? {}
                                    readonly property bool known: !!o.at && !!o.size
                                    readonly property string app: modelData.wayland?.appId ?? o.class ?? ""
                                    visible: known && !o.hidden
                                    x: known ? (o.at[0] - card.m.x) * frame.k : 0
                                    y: known ? (o.at[1] - card.m.y) * frame.k : 0
                                    width: known ? o.size[0] * frame.k : 0
                                    height: known ? o.size[1] * frame.k : 0
                                    z: o.floating ? 1 : 0
                                    radius: 6
                                    color: Qt.alpha(Theme.frame, 0.9)
                                    border.width: winMa.containsMouse || root.pick >= 0 && root.picked === modelData ? 2 : 0
                                    border.color: Theme.tone("action")
                                    ScreencopyView {
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        captureSource: root.visible ? thumb.modelData.wayland : null
                                        live: true
                                    }
                                    Rectangle { // which app
                                        readonly property real sz: Math.max(14, Math.min(22, Math.min(thumb.width, thumb.height) * 0.3))
                                        visible: badgeImg.status === Image.Ready && thumb.width > 30
                                        x: 4; y: thumb.height - height - 4
                                        width: sz; height: sz; radius: sz * 0.3
                                        color: Qt.alpha(Theme.frame, 0.85)
                                        Image {
                                            id: badgeImg
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            sourceSize: Qt.size(48, 48)
                                            asynchronous: true
                                            source: Apps.iconFor(thumb.app)
                                        }
                                    }
                                    property real dragOp: root.dragging === modelData ? 0.3 : 1
                                    Behavior on dragOp { NumberAnimation { duration: 160 } }
                                    // a window arriving (dropped here, or opened) eases in
                                    property real arriveOp: 1
                                    property real arriveScale: 1
                                    opacity: dragOp * arriveOp
                                    scale: arriveScale
                                    Component.onCompleted: if (root.visible && root.enter >= 1) arrive.restart()
                                    ParallelAnimation {
                                        id: arrive
                                        NumberAnimation { target: thumb; property: "arriveScale"; from: 0.6; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                                        NumberAnimation { target: thumb; property: "arriveOp"; from: 0; to: 1; duration: 220 }
                                    }
                                    MouseArea {
                                        id: winMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        preventStealing: true
                                        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                        property point start
                                        onEntered: if (!root.dragging) { root.current = card.index; root.hoverWin = thumb.modelData; root.caption = ""; }
                                        onExited: if (!root.dragging && root.hoverWin === thumb.modelData) root.hoverWin = null
                                        onPressed: e => start = Qt.point(e.x, e.y)
                                        onPositionChanged: e => {
                                            if (!pressed) return;
                                            if (!root.dragging && Math.hypot(e.x - start.x, e.y - start.y) < 6) return;
                                            if (!root.dragging) {
                                                root.dragging = thumb.modelData;
                                                root.dragW = Math.min(120, thumb.width);
                                                root.dragH = root.dragW * thumb.height / Math.max(1, thumb.width);
                                                root.dragPos = mapToItem(root, e.x, e.y);
                                                ghost.src = thumb.modelData;
                                                landing.stop();
                                                lift.restart();
                                                ghost.follow = true;
                                            }
                                            root.dragPos = mapToItem(root, e.x, e.y);
                                            root.dropIndex = root.cardAt(root.dragPos);
                                            const w = root.spaces[root.dropIndex];
                                            root.caption = root.dropIndex === root.spaces.length ? "Move to a new workspace"
                                                : w && w !== card.modelData ? "Move to workspace " + (w.name || w.id) : "Drop on another workspace, or + for a new one";
                                        }
                                        onReleased: {
                                            const t = root.dragging;
                                            if (!t) { root.focusWindow(thumb.modelData); return; }
                                            const i = root.dropIndex;
                                            const w = root.spaces[i];
                                            root.dragging = null;
                                            root.dropIndex = -1;
                                            if (i === root.spaces.length) { ghost.land(root.cardCentre(i), true); root.moveToNew(t); }
                                            else if (w && w !== card.modelData) { ghost.land(root.cardCentre(i), true); root.moveWindow(t, w); }
                                            else { ghost.land(thumb.mapToItem(root, thumb.width / 2, thumb.height / 2), false); root.caption = ""; }
                                        }
                                    }
                                }
                            }
                        }
                        Label {
                            anchors.centerIn: parent
                            visible: card.modelData.toplevels.values.length === 0
                            text: "Empty"
                        }
                    }
                }
            }
            // drop a window here for a workspace of its own
            Item {
                width: root.newW
                height: 30 + root.cardH
                readonly property bool over: !!root.dragging && root.dropIndex === root.spaces.length
                opacity: root.enter * (root.dragging ? 1 : 0.45)
                Behavior on opacity { NumberAnimation { duration: 160 } }
                Rectangle {
                    y: 30
                    width: parent.width
                    height: root.cardH
                    radius: 14
                    color: Qt.alpha(parent.over ? Theme.tone("success") : Theme.text, parent.over ? 0.14 : 0.04)
                    border.width: parent.over ? 2 : 1
                    border.color: parent.over ? Theme.tone("success") : Qt.alpha(Theme.text, 0.1)
                    scale: parent.over ? 1.05 : 1
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Icon { anchors.centerIn: parent; name: "add"; size: 20; color: parent.parent.over ? Theme.tone("success") : Theme.subtext }
                }
            }
        }
    }

    // the window being dragged: lifts out of its thumbnail, trails the pointer
    // on a spring, then flies into the card it's dropped on (or back home)
    Item {
        id: ghost
        property var src: null
        property bool follow: false   // springs after the pointer while dragging
        visible: !!src
        z: 10
        width: root.dragW
        height: root.dragH
        x: root.dragPos.x - width / 2
        y: root.dragPos.y - height / 2
        Behavior on x { enabled: ghost.follow; SpringAnimation { spring: 7; damping: 0.55; epsilon: 0.3 } }
        Behavior on y { enabled: ghost.follow; SpringAnimation { spring: 7; damping: 0.55; epsilon: 0.3 } }
        Rectangle {
            id: ghostCard
            anchors.fill: parent
            radius: 6
            color: Theme.frame
            border.width: 2
            border.color: Theme.tone(root.dropIndex >= 0 ? "success" : "action")
            Behavior on border.color { ColorAnimation { duration: 150 } }
            ScreencopyView {
                anchors.fill: parent
                anchors.margins: 2
                captureSource: ghost.src?.wayland ?? null
                live: false
            }
        }
        ParallelAnimation {
            id: lift
            NumberAnimation { target: ghostCard; property: "scale"; from: 0.7; to: 1.06; duration: 200; easing.type: Easing.OutBack; easing.overshoot: 2 }
            NumberAnimation { target: ghostCard; property: "opacity"; from: 0.4; to: 0.92; duration: 160 }
        }
        // fly to a point (in root), shrink and fade, then hide
        function land(p: point, into: bool): void {
            follow = false;
            landX.to = p.x - width / 2; landY.to = p.y - height / 2;
            landScale.to = into ? 0.25 : 1; landOp.to = into ? 0 : 0;
            landing.restart();
        }
        ParallelAnimation {
            id: landing
            NumberAnimation { id: landX; target: ghost; property: "x"; duration: 260; easing.type: Easing.InOutCubic }
            NumberAnimation { id: landY; target: ghost; property: "y"; duration: 260; easing.type: Easing.InOutCubic }
            NumberAnimation { id: landScale; target: ghostCard; property: "scale"; duration: 260; easing.type: Easing.InCubic }
            NumberAnimation { id: landOp; target: ghostCard; property: "opacity"; duration: 260; easing.type: Easing.InCubic }
            onFinished: { ghost.src = null; ghost.x = Qt.binding(() => root.dragPos.x - ghost.width / 2); ghost.y = Qt.binding(() => root.dragPos.y - ghost.height / 2); }
        }
    }
    // where a card's centre is, in root
    function cardCentre(i: int): point {
        return Qt.point(strip.x - strip.contentX + i * (cardW + gap) + (i === spaces.length ? newW : cardW) / 2, strip.y + 30 + cardH / 2);
    }
}
