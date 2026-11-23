pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.components
import qs.config

// Workspace overview (Super+Tab): a card per workspace with live thumbnails of
// its windows where they really sit. Click a card to go there, a thumbnail to
// focus that window. ←/→ and Enter, 1-9 to jump, Esc closes.
Item {
    id: root
    signal close()

    readonly property real cardW: 236
    readonly property real gap: 12
    readonly property real pad: 18
    // workspaces that have windows, plus the one you're on; special ones left out
    readonly property list<var> spaces: Hyprland.workspaces.values
        .filter(w => w.id > 0 && (w.toplevels.values.length > 0 || w.focused))
        .sort((a, b) => a.id - b.id)
    property int current: 0
    // what the pointer is over (a window's title, or a workspace), shown under the cards
    property string caption: ""
    readonly property bool multiMonitor: Quickshell.screens.length > 1
    // the wallpaper's still (Caelestia keeps one even for live wallpapers), behind each card
    property string wallPath: ""
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/caelestia/wallpaper/path.txt"
        watchChanges: true
        printErrors: false
        onLoaded: root.wallPath = text().trim()
        onFileChanged: reload()
    }
    // staggered entrance, replayed on every open
    property real enter: 0
    NumberAnimation { id: enterAnim; target: root; property: "enter"; from: 0; to: 1; duration: 520 }
    readonly property real cardH: {
        let r = 9 / 16; // the tallest monitor's shape
        for (const w of spaces) { const m = mon(w); if (m.w > 0) r = Math.max(r, m.h / m.w); }
        return Math.round(cardW * Math.min(r, 0.75));
    }
    readonly property real wantW: Math.min(pad * 2 + spaces.length * cardW + Math.max(0, spaces.length - 1) * gap, 1500)
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
        enterAnim.restart();
    }
    function focusField(): void { keys.forceActiveFocus(); }

    Item {
        id: keys
        focus: true
        Keys.onPressed: e => {
            const n = root.spaces.length;
            if (e.key === Qt.Key_Escape || e.key === Qt.Key_Tab && (e.modifiers & Qt.MetaModifier)) root.close();
            else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab) root.current = (root.current + 1) % Math.max(1, n);
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab) root.current = (root.current - 1 + n) % Math.max(1, n);
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.go(root.current);
            else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9) {
                const i = root.spaces.findIndex(w => w.id === e.key - Qt.Key_0);
                if (i >= 0) root.go(i);
            } else return;
            e.accepted = true;
        }
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
        text: root.caption || "←/→ to choose  ·  Enter to go  ·  1-9 to jump  ·  click a window to focus it"
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
                        border.width: card.sel ? 2 : 1
                        border.color: card.sel ? Theme.tone("action") : Qt.alpha(Theme.text, 0.08)
                        scale: card.sel ? 1 : 0.97
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
                                    border.width: winMa.containsMouse ? 2 : 0
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
                                            source: thumb.app ? Quickshell.iconPath(DesktopEntries.heuristicLookup(thumb.app)?.icon ?? thumb.app, true) : ""
                                        }
                                    }
                                    MouseArea {
                                        id: winMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: { root.current = card.index; root.caption = thumb.modelData.title || thumb.app; }
                                        onExited: root.caption = ""
                                        onClicked: root.focusWindow(thumb.modelData)
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
        }
    }
}
