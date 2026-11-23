pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.components
import qs.config
import qs.services

// Performance: ring gauges (CPU, GPU, memory, disk) with temperatures, a live
// CPU/GPU graph and network speeds.
Row {
    id: root
    spacing: 16

    component Ring: Card {
        id: ring
        property string label: ""
        property string sub: ""
        property real level: 0
        property string icon: ""
        width: 124
        height: parent.height

        readonly property real v: Math.max(0, Math.min(1, level))
        property real shown: v
        Behavior on shown { SpringAnimation { spring: 3; damping: 0.32; epsilon: 0.001 } }
        readonly property color tone: v > 0.85 ? Theme.tone("error") : Theme.tone("action")

        // dial and labels as one group, centred in the card
        Column {
            anchors.centerIn: parent
            spacing: 14
        Item {
            id: dial
            width: 112; height: 112
            anchors.horizontalCenter: parent.horizontalCenter
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath { // track: a 270° arc open at the bottom
                    strokeColor: Qt.alpha(Theme.text, 0.08)
                    strokeWidth: 9
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 56; centerY: 56; radiusX: 50; radiusY: 50; startAngle: 135; sweepAngle: 270 }
                }
                ShapePath {
                    strokeColor: ring.tone
                    strokeWidth: 9
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 56; centerY: 56; radiusX: 50; radiusY: 50; startAngle: 135; sweepAngle: Math.max(0.5, 270 * ring.shown) }
                }
            }
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -2
                font.family: Theme.font
                font.pixelSize: 22
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                color: Theme.text
                text: Math.round(ring.v * 100) + "%"
            }
            Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                name: ring.icon
                size: 16
                fill: 1
                color: ring.tone
            }
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Medium
                color: Theme.text
                text: ring.label
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: 11
                font.features: { "tnum": 1 }
                text: ring.sub
            }
        }
        }
    }

    Ring { label: "CPU"; icon: "memory"; level: SysStats.cpu; sub: Math.round(SysStats.cpuTemp) + "°C" }
    Ring { label: "GPU"; icon: "developer_board"; level: SysStats.gpu; sub: Math.round(SysStats.gpuTemp) + "°C" }
    Ring { label: "Memory"; icon: "memory_alt"; level: SysStats.mem; sub: SysStats.memUsedGb.toFixed(1) + " / " + Math.round(SysStats.memTotalGb) + " GB" }
    Ring { label: "Disk"; icon: "hard_drive"; level: SysStats.disk; sub: Math.round(SysStats.diskUsedGb) + " / " + Math.round(SysStats.diskTotalGb) + " GB" }

    Card {
        id: graph
        width: parent.width - 124 * 4 - 16 * 4
        height: parent.height

        Row {
            x: 16; y: 14
            spacing: 14
            Repeater {
                // CPU solid, GPU dashed and dimmer: tellable apart even when the
                // scheme's tones are all one grey
                model: [{ name: "CPU", hollow: false }, { name: "GPU", hollow: true }]
                Row {
                    required property var modelData
                    spacing: 6
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: parent.modelData.hollow ? "transparent" : Theme.tone("action")
                        border.width: parent.modelData.hollow ? 1.5 : 0
                        border.color: Qt.alpha(Theme.tone("info"), 0.8)
                    }
                    Label { text: parent.modelData.name; font.pixelSize: 11 }
                }
            }
        }

        // live graph of the last 40 seconds
        Item {
            id: plot
            x: 14; y: 38
            width: parent.width - 28
            height: parent.height - 38 - 62
            function points(h: list<real>): string {
                let d = "";
                for (let i = 0; i < h.length; i++) {
                    // spread across the width until the history fills, then scroll
                    const x = plot.width * i / Math.max(1, h.length - 1);
                    const y = plot.height * (1 - Math.max(0, Math.min(1, h[i])));
                    d += (i ? " L " : "M ") + x.toFixed(1) + " " + y.toFixed(1);
                }
                return d;
            }
            // the line closed down to the bottom, for the fill
            function area(h: list<real>): string {
                if (h.length < 2) return "";
                return points(h) + ` L ${plot.width.toFixed(1)} ${plot.height} L 0 ${plot.height} Z`;
            }
            Label {
                anchors.centerIn: parent
                visible: SysStats.cpuHistory.length < 3
                font.pixelSize: 11
                text: "Collecting…"
            }
            Repeater {
                model: [0.25, 0.5, 0.75]
                Rectangle {
                    required property real modelData
                    y: plot.height * modelData
                    width: plot.width
                    height: 1
                    color: Qt.alpha(Theme.text, 0.05)
                }
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath { // CPU's soft fill
                    strokeColor: "transparent"
                    fillGradient: LinearGradient {
                        y1: 0; y2: plot.height
                        GradientStop { position: 0; color: Qt.alpha(Theme.tone("action"), 0.22) }
                        GradientStop { position: 1; color: Qt.alpha(Theme.tone("action"), 0) }
                    }
                    PathSvg { path: plot.area(SysStats.cpuHistory) }
                }
                ShapePath {
                    strokeColor: Qt.alpha(Theme.tone("info"), 0.8)
                    strokeWidth: 1.6
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [2.5, 2]
                    fillColor: "transparent"
                    joinStyle: ShapePath.RoundJoin
                    capStyle: ShapePath.FlatCap
                    PathSvg { path: plot.points(SysStats.gpuHistory) }
                }
                ShapePath {
                    strokeColor: Theme.tone("action")
                    strokeWidth: 2
                    fillColor: "transparent"
                    joinStyle: ShapePath.RoundJoin
                    capStyle: ShapePath.RoundCap
                    PathSvg { path: plot.points(SysStats.cpuHistory) }
                }
            }
        }

        // network
        Row {
            x: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            spacing: 22
            Repeater {
                model: [{ icon: "arrow_downward", v: SysStats.rxRate, l: "Down" }, { icon: "arrow_upward", v: SysStats.txRate, l: "Up" }]
                Row {
                    id: net
                    required property var modelData
                    spacing: 6
                    Icon { name: net.modelData.icon; size: 16; color: Theme.tone("action"); anchors.verticalCenter: parent.verticalCenter }
                    Column {
                        Label { text: net.modelData.l; font.pixelSize: 10 }
                        Text {
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                            color: Theme.text
                            text: SysStats.fmtRate(net.modelData.v)
                        }
                    }
                }
            }
        }
    }
}
