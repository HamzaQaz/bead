pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.components
import qs.config
import qs.services

// Timers and the stopwatch. On the left a dial to set one (drag round it or
// scroll; past an hour in 5-minute steps), an optional name, presets and the
// stopwatch. On the right everything running, each with pause / resume (a
// morphing play/pause), +1 min or lap, and stop; laps under the stopwatch.
Row {
    id: root
    spacing: 16

    // ── quick start: a dial you turn (drag round it, or scroll), presets ──
    Card {
        id: quick
        width: 420
        height: parent.height

        // minutes on the dial: 1–60 in single minutes, then 5-minute steps to 2 h
        property int mins: 5
        function nudge(d: int): void {
            const step = mins >= 60 && d > 0 || mins > 60 ? 5 : 1;
            mins = Math.max(1, Math.min(120, mins + d * step));
        }
        function start(): void { Countdown.startTimer(mins * 60000, nameField.text.trim()); nameField.text = ""; startPop.restart(); }

        Item {
            id: dial
            x: 18
            anchors.verticalCenter: parent.verticalCenter
            width: 172; height: 172
            // what the ring shows: the minutes within the hour, eased
            property real shown: quick.mins > 60 ? 1 : quick.mins / 60
            Behavior on shown { SpringAnimation { spring: 4; damping: 0.4; epsilon: 0.001 } }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Qt.alpha(Theme.text, 0.08)
                    strokeWidth: 12
                    fillColor: "transparent"
                    PathAngleArc { centerX: 86; centerY: 86; radiusX: 74; radiusY: 74; startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    strokeColor: Theme.tone("action")
                    strokeWidth: 12
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 86; centerY: 86; radiusX: 74; radiusY: 74; startAngle: -90; sweepAngle: Math.max(0.5, 360 * dial.shown) }
                }
                // past an hour: a second, inner lap
                ShapePath {
                    strokeColor: Qt.alpha(Theme.tone("action"), 0.55)
                    strokeWidth: 5
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 86; centerY: 86; radiusX: 60; radiusY: 60; startAngle: -90; sweepAngle: quick.mins > 60 ? 360 * (quick.mins - 60) / 60 : 0 }
                }
            }
            // twelve ticks inside the ring, like a clock
            Repeater {
                model: 12
                Item {
                    required property int index
                    x: 86; y: 86
                    rotation: index * 30
                    Rectangle {
                        x: -1
                        y: -50
                        width: 2; height: parent.index % 3 === 0 ? 7 : 4; radius: 1
                        color: Qt.alpha(Theme.text, parent.index % 3 === 0 ? 0.35 : 0.16)
                    }
                }
            }
            // the knob at the end of the arc
            Rectangle {
                readonly property real a: (dial.shown * 360 - 90) * Math.PI / 180
                x: 86 + Math.cos(a) * 74 - width / 2
                y: 86 + Math.sin(a) * 74 - height / 2
                width: turn.pressed ? 24 : 20; height: width; radius: width / 2
                color: Theme.text
                border.width: 4
                border.color: Theme.tone("action")
                Behavior on width { SpringAnimation { spring: 6; damping: 0.3 } }
            }
            Column {
                anchors.centerIn: parent
                Text {
                    id: minsText
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.family: Theme.font
                    font.pixelSize: 34
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    color: Theme.text
                    text: quick.mins >= 60 ? Math.floor(quick.mins / 60) + ":" + String(quick.mins % 60).padStart(2, "0") : quick.mins
                }
                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    font.pixelSize: 11
                    text: quick.mins >= 60 ? "hours" : quick.mins === 1 ? "minute" : "minutes"
                }
            }
            MouseArea {
                id: turn
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                property real last: -1
                // angle from 12 o'clock, 0–60 "minutes"; past the top keeps going
                function at(x: real, y: real): real {
                    let a = Math.atan2(x - 86, -(y - 86)) * 180 / Math.PI;
                    if (a < 0) a += 360;
                    return a / 6;
                }
                onPressed: e => last = at(e.x, e.y)
                // one turn is 60 minutes; whole minutes apply as you go
                onPositionChanged: e => {
                    if (!pressed) return;
                    const now = at(e.x, e.y);
                    let d = now - last;
                    if (d > 30) d -= 60; else if (d < -30) d += 60; // across 12 o'clock
                    last = now;
                    acc += d;
                    const whole = acc > 0 ? Math.floor(acc) : Math.ceil(acc);
                    if (whole !== 0) {
                        acc -= whole;
                        quick.mins = Math.max(1, Math.min(120, quick.mins + whole));
                    }
                }
                property real acc: 0
                onReleased: { acc = 0; if (quick.mins > 60) quick.mins = Math.round(quick.mins / 5) * 5; }
                onDoubleClicked: quick.start()
            }
            WheelHandler { onWheel: e => quick.nudge(e.angleDelta.y > 0 ? 1 : -1) }
        }

        // the right side: name, presets, go
        Column {
            x: dial.x + dial.width + 20
            width: parent.width - x - 18
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Rectangle { // an optional name
                width: parent.width
                height: 32
                radius: 10
                color: Qt.alpha(Theme.text, 0.06)
                border.width: nameField.activeFocus ? 1.5 : 0
                border.color: Theme.tone("action")
                TextInput {
                    id: nameField
                    anchors.fill: parent
                    anchors.leftMargin: 12; anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: Theme.font
                    font.pixelSize: 12
                    color: Theme.text
                    clip: true
                    maximumLength: 40
                    onAccepted: quick.start()
                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !nameField.text && !nameField.activeFocus
                        font.pixelSize: 12
                        text: "Name (optional)"
                    }
                }
            }
            Grid {
                columns: 4
                spacing: 6
                Repeater {
                    model: [1, 3, 5, 10, 15, 25, 45, 60]
                    Rectangle {
                        id: chip
                        required property int modelData
                        readonly property bool on: quick.mins === modelData
                        width: (190 - 18) / 4; height: 28; radius: 14
                        color: on ? Theme.tone("action") : Qt.alpha(Theme.text, chipMa.pressed ? 0.16 : chipMa.containsMouse ? 0.11 : 0.06)
                        scale: chipMa.pressed ? 0.92 : 1
                        Behavior on scale { SpringAnimation { spring: 6; damping: 0.3 } }
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text {
                            anchors.centerIn: parent
                            font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                            color: chip.on ? Theme.frame : Theme.text
                            text: chip.modelData === 60 ? "1h" : chip.modelData + "m"
                        }
                        MouseArea { id: chipMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: quick.mins = chip.modelData }
                    }
                }
            }
            Row {
                spacing: 8
                Rectangle { // start
                    id: go
                    width: 118; height: 36; radius: 18
                    color: Theme.tone("action")
                    scale: goMa.pressed ? 0.94 : 1
                    Behavior on scale { SpringAnimation { spring: 6; damping: 0.3 } }
                    SequentialAnimation {
                        id: startPop
                        NumberAnimation { target: go; property: "scale"; to: 1.08; duration: 110; easing.type: Easing.OutQuad }
                        NumberAnimation { target: go; property: "scale"; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2 }
                    }
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: "play_arrow"; size: 18; fill: 1; color: Theme.frame }
                        Text { anchors.verticalCenter: parent.verticalCenter; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold; color: Theme.frame; text: "Start" }
                    }
                    MouseArea { id: goMa; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: quick.start() }
                }
                Rectangle { // stopwatch
                    width: 64; height: 36; radius: 18
                    color: Qt.alpha(Theme.text, swMa.pressed ? 0.16 : swMa.containsMouse ? 0.11 : 0.06)
                    scale: swMa.pressed ? 0.94 : 1
                    Behavior on scale { SpringAnimation { spring: 6; damping: 0.3 } }
                    Icon { anchors.centerIn: parent; name: "avg_pace"; size: 18; fill: 1; color: Theme.text }
                    MouseArea { id: swMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Countdown.startStopwatch() }
                }
            }
            Label { font.pixelSize: 10; text: "Turn the dial or scroll · double-click starts" }
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
                            property bool morph: false   // play/pause as a morphing shape
                            property bool playing: false
                            Icon { visible: !ctl.morph; anchors.fill: parent; name: ctl.glyph; size: 19; fill: 1; color: ctl.main ? Theme.frame : Theme.text }
                            PlayPause { visible: ctl.morph; anchors.centerIn: parent; size: 18; playing: ctl.playing; color: ctl.main ? Theme.frame : Theme.text }
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
                            Ctl { morph: true; playing: card.it.running; main: true; onHit: Countdown.toggle(card.it.id) }
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
