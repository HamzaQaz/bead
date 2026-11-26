pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.config
import qs.services

// Wireless devices' batteries (UPower), and your phone's (KDE Connect): one row
// each with its level, state and a small gauge. Opened from the side bar's
// battery button.
PanelColumn {
    id: root
    width: 292
    spacing: 6

    PanelHeader { icon: "battery_full"; title: "Devices" }

    // its level as an icon and a small bar: red when low, green while charging
    component Gauge: Row {
        id: g
        property int level: 0
        property bool charging: false
        readonly property bool low: level <= 20 && !charging
        anchors.verticalCenter: parent?.verticalCenter
        spacing: 6
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            name: Osd.batteryGlyph(g.level, g.charging)
            size: 17
            fill: 1
            rotation: 90
            color: g.low ? Theme.tone("error") : g.charging ? Theme.tone("success") : Theme.subtext
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 54; height: 6; radius: 3
            color: Qt.alpha(Theme.text, 0.1)
            Rectangle {
                width: parent.width * g.level / 100
                height: parent.height
                radius: 3
                color: g.low ? Theme.tone("error") : g.charging ? Theme.tone("success") : Theme.text
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }
    }

    Repeater {
        model: Osd.peripherals
        PanelRow {
            id: row
            required property var modelData
            readonly property int level: Osd.pct(modelData)
            icon: Osd.glyphFor(modelData)
            title: modelData.model || "Device"
            sub: level + "%  ·  " + Osd.stateText(modelData)
            Gauge { level: row.level; charging: Osd.charging(row.modelData) }
        }
    }
    // your phone, through KDE Connect
    PanelRow {
        id: phoneRow
        readonly property var p: Phone.phone
        visible: !!p && p.battery !== null && p.battery !== undefined
        icon: "smartphone"
        title: p?.name ?? ""
        sub: !p ? "" : p.battery + "%  ·  " + (p.charging ? "Charging" : Phone.near ? "On battery" : "Last seen")
        Gauge { level: phoneRow.p?.battery ?? 0; charging: !!phoneRow.p?.charging }
    }
    Label {
        visible: Osd.peripherals.length === 0 && !(Phone.phone && Phone.phone.battery !== null && Phone.phone.battery !== undefined)
        x: 4
        text: "No wireless devices report a battery"
    }
}
