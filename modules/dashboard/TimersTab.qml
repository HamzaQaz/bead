pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.components
import qs.config
import qs.services

// Timers and the stopwatch: everything running, each with pause / resume,
// +1 min or lap, and stop; laps under the stopwatch. On the left, quick starts.
Row {
    id: root
    spacing: 16

    // ── quick start ──
    Card {
        id: quick
        width: 236
        height: parent.height
        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10
            Text {
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Medium
                color: Theme.text
                text: "Start"
            }
            Grid {
                columns: 4
                spacing: 6
                Repeater {
                    model: [1, 3, 5, 10, 15, 25, 45, 60]
                    Rectangle {
                        id: chip
                        required property int modelData
                        width: 47; height: 34; radius: 17
                        color: Qt.alpha(Theme.text, chipMa.pressed ? 0.16 : chipMa.containsMouse ? 0.11 : 0.06)
                        scale: chipMa.pressed ? 0.94 : 1
                        Behavior on scale { SpringAnimation { spring: 6; damping: 0.3 } }
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text {
                            anchors.centerIn: parent
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: Theme.text
                            text: chip.modelData === 60 ? "1h" : chip.modelData + "m"
                        }
                        MouseArea {
                            id: chipMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Countdown.startTimer(chip.modelData * 60000, chip.modelData === 25 ? "Focus" : chip.modelData === 3 ? "Tea" : "")
                        }
                    }
                }
            }
            Rectangle {
                width: parent.width
                height: 38
                radius: 19
                color: swMa.containsMouse ? Qt.alpha(Theme.tone("action"), 0.9) : Theme.tone("action")
                scale: swMa.pressed ? 0.96 : 1
                Behavior on scale { SpringAnimation { spring: 6; damping: 0.3 } }
                Row {
                    anchors.centerIn: parent
                    spacing: 7
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "avg_pace"; size: 18; fill: 1; color: Theme.frame }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        color: Theme.frame
                        text: Countdown.stopwatch ? "Restart stopwatch" : "Stopwatch"
                    }
                }
                MouseArea { id: swMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Countdown.startStopwatch() }
            }
            Label {
                width: parent.width
                wrapMode: Text.WordWrap
                font.pixelSize: 11
                text: "Or from the launcher: > timer 7m30s"
            }
        }
    }

    // cards are kept per timer id (a ListModel synced from Countdown.items),
    // so pausing or stopping one doesn't rebuild the others
    ListModel { id: ids }
    function sync(): void {
        const want = Countdown.items.map(i => i.id);
        for (let k = ids.count - 1; k >= 0; k--)
            if (!want.includes(ids.get(k).tid)) ids.remove(k);
        for (const id of want) {
            let found = false;
            for (let k = 0; k < ids.count; k++) if (ids.get(k).tid === id) { found = true; break; }
            if (!found) ids.append({ tid: id });
        }
    }
    Component.onCompleted: sync()
    Connections { target: Countdown; function onItemsChanged() { root.sync(); } }

    // ── what's running ──
    Item {
        width: parent.width - quick.width - root.spacing
        height: parent.height

        Column {
            anchors.centerIn: parent
            visible: Countdown.items.length === 0
            spacing: 6
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "timer"; size: 34; color: Theme.subtext }
            Label { anchors.horizontalCenter: parent.horizontalCenter; text: "No timers running" }
        }

        Flickable {
            anchors.fill: parent
            contentHeight: list.height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: list
                width: parent.width
                spacing: 10
                Repeater {
                    model: ids
                    Card {
                        id: card
                        required property int tid
                        readonly property var it: Countdown.items.find(i => i.id === tid) ?? ({ id: tid, kind: "timer", name: "", total: 0, accumulated: 0, startedAt: 0, running: false, laps: [] })
                        readonly property bool sw: it.kind === "stopwatch"
                        width: list.width
                        height: 76 + (sw && it.laps.length ? lapsCol.height + 8 : 0)
                        opacity: 0
                        Component.onCompleted: opacity = 1
                        Behavior on opacity { NumberAnimation { duration: 220 } }
                        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                        // ring (timer) or glyph (stopwatch)
                        Item {
                            id: dial
                            x: 16; y: 14
                            width: 48; height: 48
                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    fillColor: "transparent"
                                    strokeColor: Qt.alpha(Theme.text, 0.1)
                                    strokeWidth: 4
                                    PathAngleArc { centerX: 24; centerY: 24; radiusX: 21; radiusY: 21; startAngle: 0; sweepAngle: 360 }
                                }
                                ShapePath {
                                    fillColor: "transparent"
                                    strokeColor: card.it.running ? Theme.tone("action") : Theme.subtext
                                    strokeWidth: 4
                                    capStyle: ShapePath.RoundCap
                                    PathAngleArc {
                                        centerX: 24; centerY: 24; radiusX: 21; radiusY: 21; startAngle: -90
                                        sweepAngle: card.sw ? 360 * ((Countdown.elapsedOf(card.it) % 60000) / 60000)
                                            : 360 * (1 - Countdown.progressOf(card.it))
                                    }
                                }
                            }
                            Icon {
                                anchors.fill: parent
                                name: card.sw ? "avg_pace" : "timer"
                                size: 18
                                fill: card.it.running ? 1 : 0
                                color: card.it.running ? Theme.tone("action") : Theme.subtext
                            }
                        }

                        Column {
                            x: 78
                            y: 14
                            Text {
                                font.family: Theme.font
                                font.pixelSize: 28
                                font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                                color: card.it.running ? Theme.text : Theme.subtext
                                text: Countdown.labelOf(card.it)
                            }
                            Label {
                                font.pixelSize: 11
                                text: (card.sw ? "Stopwatch" : card.it.name + (card.it.name !== Countdown.fmtTotal(card.it.total) ? " · " + Countdown.fmtTotal(card.it.total) : ""))
                                    + (card.it.running ? "" : " · paused")
                            }
                        }

                        // controls
                        component Ctl: Rectangle {
                            id: ctl
                            property string glyph: ""
                            property bool main: false
                            property string tip: ""
                            signal hit()
                            width: 38; height: 38; radius: 19
                            color: main ? Theme.tone("action") : Qt.alpha(Theme.text, cma.pressed ? 0.16 : cma.containsMouse ? 0.11 : 0.06)
                            scale: cma.pressed ? 0.92 : 1
                            Behavior on scale { SpringAnimation { spring: 6; damping: 0.3 } }
                            Behavior on color { ColorAnimation { duration: 140 } }
                            Icon { anchors.fill: parent; name: ctl.glyph; size: 19; fill: 1; color: ctl.main ? Theme.frame : Theme.text }
                            MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ctl.hit() }
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            y: 19
                            spacing: 8
                            Ctl {
                                glyph: card.sw ? "flag" : "more_time"
                                visible: !card.sw || card.it.running
                                onHit: card.sw ? Countdown.lap(card.it.id) : Countdown.addTime(card.it.id, 60000)
                            }
                            Ctl { glyph: card.it.running ? "pause" : "play_arrow"; main: true; onHit: Countdown.toggle(card.it.id) }
                            Ctl { glyph: "stop"; onHit: Countdown.stop(card.it.id) }
                        }

                        // laps, newest first
                        Column {
                            id: lapsCol
                            x: 78
                            y: 72
                            width: parent.width - 78 - 16
                            visible: card.sw && card.it.laps.length > 0
                            Repeater {
                                model: card.sw ? card.it.laps.map((t, i, a) => ({ n: i + 1, t: t, d: t - (a[i - 1] ?? 0) })).reverse().slice(0, 4) : []
                                Row {
                                    required property var modelData
                                    spacing: 14
                                    Label { width: 46; font.pixelSize: 11; text: "Lap " + modelData.n }
                                    Label { width: 64; font.pixelSize: 11; font.features: { "tnum": 1 }; color: Theme.text; text: "+" + Countdown.clock(modelData.d, false) }
                                    Label { font.pixelSize: 11; font.features: { "tnum": 1 }; text: Countdown.clock(modelData.t, false) }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
