pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.config
import qs.services
import "../../services/displays.js" as D
import "../../services/demo.js" as DemoData

// Displays: the monitors drawn where they sit, to scale. Drag one to move it
// (it snaps against the others); pick one for its refresh rate, scale and
// rotation. Each change is a trial that goes back by itself after 15 s unless
// kept (services/Displays.qml), and keeping saves it.
Item {
    id: root

    onVisibleChanged: if (visible) Displays.refresh()
    Component.onCompleted: Displays.refresh()
    property string chosen: ""
    readonly property var sel: Displays.monitors.find(m => m.name === chosen) ?? Displays.monitors.find(m => m.focused) ?? Displays.monitors[0] ?? null

    // a label on the left, its control after it
    component Setting: Row {
        property alias text: lbl.text
        spacing: 10
        Label { id: lbl; width: 62; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
    }

    // ── the map ──
    Card {
        id: map
        width: parent.width - side.width - 14
        height: parent.height

        Label { x: 18; y: 14; text: "Displays · drag to arrange"; font.pixelSize: 13; color: Theme.text }

        Item {
            id: area
            x: 20; y: 44
            width: parent.width - 40
            height: parent.height - 64
            readonly property var rects: Displays.monitors.map(m => D.logical(m))
            readonly property real bx: Math.min(...rects.map(r => r.x), 0)
            readonly property real by: Math.min(...rects.map(r => r.y), 0)
            readonly property real bw: Math.max(1, Math.max(...rects.map(r => r.x + r.w), 1) - bx)
            readonly property real bh: Math.max(1, Math.max(...rects.map(r => r.y + r.h), 1) - by)
            readonly property real k: Math.min(width / bw, height / bh) * 0.86
            readonly property real ox: (width - bw * k) / 2
            readonly property real oy: (height - bh * k) / 2

            Repeater {
                model: Displays.monitors
                Rectangle {
                    id: mon
                    required property var modelData
                    required property int index
                    readonly property var r: area.rects[index] ?? { x: 0, y: 0, w: 0, h: 0 }
                    readonly property bool picked: root.sel?.name === modelData.name
                    x: area.ox + (r.x - area.bx) * area.k
                    y: area.oy + (r.y - area.by) * area.k
                    width: r.w * area.k
                    height: r.h * area.k
                    radius: 10
                    color: Qt.alpha(picked ? Theme.tone("action") : Theme.text, drag.pressed ? 0.22 : picked ? 0.14 : 0.06)
                    border.width: picked ? 2 : 1
                    border.color: picked ? Theme.tone("action") : Qt.alpha(Theme.text, 0.15)
                    z: drag.pressed ? 2 : 1
                    Behavior on x { enabled: !drag.pressed; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                    Behavior on y { enabled: !drag.pressed; NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.DemiBold
                            color: Theme.text
                            text: mon.modelData.name
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            font.family: Theme.font; font.pixelSize: 10
                            color: Theme.subtext
                            text: mon.modelData.width + "×" + mon.modelData.height + " · " + Math.round(mon.modelData.refreshRate) + " Hz"
                        }
                    }
                    MouseArea {
                        id: drag
                        anchors.fill: parent
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        drag.target: Displays.monitors.length > 1 ? mon : null
                        drag.threshold: 6
                        onPressed: root.chosen = mon.modelData.name
                        onReleased: {
                            const moved = drag.active || Math.abs(mon.x - (area.ox + (mon.r.x - area.bx) * area.k)) > 2;
                            const lx = (mon.x - area.ox) / area.k + area.bx, ly = (mon.y - area.oy) / area.k + area.by;
                            // back onto its binding; the new place comes from Hyprland
                            mon.x = Qt.binding(() => area.ox + (mon.r.x - area.bx) * area.k);
                            mon.y = Qt.binding(() => area.oy + (mon.r.y - area.by) * area.k);
                            if (!moved) return;
                            const p = D.snap({ x: lx, y: ly, w: mon.r.w, h: mon.r.h }, area.rects.filter((_, i) => i !== mon.index), 120);
                            if (Math.round(p.x) !== mon.r.x || Math.round(p.y) !== mon.r.y) Displays.apply(mon.modelData.name, { x: p.x, y: p.y });
                        }
                    }
                }
            }
        }
    }

    // ── the chosen one ──
    Card {
        id: side
        anchors.right: parent.right
        width: 380
        height: parent.height

        Column {
            x: 18; y: 16
            width: parent.width - 36
            spacing: 8
            visible: !!root.sel

            Column {
                spacing: 2
                Label { text: root.sel?.name ?? ""; font.pixelSize: 14; color: Theme.text }
                Text {
                    width: side.width - 36
                    elide: Text.ElideRight
                    font.family: Theme.font; font.pixelSize: 11
                    color: Theme.subtext
                    text: Demo.on ? DemoData.monitor : [root.sel?.make, root.sel?.model].filter(Boolean).join(" ")
                }
            }

            Setting {
                text: "Refresh"
                Choice {
                    readonly property var list: root.sel ? D.rates(root.sel).slice(0, 4) : []
                    options: list.map(r => ({ v: String(r), t: Math.round(r) + " Hz" }))
                    // the live rate (119.88) matches its whole-number entry (120)
                    value: String(list.find(r => Math.round(r) === Math.round(root.sel?.refreshRate ?? 0)) ?? "")
                    onChose: v => Displays.apply(root.sel.name, { rate: Number(v) })
                }
            }
            Setting {
                text: "Scale"
                Choice {
                    options: [{ v: "1", t: "100%" }, { v: "1.25", t: "125%" }, { v: "1.5", t: "150%" }, { v: "2", t: "200%" }]
                    value: root.sel ? String(Number(root.sel.scale.toFixed(2))) : ""
                    onChose: v => Displays.apply(root.sel.name, { scale: Number(v) })
                }
            }
            Setting {
                text: "Rotation"
                Choice {
                    options: [{ v: "0", t: "None" }, { v: "1", t: "90°" }, { v: "2", t: "180°" }, { v: "3", t: "270°" }]
                    value: root.sel ? String(root.sel.transform % 4) : ""
                    onChose: v => Displays.apply(root.sel.name, { transform: Number(v) })
                }
            }

            Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.text, 0.07) }

            // the trial: keep it, or it goes back by itself
            Column {
                visible: Displays.trying
                width: parent.width
                spacing: 8
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    font.family: Theme.font; font.pixelSize: 12
                    color: Theme.tone("warning")
                    text: "Keep these settings? Going back in " + Displays.left + " s."
                }
                Row {
                    spacing: 8
                    Action { text: "Keep"; glyph: "check"; accent: true; onHit: Displays.keep() }
                    Action { text: "Go back"; glyph: "undo"; onHit: Displays.revert() }
                }
            }
            Text {
                visible: !!Displays.error
                width: parent.width
                wrapMode: Text.Wrap
                font.family: Theme.font; font.pixelSize: 11
                color: Theme.tone("error")
                text: "Hyprland said: " + Displays.error
            }
            // where kept settings go, and how Hyprland finds them
            Text {
                visible: !Displays.trying
                width: parent.width
                wrapMode: Text.Wrap
                font.family: Theme.font; font.pixelSize: 11
                color: Theme.subtext
                text: Displays.hooked ? "Kept changes are saved in ~/.config/hypr/bead-monitors.lua and load with Hyprland."
                    : "Kept changes go in ~/.config/hypr/bead-monitors.lua. To load them at start, add one line at the end of your Hyprland config:"
            }
            Action {
                visible: !Displays.trying && !Displays.hooked
                text: "Copy the line"
                glyph: "content_copy"
                onHit: Quickshell.execDetached(["wl-copy", Displays.hookLine])
            }
        }
    }
}
