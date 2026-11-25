pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config

// bead's right-click menu (opened through Menus, never made by hand). A popup
// window next to the pointer, so it works over the bar and the island as well
// as in windows; a click anywhere else, Escape, or picking something closes it.
//
// Rows: { t, g (icon), keys (shortcut, shown), enabled, checked (true/false;
// leave it out for a plain row), danger, sep (a line), sub ([rows], a submenu),
// act () }. Or `handle`: an app's own menu (a tray icon's), drawn the same way.
PopupWindow {
    id: pop
    property Item target
    property point at
    property var items: []
    property var handle: null
    // submenus opened: [{ title, items } | { title, handle }]
    property var stack: []
    readonly property var level: stack.length ? stack[stack.length - 1] : { items: pop.items, handle: pop.handle }
    property int hi: -1   // the row under the keys

    QsMenuOpener { id: opener; menu: pop.level.handle ?? null }
    readonly property var rows: level.handle
        ? (opener.children?.values ?? []).map(e => ({
            t: String(e.text ?? "").replace(/&(?!&)/g, ""), img: e.icon ?? "", sep: e.isSeparator, enabled: e.enabled,
            checked: e.buttonType === QsMenuButtonType.None ? undefined : e.checkState === Qt.Checked,
            radio: e.buttonType === QsMenuButtonType.RadioButton, sub: e.hasChildren, entry: e }))
        : (level.items ?? []).filter(r => r)

    anchor.item: target
    anchor.rect.x: at.x
    anchor.rect.y: at.y
    anchor.rect.width: 1
    anchor.rect.height: 1
    anchor.edges: Edges.Top | Edges.Left
    anchor.gravity: Edges.Bottom | Edges.Right
    grabFocus: true
    color: "transparent"
    implicitWidth: 248
    implicitHeight: card.height + 8
    Component.onCompleted: visible = true
    onVisibleChanged: if (!visible) destroy()

    function dismiss(): void { visible = false; }
    function usable(r: var): bool { return !!r && !r.sep && r.enabled !== false; }
    function pick(r: var): void {
        if (!usable(r)) return;
        if (r.sub) {
            stack = [...stack, r.entry ? { title: r.t, handle: r.entry } : { title: r.t, items: r.sub }];
            hi = -1;
            return;
        }
        if (r.entry) r.entry.triggered();
        else if (r.act) r.act();
        dismiss();
    }
    function back(): void { if (stack.length) { stack = stack.slice(0, -1); hi = -1; } else dismiss(); }
    function step(d: int): void {
        const n = rows.length;
        for (let i = 1; i <= n; i++) {
            const j = ((hi < 0 && d < 0 ? n : hi) + d * i + n * 2) % n;
            if (usable(rows[j])) { hi = j; return; }
        }
    }

    Rectangle {
        id: card
        x: 4; y: 4
        width: pop.implicitWidth - 8
        height: list.implicitHeight + 12
        radius: 14
        color: Qt.tint(Theme.frame, Qt.alpha(Theme.text, 0.07))
        border.width: 1
        border.color: Qt.alpha(Theme.text, 0.1)
        transformOrigin: Item.TopLeft
        focus: true
        Keys.onPressed: e => {
            if (e.key === Qt.Key_Escape) pop.dismiss();
            else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backspace) pop.back();
            else if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab) pop.step(1);
            else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) pop.step(-1);
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space || (e.key === Qt.Key_Right && pop.rows[pop.hi]?.sub)) pop.pick(pop.rows[pop.hi]);
            else return;
            e.accepted = true;
        }
        ParallelAnimation {
            running: true
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: Motion.ms(130) }
            NumberAnimation { target: card; property: "scale"; from: 0.94; to: 1; duration: Motion.ms(200); easing.type: Easing.OutBack }
        }

        Column {
            id: list
            x: 6; y: 6
            width: parent.width - 12
            // a submenu: its name, and the way back
            Rectangle {
                visible: pop.stack.length > 0
                width: parent.width; height: visible ? 32 : 0; radius: 9
                color: Qt.alpha(Theme.text, backMa.containsMouse ? 0.08 : 0)
                Row {
                    x: 6; anchors.verticalCenter: parent.verticalCenter; spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "chevron_left"; size: 16; color: Theme.subtext }
                    Text { anchors.verticalCenter: parent.verticalCenter; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: Theme.subtext; text: pop.stack.length ? pop.stack[pop.stack.length - 1].title : "" }
                }
                MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pop.back() }
            }
            Repeater {
                model: pop.rows
                Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool ok: pop.usable(modelData)
                    width: list.width
                    height: modelData.sep ? 9 : 32
                    Rectangle {
                        visible: !!row.modelData.sep
                        anchors.centerIn: parent
                        width: parent.width - 16; height: 1
                        color: Qt.alpha(Theme.text, 0.1)
                    }
                    Rectangle {
                        visible: !row.modelData.sep
                        anchors.fill: parent
                        radius: 9
                        color: row.modelData.danger && (ma.containsMouse || pop.hi === row.index) ? Qt.alpha(Theme.tone("error"), 0.16)
                            : Qt.alpha(Theme.text, row.ok && (ma.containsMouse || pop.hi === row.index) ? 0.08 : 0)
                        opacity: row.ok ? 1 : 0.4
                        Row {
                            x: 10; anchors.verticalCenter: parent.verticalCenter
                            spacing: 9
                            Item {
                                // the icon column: icons line up, and rows without one still align
                                width: 16; height: 16
                                anchors.verticalCenter: parent.verticalCenter
                                Icon {
                                    visible: !row.modelData.img && (!!row.modelData.g || row.modelData.checked !== undefined)
                                    anchors.centerIn: parent
                                    name: row.modelData.checked !== undefined && !row.modelData.g
                                        ? (row.modelData.radio ? (row.modelData.checked ? "radio_button_checked" : "radio_button_unchecked") : (row.modelData.checked ? "check" : ""))
                                        : (row.modelData.g ?? "")
                                    size: 16
                                    fill: row.modelData.checked ? 1 : 0
                                    color: row.modelData.danger ? Theme.tone("error") : row.modelData.checked ? Theme.tone("action") : Theme.text
                                }
                                Image {
                                    visible: !!row.modelData.img
                                    anchors.fill: parent
                                    source: row.modelData.img ?? ""
                                    sourceSize: Qt.size(32, 32)
                                    asynchronous: true
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: list.width - 54 - (keysT.visible ? keysT.implicitWidth + 8 : 0) - (row.modelData.sub ? 18 : 0)
                                elide: Text.ElideRight
                                font.family: Theme.font; font.pixelSize: 12
                                font.weight: row.modelData.checked ? Font.DemiBold : Font.Normal
                                color: row.modelData.danger ? Theme.tone("error") : Theme.text
                                text: row.modelData.t ?? ""
                            }
                        }
                        Text {
                            id: keysT
                            visible: !!row.modelData.keys && !row.modelData.sub
                            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                            font.family: Theme.font; font.pixelSize: 11; color: Theme.subtext
                            text: row.modelData.keys ?? ""
                        }
                        Icon {
                            visible: !!row.modelData.sub
                            anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
                            name: "chevron_right"; size: 16; color: Theme.subtext
                        }
                        // a check on a row that has its own icon
                        Icon {
                            visible: !!row.modelData.g && row.modelData.checked === true && !row.modelData.sub
                            anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                            name: "check"; size: 16; color: Theme.tone("action")
                        }
                    }
                    MouseArea {
                        id: ma
                        enabled: !row.modelData.sep
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: row.ok ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onEntered: pop.hi = row.ok ? row.index : -1
                        onClicked: pop.pick(row.modelData)
                    }
                }
            }
            Text {
                visible: pop.rows.length === 0
                width: list.width; height: 32
                verticalAlignment: Text.AlignVCenter; leftPadding: 10
                font.family: Theme.font; font.pixelSize: 12; color: Theme.subtext
                text: pop.level.handle ? "Nothing in this menu" : "Nothing to do here"
            }
        }
    }
}
