pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import qs.components
import qs.config
import qs.services

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
        Row {
            spacing: 10
            Item {
                width: 38; height: 38
                Image {
                    id: face
                    anchors.fill: parent
                    source: "file://" + Quickshell.env("HOME") + "/.face"
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectCrop
                    visible: false
                }
                Rectangle { id: faceMask; anchors.fill: parent; radius: 19; visible: false; layer.enabled: true }
                MultiEffect { anchors.fill: parent; source: face; maskEnabled: true; maskSource: faceMask; visible: face.status === Image.Ready }
                Icon { anchors.centerIn: parent; visible: face.status !== Image.Ready; name: "person"; fill: 1; color: Theme.subtext }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Label { text: root.greeting(); font.pixelSize: 11 }
                Text {
                    font.family: Theme.font
                    font.pixelSize: 14
                    font.weight: Font.Medium
                    color: Theme.text
                    text: Quickshell.env("USER")
                }
            }
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
            Icon { name: Weather.icon(Weather.code, Weather.isDay); size: 18; fill: 1; color: Theme.tone("action"); anchors.verticalCenter: parent.verticalCenter }
            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Math.round(Weather.temp) + "°  " + Weather.describe(Weather.code)
                color: Theme.text
            }
        }
        Label { text: SysStats.uptime ? "up " + SysStats.uptime : "" }
    }

    // ── calendar ──
    Card {
        id: cal
        width: 236
        height: parent.height
        readonly property date today: root.clock.date
        readonly property int year: today.getFullYear()
        readonly property int month: today.getMonth()
        readonly property var days: {
            const first = new Date(year, month, 1);
            const offset = (first.getDay() + 6) % 7; // Monday first
            const out = [];
            for (let i = 0; i < 42; i++) {
                const d = new Date(year, month, 1 - offset + i);
                out.push({ n: d.getDate(), inMonth: d.getMonth() === month, today: d.toDateString() === today.toDateString() });
            }
            return out;
        }
        Text {
            x: 16; y: 12
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Medium
            color: Theme.text
            text: Qt.formatDate(cal.today, "MMMM yyyy")
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
                model: cal.days.slice(0, cal.days[35].inMonth ? 42 : 35)
                Item {
                    id: day
                    required property var modelData
                    width: 30; height: 26
                    Rectangle {
                        anchors.centerIn: parent
                        width: 24; height: 24; radius: 12
                        visible: day.modelData.today
                        color: Theme.tone("action")
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
        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12
            Row {
                spacing: 12
                Art { width: 64; height: 64; radius: 12; source: media.p?.trackArtUrl ?? "" }
                Column {
                    width: 122
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
        }
    }

    // ── system ──
    Card {
        width: parent.width - 196 - 236 - 226 - 16 * 3
        height: parent.height
        Column {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 9
            Gauge { label: "CPU"; value: Math.round(SysStats.cpu * 100) + "%"; level: SysStats.cpu }
            Gauge { label: "Memory"; value: SysStats.memUsedGb.toFixed(1) + " / " + Math.round(SysStats.memTotalGb) + " GB"; level: SysStats.mem }
            Gauge { label: "GPU"; value: Math.round(SysStats.gpu * 100) + "%"; level: SysStats.gpu }
            Gauge { label: "CPU temp"; value: Math.round(SysStats.cpuTemp) + "°"; level: SysStats.cpuTemp / 95 }
            Gauge { label: "Disk"; value: Math.round(SysStats.disk * 100) + "%"; level: SysStats.disk }
        }
    }
}
