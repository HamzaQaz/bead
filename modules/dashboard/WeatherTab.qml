pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.config
import qs.services

// Weather: now (big icon and temperature, conditions, feels like, humidity,
// wind, today's high/low) and the next 8 hours.
Row {
    id: root
    spacing: 16

    Card {
        width: 330
        height: parent.height
        visible: Weather.ready
        Column {
            x: 22; y: 18
            spacing: 2
            Row {
                spacing: 6
                Icon { name: "location_on"; size: 15; fill: 1; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
                Label { text: Weather.city || "Here"; anchors.verticalCenter: parent.verticalCenter }
            }
            Row {
                spacing: 14
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: Weather.icon(Weather.code, Weather.isDay)
                    size: 72
                    fill: 1
                    color: Theme.tone("action")
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        font.family: Theme.font
                        font.pixelSize: 52
                        font.weight: Font.DemiBold
                        color: Theme.text
                        text: Math.round(Weather.temp) + "°"
                    }
                    Text {
                        font.family: Theme.font
                        font.pixelSize: 14
                        color: Theme.text
                        text: Weather.describe(Weather.code)
                    }
                }
            }
        }
        Row {
            x: 22
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            spacing: 18
            Repeater {
                model: [
                    { icon: "thermostat", l: "Feels", v: Math.round(Weather.feels) + "°" },
                    { icon: "humidity_percentage", l: "Humidity", v: Math.round(Weather.humidity) + "%" },
                    { icon: "air", l: "Wind", v: Math.round(Weather.wind) + (Weather.fahrenheit ? " mph" : " km/h") },
                    { icon: "swap_vert", l: "High / low", v: Math.round(Weather.high) + "° / " + Math.round(Weather.low) + "°" }
                ]
                Column {
                    id: stat
                    required property var modelData
                    spacing: 2
                    Row {
                        spacing: 4
                        Icon { name: stat.modelData.icon; size: 13; color: Theme.subtext; anchors.verticalCenter: parent.verticalCenter }
                        Label { text: stat.modelData.l; font.pixelSize: 10; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Text {
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: Theme.text
                        text: stat.modelData.v
                    }
                }
            }
        }
    }

    Card {
        width: parent.width - 330 - 16
        height: parent.height
        visible: Weather.ready
        Label { x: 20; y: 16; text: "Next hours"; color: Theme.text; font.weight: Font.Medium; font.pixelSize: 13 }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            spacing: 4
            Repeater {
                model: Weather.hourly
                Rectangle {
                    id: hour
                    required property var modelData
                    required property int index
                    width: 54
                    height: 150
                    radius: 27
                    color: Qt.alpha(Theme.text, index === 0 ? 0.08 : 0)
                    Column {
                        anchors.centerIn: parent
                        spacing: 10
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            font.pixelSize: 11
                            text: hour.index === 0 ? "Now" : Qt.formatTime(hour.modelData.time, "HH:mm")
                        }
                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: Weather.icon(hour.modelData.code, hour.modelData.isDay)
                            size: 26
                            fill: 1
                            color: Theme.tone("action")
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            font.family: Theme.font
                            font.pixelSize: 14
                            font.weight: Font.Medium
                            color: Theme.text
                            text: Math.round(hour.modelData.temp) + "°"
                        }
                    }
                }
            }
        }
    }

    Item {
        width: parent.width
        height: parent.height
        visible: !Weather.ready
        Column {
            anchors.centerIn: parent
            spacing: 8
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "cloud_sync"; size: 30; color: Theme.subtext }
            Label { text: "Getting the weather…" }
        }
    }
}
