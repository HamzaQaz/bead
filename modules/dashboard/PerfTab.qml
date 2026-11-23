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

        Item {
            id: dial
            width: 96; height: 96
            anchors.horizontalCenter: parent.horizontalCenter
            y: 20
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath { // track: a 270° arc open at the bottom
                    strokeColor: Qt.alpha(Theme.text, 0.08)
                    strokeWidth: 9
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 48; centerY: 48; radiusX: 42; radiusY: 42; startAngle: 135; sweepAngle: 270 }
                }
                ShapePath {
                    strokeColor: ring.tone
                    strokeWidth: 9
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 48; centerY: 48; radiusX: 42; radiusY: 42; startAngle: 135; sweepAngle: Math.max(0.5, 270 * ring.shown) }
                }
            }
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -2
                font.family: Theme.font
                font.pixelSize: 20
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
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
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
                model: [{ name: "CPU", c: Theme.tone("action") }, { name: "GPU", c: Theme.tone("info") }]
                Row {
                    required property var modelData
                    spacing: 6
                    Rectangle { width: 8; height: 8; radius: 4; color: parent.modelData.c; anchors.verticalCenter: parent.verticalCenter }
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
                const n = SysStats.historyLength;
                let d = "";
                for (let i = 0; i < h.length; i++) {
                    const x = plot.width * (i + n - h.length) / (n - 1);
                    const y = plot.height * (1 - Math.max(0, Math.min(1, h[i])));
                    d += (i ? " L " : "M ") + x.toFixed(1) + " " + y.toFixed(1);
                }
                return d;
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
                ShapePath {
                    strokeColor: Theme.tone("info")
                    strokeWidth: 2
                    fillColor: "transparent"
                    joinStyle: ShapePath.RoundJoin
                    capStyle: ShapePath.RoundCap
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
