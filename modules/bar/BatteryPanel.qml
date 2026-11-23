pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.config
import qs.services

// Wireless devices' batteries (UPower): one row each with its level, state and
// a small gauge. Opened from the side bar's battery button.
PanelColumn {
    id: root
    width: 292
    spacing: 6

    PanelHeader { icon: "battery_full"; title: "Devices" }

    Repeater {
        model: Osd.peripherals
        PanelRow {
            id: row
            required property var modelData
            readonly property int level: Osd.pct(modelData)
            readonly property bool low: level <= 20 && !Osd.charging(modelData)
            icon: Osd.glyphFor(modelData)
            title: modelData.model || "Device"
            sub: level + "%  ·  " + Osd.stateText(modelData)
            Row {
                anchors.verticalCenter: parent?.verticalCenter
                spacing: 6
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: Osd.batteryGlyph(row.level, Osd.charging(row.modelData))
                    size: 17
                    fill: 1
                    rotation: 90
                    color: row.low ? Theme.tone("error") : Osd.charging(row.modelData) ? Theme.tone("success") : Theme.subtext
                }
                Rectangle { // gauge
                    anchors.verticalCenter: parent.verticalCenter
                    width: 54; height: 6; radius: 3
                    color: Qt.alpha(Theme.text, 0.1)
                    Rectangle {
                        width: parent.width * row.level / 100
                        height: parent.height
                        radius: 3
                        color: row.low ? Theme.tone("error") : Osd.charging(row.modelData) ? Theme.tone("success") : Theme.text
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }
    }
    Label {
        visible: Osd.peripherals.length === 0
        x: 4
        text: "No wireless devices report a battery"
    }
}
