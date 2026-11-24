pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import "../../components/emptystates.js" as Empty
import qs.components
import qs.config
import qs.services
import "sky.js" as Sky

// Weather.
//  left:  where, a big animated icon, the temperature and conditions, today's
//         high / low, and feels like · humidity · wind · sunrise / sunset
//  right: the next 12 hours as a temperature curve that draws itself in
//         (icons, temperatures and rain chances on it), then five days with
//         a range bar each against the week's coldest and warmest
Row {
    id: root
    spacing: 16

    // replayed every time the tab shows
    property real draw: 0
    onVisibleChanged: if (visible) { draw = 0; drawAnim.restart(); }
    Component.onCompleted: drawAnim.restart()
    NumberAnimation { id: drawAnim; target: root; property: "draw"; from: 0; to: 1; duration: 900; easing.type: Easing.OutCubic }

    function hhmm(d: var): string { return d ? Qt.formatTime(d, "hh:mm") : "–"; }
    readonly property string unit: Weather.fahrenheit ? " mph" : " km/h"

    // ── now ──
    Card {
        width: 312
        height: parent.height
        visible: Weather.ready

        // behind it all, light motion matched to the weather (sky.js, sky.frag);
        // it only runs while the tab is on screen
        ShaderEffect {
            id: sky
            anchors.fill: parent
            readonly property var what: Sky.of(Weather.code, Weather.isDay)
            fragmentShader: Qt.resolvedUrl("../../shaders/sky.frag.qsb")
            property size size: Qt.size(width, height)
            property real time: 0
            property real kind: what.kind
            property real amount: what.amount
            property real radius: parent.radius
            property color tint: Theme.tone("action")
            opacity: 0
            Component.onCompleted: opacity = 1
            Behavior on opacity { NumberAnimation { duration: 1200 } }
            FrameAnimation {
                running: sky.visible && root.visible
                onTriggered: sky.time += frameTime
            }
        }

        Row {
            x: 20; y: 16
            spacing: 6
            Icon { name: "location_on"; size: 15; fill: 1; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
            Label { text: Weather.city || "Here"; anchors.verticalCenter: parent.verticalCenter }
        }

        Row {
            x: 18; y: 38
            spacing: 12
            // the icon lives a little: a sun turns, anything else drifts
            Item {
                width: 78; height: 78
                anchors.verticalCenter: parent.verticalCenter
                Icon {
                    id: bigIcon
                    anchors.centerIn: parent
                    readonly property string n: Weather.icon(Weather.code, Weather.isDay)
                    readonly property bool sunny: n === "clear_day" || n === "sunny"
                    name: n
                    size: 72
                    fill: 0
                    color: Theme.tone("action")
                    RotationAnimation on rotation {
                        running: bigIcon.sunny && root.visible
                        from: 0; to: 360; duration: 40000; loops: Animation.Infinite
                    }
                    SequentialAnimation on anchors.horizontalCenterOffset {
                        running: !bigIcon.sunny && root.visible
                        loops: Animation.Infinite
                        NumberAnimation { to: 4; duration: 2600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: -4; duration: 2600; easing.type: Easing.InOutSine }
                    }
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    font.family: Theme.font
                    font.pixelSize: 50
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                    color: Theme.text
                    text: Math.round(Weather.temp) + "°"
                }
                Text {
                    font.family: Theme.font
                    font.pixelSize: 14
                    color: Theme.text
                    text: Weather.describe(Weather.code) + "  <font color='" + Theme.subtext + "'>H " + Math.round(Weather.high) + "° · L " + Math.round(Weather.low) + "°</font>"
                    textFormat: Text.StyledText
                }
            }
        }

        // the details, a 2×2 grid at the bottom
        Grid {
            x: 16
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 14
            columns: 2
            columnSpacing: 8
            rowSpacing: 8
            Repeater {
                model: [
                    { icon: "thermostat", l: "Feels like", v: Math.round(Weather.feels) + "°" },
                    { icon: "humidity_percentage", l: "Humidity", v: Math.round(Weather.humidity) + "%" },
                    { icon: "air", l: "Wind", v: Math.round(Weather.wind) + root.unit },
                    { icon: "wb_twilight", l: "Sun", v: root.hhmm(Weather.sunrise) + " – " + root.hhmm(Weather.sunset) }
                ]
                Rectangle {
                    id: stat
                    required property var modelData
                    required property int index
                    width: (312 - 32 - 8) / 2
                    height: 44
                    radius: 12
                    color: Qt.alpha(Theme.text, 0.05)
                    // pop in, one after another
                    opacity: Math.min(1, Math.max(0, root.draw * 4 - stat.index * 0.5))
                    scale: 0.9 + 0.1 * opacity
                    Icon { x: 10; anchors.verticalCenter: parent.verticalCenter; name: stat.modelData.icon; size: 17; color: Theme.subtext }
                    Column {
                        x: 34
                        anchors.verticalCenter: parent.verticalCenter
                        Label { font.pixelSize: 10; text: stat.modelData.l }
                        Text {
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                            color: Theme.text
                            text: stat.modelData.v
                        }
                    }
                }
            }
        }
    }

    // ── the next hours, then the days ──
    Card {
        id: ahead
        width: parent.width - 312 - 16
        height: parent.height
        visible: Weather.ready

        // the curve
        Item {
            id: chart
            x: 18
            y: 12
            width: parent.width - 36
            height: 136
            readonly property var hrs: Weather.hourly
            readonly property int n: hrs.length
            readonly property real lo: n ? Math.min(...hrs.map(h => h.temp)) : 0
            readonly property real hi: n ? Math.max(...hrs.map(h => h.temp)) : 1
            readonly property real padTop: 36   // room for icons + temps above
            readonly property real padBottom: 30 // room for times below
            function px(i: int): real { return n > 1 ? 14 + i * (width - 28) / (n - 1) : width / 2; }
            function py(t: real): real {
                const span = Math.max(1, hi - lo);
                return padTop + (1 - (t - lo) / span) * (height - padTop - padBottom);
            }
            // a smooth path through the points (Catmull-Rom as cubic Béziers)
            function path(closed: bool): string {
                if (n < 2) return "";
                const P = hrs.map((h, i) => [px(i), py(h.temp)]);
                let d = `M ${P[0][0]} ${P[0][1]}`;
                for (let i = 0; i < n - 1; i++) {
                    const p0 = P[Math.max(0, i - 1)], p1 = P[i], p2 = P[i + 1], p3 = P[Math.min(n - 1, i + 2)];
                    const c1 = [p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6];
                    const c2 = [p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6];
                    d += ` C ${c1[0]} ${c1[1]} ${c2[0]} ${c2[1]} ${p2[0]} ${p2[1]}`;
                }
                if (closed) d += ` L ${P[n - 1][0]} ${height - padBottom + 6} L ${P[0][0]} ${height - padBottom + 6} Z`;
                return d;
            }

            // drawn in from the left
            Item {
                width: chart.width * root.draw
                height: chart.height
                clip: true
                Shape {
                    width: chart.width
                    height: chart.height
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        strokeColor: "transparent"
                        fillGradient: LinearGradient {
                            x1: 0; y1: chart.padTop; x2: 0; y2: chart.height - chart.padBottom
                            GradientStop { position: 0; color: Qt.alpha(Theme.tone("action"), 0.28) }
                            GradientStop { position: 1; color: Qt.alpha(Theme.tone("action"), 0) }
                        }
                        PathSvg { path: chart.path(true) }
                    }
                    ShapePath {
                        strokeColor: Theme.tone("action")
                        strokeWidth: 2.5
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: chart.path(false) }
                    }
                }
            }
            // the hours: a dot, the temperature and icon above, time (and rain) below
            Repeater {
                model: chart.hrs
                Item {
                    id: hour
                    required property var modelData
                    required property int index
                    readonly property real cx: chart.px(index)
                    readonly property real cy: chart.py(modelData.temp)
                    // each appears as the line reaches it
                    readonly property real on: Math.min(1, Math.max(0, (root.draw * chart.width - cx + 30) / 40))
                    opacity: on
                    Rectangle {
                        x: hour.cx - width / 2; y: hour.cy - height / 2
                        width: hour.index === 0 ? 10 : 6; height: width; radius: width / 2
                        color: hour.index === 0 ? Theme.text : Theme.tone("action")
                        border.width: hour.index === 0 ? 2 : 0
                        border.color: Theme.tone("action")
                        scale: 0.4 + 0.6 * hour.on
                    }
                    // every other hour labelled, so it breathes
                    Column {
                        visible: hour.index % 2 === 0
                        x: hour.cx - width / 2
                        y: hour.cy - height - 6
                        spacing: 0
                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: Weather.icon(hour.modelData.code, hour.modelData.isDay)
                            size: 15
                            fill: 0
                            color: Theme.subtext
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            font.features: { "tnum": 1 }
                            color: Theme.text
                            text: Math.round(hour.modelData.temp) + "°"
                        }
                    }
                    Column {
                        visible: hour.index % 2 === 0
                        x: hour.cx - width / 2
                        y: chart.height - chart.padBottom + 8
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            font.pixelSize: 10
                            font.features: { "tnum": 1 }
                            text: hour.index === 0 ? "Now" : Qt.formatTime(hour.modelData.time, "HH:00")
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: hour.modelData.rain >= 20
                            font.family: Theme.font
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                            color: "#7fb4ff"
                            text: hour.modelData.rain + "%"
                        }
                    }
                }
            }
        }

        Rectangle { x: 18; y: chart.y + chart.height + 4; width: parent.width - 36; height: 1; color: Qt.alpha(Theme.text, 0.07) }

        // the days: name, icon, a low–high bar on the week's scale
        Row {
            id: days
            x: 18
            y: chart.y + chart.height + 14
            width: parent.width - 36
            readonly property var list: Weather.daily.slice(1, 6)
            readonly property real wlo: list.length ? Math.min(...list.map(d => d.min)) : 0
            readonly property real whi: list.length ? Math.max(...list.map(d => d.max)) : 1
            Repeater {
                model: days.list
                Item {
                    id: day
                    required property var modelData
                    required property int index
                    width: days.width / Math.max(1, days.list.length)
                    height: ahead.height - days.y - 12
                    opacity: Math.min(1, Math.max(0, root.draw * 3 - 0.6 - day.index * 0.25))
                    transform: Translate { y: 8 * (1 - day.opacity) }
                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            font.pixelSize: 11
                            font.weight: Font.Medium
                            text: Qt.formatDate(day.modelData.date, "ddd")
                        }
                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: Weather.icon(day.modelData.code, true)
                            size: 18
                            fill: 0
                            color: Theme.tone("action")
                        }
                        // the range bar: where this day sits in the week
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 64
                            height: 4
                            radius: 2
                            color: Qt.alpha(Theme.text, 0.08)
                            Rectangle {
                                readonly property real span: Math.max(1, days.whi - days.wlo)
                                x: parent.width * (day.modelData.min - days.wlo) / span
                                width: Math.max(4, parent.width * (day.modelData.max - day.modelData.min) / span)
                                height: parent.height
                                radius: 2
                                color: Theme.tone("action")
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.features: { "tnum": 1 }
                            color: Theme.text
                            text: Math.round(day.modelData.max) + "°  <font color='" + Theme.subtext + "'>" + Math.round(day.modelData.min) + "°</font>"
                            textFormat: Text.StyledText
                        }
                    }
                }
            }
        }
    }

    // not yet
    Card {
        width: parent.width
        height: parent.height
        id: waiting
        // on its way, or it didn't get through (components/emptystates.js)
        readonly property var what: Empty.weather({ ready: Weather.ready, failed: Weather.failed })
        visible: !!what
        Column {
            anchors.centerIn: parent
            spacing: 8
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: waiting.what?.glyph ?? ""; size: 32; color: Theme.subtext }
            Text { anchors.horizontalCenter: parent.horizontalCenter; font.family: Theme.font; font.pixelSize: 13; font.weight: Font.Medium; color: Theme.text; text: waiting.what?.text ?? "" }
            Label { anchors.horizontalCenter: parent.horizontalCenter; visible: text !== ""; text: waiting.what?.hint ?? "" }
            Item { width: 1; height: 2; visible: retry.visible }
            Action { id: retry; anchors.horizontalCenter: parent.horizontalCenter; visible: !!waiting.what?.retry; text: "Try again"; glyph: "refresh"; onHit: Weather.retry() }
        }
    }
}
