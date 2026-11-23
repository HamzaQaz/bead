import QtQuick
import qs.config

// A Material Symbols Rounded icon (the font Caelestia uses), by name:
// Icon { name: "partly_cloudy_day" }. `fill` animates the filled variant.
Text {
    id: icon
    property string name: ""
    property real size: 20
    property real fill: 0
    Behavior on fill { NumberAnimation { duration: 200 } }

    font.family: "Material Symbols Rounded"
    font.pixelSize: size
    font.variableAxes: { "FILL": fill, "opsz": Math.max(20, Math.min(48, size)), "wght": 400 }
    color: Theme.text
    text: name
    renderType: Text.NativeRendering
}
