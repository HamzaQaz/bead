pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import qs.components
import qs.config
import qs.services
import "calendar.js" as Cal

// Overview: greeting + clock + weather, calendar, now playing, system gauges.
Row {
    id: root
    required property var clock      // SystemClock
    required property MprisPlayer player
    spacing: 16

    function greeting(): string {
        const h = clock.date.getHours();
        return h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
    }

    // ── clock ──
    Column {
        width: 196
        height: parent.height
        spacing: 3
        Label {
            text: root.greeting() + (Demo.on ? "" : ", " + Quickshell.env("USER"))
            font.pixelSize: 12
        }
        Item { width: 1; height: 8 }
        Text {
            font.family: Theme.font
            font.pixelSize: 56
            font.weight: Font.DemiBold
            font.features: { "tnum": 1 }
            color: Theme.text
            text: Qt.formatTime(root.clock.date, "hh:mm")
        }
        Text {
            font.family: Theme.font
            font.pixelSize: 14
            color: Theme.text
            text: Qt.formatDate(root.clock.date, "dddd, d MMMM")
        }
        Item { width: 1; height: 6 }
        Row {
            spacing: 6
            visible: Weather.ready
            Icon { name: Weather.icon(Weather.code, Weather.isDay); size: 18; fill: 0; color: Theme.tone("action"); anchors.verticalCenter: parent.verticalCenter }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(Weather.temp) + "°  " + Weather.describe(Weather.code)
                color: Theme.text
            }
        }

        // live activities (the island's chips, which the open dashboard covers)
        Item { width: 1; height: 8; visible: liveRow.visible }
        LiveActivities {
            id: liveRow
            width: parent.width
        }
    }
    // ── calendar ──
    Card {
        id: cal
        width: 236
        height: parent.height
        readonly property date today: root.clock.date
        readonly property var now: ({ y: today.getFullYear(), m: today.getMonth(), d: today.getDate() })
        // the selected day (its month is the one shown); null: today
        property var picked: null
        readonly property var sel: picked ?? now
        readonly property var days: Cal.grid(sel, now)
        // a keyboard stop with keys of its own (calendar.js): arrows move the
        // day, [ ] page months, t goes back to today; off an edge the ring moves on
        readonly property bool focusStop: true
        readonly property bool focusCalendar: true
        function focusKey(name: string): bool {
            const r = Cal.key(sel, name, now);
            if (r) picked = r.day;
            return !!r;
        }
        onVisibleChanged: if (!visible) picked = null
        WheelHandler { onWheel: e => cal.picked = Cal.page(cal.sel, e.angleDelta.y > 0 ? -1 : 1) }
        Text {
            x: 16; y: 12
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Medium
            color: Theme.text
            text: Qt.formatDate(new Date(cal.sel.y, cal.sel.m, 1), "MMMM yyyy")
        }
        Grid {
            x: 12; y: 38
            columns: 7
            Repeater {
                model: ["M", "T", "W", "T", "F", "S", "S"]
                Label {
                    required property string modelData
                    width: 30; height: 22
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: 10
                    text: modelData
                }
            }
            Repeater {
                // a fixed set of cells that only change what they show: cells
                // rebuilt while the dashboard is up render their digits with
                // colour fringes, so paging must not rebuild them
                model: 42
                Item {
                    id: day
                    required property int index
                    readonly property var modelData: cal.days[index] ?? cal.days[0]
                    visible: index < cal.days.length
                    width: 30; height: 26
                    Rectangle {
                        anchors.centerIn: parent
                        width: 24; height: 24; radius: 12
                        visible: day.modelData.today
                        color: Theme.tone("action")
                    }
                    Rectangle { // the selected day, once one is picked
                        anchors.centerIn: parent
                        width: 24; height: 24; radius: 12
                        visible: cal.picked !== null && day.modelData.selected && !day.modelData.today
                        color: "transparent"
                        border.width: 1.5
                        border.color: Theme.tone("action")
                    }
                    Text {
                        anchors.centerIn: parent
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: day.modelData.today ? Font.DemiBold : Font.Normal
                        font.features: { "tnum": 1 }
                        color: day.modelData.today ? Theme.frame : day.modelData.inMonth ? Theme.text : Qt.alpha(Theme.text, 0.25)
                        text: day.modelData.n
                    }
                }
            }
        }
    }

    // ── now playing (compact) ──
    Card {
        id: media
        width: 226
        height: parent.height
        readonly property MprisPlayer p: root.player
        clip: true
        CoverBackdrop { anchors.fill: parent; radius: media.radius; source: media.p?.trackArtUrl ?? ""; blur: 0.6; veil: 0.45 }
        Column {
            // fills the card: track, progress, controls, then the volume
            x: 14
            y: 14
            width: parent.width - 28
            height: parent.height - 28
            spacing: Math.max(10, (height - 76 - 34 - 50 - 20) / 3)
            Row {
                spacing: 12
                Art { width: 76; height: 76; radius: 14; source: media.p?.trackArtUrl ?? "" }
                Column {
                    width: 110
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: Theme.text
                        text: media.p?.trackTitle || "Nothing playing"
                    }
                    Label { width: parent.width; elide: Text.ElideRight; text: media.p?.trackArtist ?? "" }
                    Label { width: parent.width; elide: Text.ElideRight; font.pixelSize: 10; opacity: 0.7; text: media.p?.identity ?? "" }
                }
            }
            Progress { width: parent.width; player: media.p; visible: (media.p?.length ?? 0) > 0 }
            Controls { anchors.horizontalCenter: parent.horizontalCenter; player: media.p; visible: media.p !== null }
            // the player's volume (its own when it has one, else the system's)
            Row {
                width: parent.width
                height: 20
                spacing: 8
                readonly property bool own: media.p?.volumeSupported ?? false
                readonly property real v: own ? media.p.volume : Audio.volume
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: parent.v <= 0.001 ? "volume_off" : parent.v < 0.5 ? "volume_down" : "volume_up"
                    ref: "volume_up"
                    size: 16
                    fill: 1
                    color: Theme.subtext
                }
                Slider {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 24 - 34
                    value: parent.v
                    onMoved: v => { if (parent.own) media.p.volume = v; else Audio.setVolume(v); }
                    onNudged: d => { const n = Math.max(0, Math.min(1, parent.v + d * 0.05)); if (parent.own) media.p.volume = n; else Audio.setVolume(n); }
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: 10
                    font.features: { "tnum": 1 }
                    text: Math.round(parent.v * 100) + "%"
                }
            }
        }
    }

    // ── system ──
    Card {
        width: parent.width - 196 - 236 - 226 - 16 * 3
        height: parent.height
        Column {
            anchors.fill: parent
            anchors.margins: 16
            // spread over the card's height
            spacing: Math.max(9, (height - 5 * 25) / 4)
            Gauge { label: "CPU"; value: Math.round(SysStats.cpu * 100) + "%"; level: SysStats.cpu }
            Gauge { label: "Memory"; value: SysStats.memUsedGb.toFixed(1) + " / " + Math.round(SysStats.memTotalGb) + " GB"; level: SysStats.mem }
            Gauge { label: "GPU"; value: Math.round(SysStats.gpu * 100) + "%"; level: SysStats.gpu }
            Gauge { label: "CPU temp"; value: Math.round(SysStats.cpuTemp) + "°"; level: SysStats.cpuTemp / 95 }
            Gauge { label: "Disk"; value: Math.round(SysStats.disk * 100) + "%"; level: SysStats.disk }
        }
    }
}
