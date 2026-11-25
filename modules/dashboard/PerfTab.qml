pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.components
import qs.config
import qs.services
import "../../services/demo.js" as DemoData

// Performance.
//  left:   four dials (CPU, GPU, memory, VRAM) with temperatures / amounts
//  middle: CPU and GPU over the last 40 s, gliding (not stepping) as new
//          samples come in, and every core's load underneath
//  right:  the busiest processes right now, and network up / down
Row {
    id: root
    spacing: 16

    // the process list only runs while this tab shows
    Binding { target: SysStats; property: "procsWanted"; value: root.visible }

    // ── dials ──
    component Dial: Item {
        id: dial
        property string label: ""
        property string sub: ""
        property real level: 0
        width: 124
        height: 118
        readonly property real v: Math.max(0, Math.min(1, level))
        property real shown: v
        Behavior on shown { SpringAnimation { spring: 3; damping: 0.32; epsilon: 0.001 } }
        readonly property color tone: v > 0.85 ? Theme.tone("error") : Theme.tone("action")
        Item {
            id: arc
            anchors.horizontalCenter: parent.horizontalCenter
            width: 78; height: 78
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Qt.alpha(Theme.text, 0.08)
                    strokeWidth: 7
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 39; centerY: 39; radiusX: 34; radiusY: 34; startAngle: 135; sweepAngle: 270 }
                }
                ShapePath {
                    strokeColor: dial.tone
                    strokeWidth: 7
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 39; centerY: 39; radiusX: 34; radiusY: 34; startAngle: 135; sweepAngle: Math.max(0.5, 270 * dial.shown) }
                }
            }
            Text {
                anchors.centerIn: parent
                font.family: Theme.font
                font.pixelSize: 17
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
                color: Theme.text
                text: Math.round(dial.shown * 100) + "%"
            }
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: arc.height - 4
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                color: Theme.text
                text: dial.label
            }
            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                font.pixelSize: 10
                font.features: { "tnum": 1 }
                text: dial.sub
            }
        }
    }
    Card {
        id: dials
        width: 272
        height: parent.height
        Grid {
            anchors.centerIn: parent
            columns: 2
            rowSpacing: 4
            Dial { label: "CPU"; level: SysStats.cpu; sub: Math.round(SysStats.cpuTemp) + "°C" }
            Dial { label: "GPU"; level: SysStats.gpu; sub: Math.round(SysStats.gpuTemp) + "°C" }
            Dial { label: "Memory"; level: SysStats.mem; sub: SysStats.memUsedGb.toFixed(1) + " / " + Math.round(SysStats.memTotalGb) + " GB" }
            Dial { label: "VRAM"; level: SysStats.vram; sub: SysStats.vramUsedGb.toFixed(1) + " / " + Math.round(SysStats.vramTotalGb) + " GB" }
        }
    }

    // ── the graph and the cores ──
    Card {
        id: graph
        width: parent.width - dials.width - side.width - 16 * 2
        height: parent.height

        Row {
            x: 16; y: 14
            spacing: 14
            Repeater {
                model: [{ name: "CPU", v: SysStats.cpu, hollow: false }, { name: "GPU", v: SysStats.gpu, hollow: true }]
                Row {
                    id: key
                    required property var modelData
                    spacing: 6
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: key.modelData.hollow ? "transparent" : Theme.tone("action")
                        border.width: key.modelData.hollow ? 1.5 : 0
                        border.color: Qt.alpha(Theme.tone("info"), 0.8)
                    }
                    Label { text: key.modelData.name; font.pixelSize: 11 }
                    Text {
                        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        color: Theme.text
                        text: Math.round(key.modelData.v * 100) + "%"
                    }
                }
            }
        }
        Label {
            anchors.right: parent.right; anchors.rightMargin: 16
            y: 14
            font.pixelSize: 10
            text: "last 40 s"
        }

        Item {
            id: plot
            x: 14; y: 38
            width: parent.width - 28
            height: parent.height - y - cores.height - 22
            clip: true
            readonly property int n: SysStats.historyLength
            readonly property real step: width / (n - 2)
            // glide: each new sample shifts everything one step left, smoothly
            property real slide: 0
            Connections {
                target: SysStats
                function onCpuHistoryChanged(): void { plot.slide = 1; glide.restart(); }
            }
            NumberAnimation { id: glide; target: plot; property: "slide"; to: 0; duration: 1000; easing.type: Easing.Linear }

            function xAt(i: int, len: int): real { return width - (len - 1 - i - slide) * step; }
            function points(h: list<real>): string {
                let d = "";
                for (let i = 0; i < h.length; i++) {
                    const x = xAt(i, h.length);
                    const y = 3 + (height - 6) * (1 - Math.max(0, Math.min(1, h[i])));
                    d += (i ? " L " : "M ") + x.toFixed(1) + " " + y.toFixed(1);
                }
                return d;
            }
            function area(h: list<real>): string {
                if (h.length < 2) return "";
                return points(h) + ` L ${xAt(h.length - 1, h.length).toFixed(1)} ${height} L ${xAt(0, h.length).toFixed(1)} ${height} Z`;
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
            Label {
                anchors.centerIn: parent
                visible: SysStats.cpuHistory.length < 3
                font.pixelSize: 11
                text: "Collecting…"
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillGradient: LinearGradient {
                        y1: 0; y2: plot.height
                        GradientStop { position: 0; color: Qt.alpha(Theme.tone("action"), 0.24) }
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

        // every core: a little bar each, filling from the bottom
        Row {
            id: cores
            x: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            width: parent.width - 32
            height: 30
            spacing: 4
            readonly property int n: Math.max(1, SysStats.cores.length)
            Repeater {
                model: SysStats.cores.length
                Item {
                    id: core
                    required property int index
                    readonly property real v: SysStats.cores[index] ?? 0
                    width: (cores.width - (cores.n - 1) * cores.spacing) / cores.n
                    height: cores.height
                    Rectangle { anchors.fill: parent; radius: 4; color: Qt.alpha(Theme.text, 0.06) }
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        // square root: light loads still show (the % is in the graph above)
                        height: Math.max(3, parent.height * Math.sqrt(core.v))
                        radius: 4
                        color: core.v > 0.85 ? Theme.tone("error") : Theme.tone("action")
                        opacity: 0.45 + 0.55 * core.v
                        Behavior on height { SpringAnimation { spring: 3; damping: 0.4; epsilon: 0.3 } }
                    }
                }
            }
        }
    }

    // ── processes and network ──
    Card {
        id: side
        width: 286
        height: parent.height

        Text {
            x: 16; y: 14
            font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium
            color: Theme.text
            text: "Busiest now"
        }
        Column {
            x: 16; y: 40
            width: parent.width - 32
            spacing: 6
            Label {
                visible: !Demo.on && SysStats.procs.length === 0
                font.pixelSize: 11
                text: "Looking…"
            }
            Repeater {
                model: Demo.on ? DemoData.procs : SysStats.procs
                Item {
                    id: pr
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: 22
                    // share of the whole machine (top reports per core)
                    readonly property real share: Math.min(1, modelData.cpu / 100 / Math.max(1, SysStats.cores.length))
                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: Qt.alpha(Theme.text, 0.04)
                        Rectangle {
                            height: parent.height
                            radius: 6
                            width: Math.max(0, parent.width * Math.min(1, pr.modelData.cpu / 100))
                            color: Qt.alpha(Theme.tone("action"), 0.18)
                            Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                        }
                    }
                    Text {
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 120
                        elide: Text.ElideRight
                        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Medium
                        color: Theme.text
                        text: pr.modelData.name
                    }
                    Label {
                        anchors.right: cpuT.left; anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: 10
                        font.features: { "tnum": 1 }
                        text: pr.modelData.memMb >= 1024 ? (pr.modelData.memMb / 1024).toFixed(1) + " GB" : Math.round(pr.modelData.memMb) + " MB"
                    }
                    Text {
                        id: cpuT
                        anchors.right: parent.right; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 36
                        horizontalAlignment: Text.AlignRight
                        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                        font.features: { "tnum": 1 }
                        color: Theme.text
                        text: Math.round(pr.modelData.cpu) + "%"
                    }
                }
            }
        }

        // network: speeds and a small history each
        Row {
            x: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            width: parent.width - 32
            spacing: 12
            Repeater {
                model: [
                    { icon: "arrow_downward", v: SysStats.rxRate, h: SysStats.rxHistory },
                    { icon: "arrow_upward", v: SysStats.txRate, h: SysStats.txHistory }
                ]
                Item {
                    id: net
                    required property var modelData
                    width: (parent.width - 12) / 2
                    height: 40
                    Row {
                        spacing: 4
                        Icon { name: net.modelData.icon; size: 14; color: Theme.tone("action"); anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                            color: Theme.text
                            text: SysStats.fmtRate(net.modelData.v)
                        }
                    }
                    Shape {
                        id: spark
                        y: 20
                        width: parent.width
                        height: 20
                        preferredRendererType: Shape.CurveRenderer
                        readonly property real peak: Math.max(1024, ...net.modelData.h)
                        ShapePath {
                            strokeColor: Qt.alpha(Theme.tone("action"), 0.7)
                            strokeWidth: 1.5
                            fillColor: Qt.alpha(Theme.tone("action"), 0.12)
                            joinStyle: ShapePath.RoundJoin
                            PathSvg {
                                path: {
                                    const h = net.modelData.h, w = net.width, H = 20, t = spark.peak;
                                    if (h.length < 2) return "";
                                    let d = "";
                                    for (let i = 0; i < h.length; i++)
                                        d += (i ? " L " : "M ") + (w * i / (h.length - 1)).toFixed(1) + " " + (H - 1 - (H - 2) * Math.min(1, h[i] / t)).toFixed(1);
                                    return d + ` L ${w} ${H} L 0 ${H} Z`;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
