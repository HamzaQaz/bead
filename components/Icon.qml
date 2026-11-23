import QtQuick
import qs.config

// A Material Symbols Rounded icon (the font Caelestia uses), by name:
// Icon { name: "partly_cloudy_day" }. `fill` animates the filled variant.
// The box is size × size and the glyph's outline is centred in it (the
// font's line metrics would otherwise sit it low and off centre), so
// anchors.centerIn really centres the glyph.
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
    renderType: Text.QtRendering // sub-pixel placement, so the centring holds at fractional scales

    width: size  // callers may override
    height: size
    horizontalAlignment: Text.AlignLeft
    verticalAlignment: Text.AlignTop
    TextMetrics { id: tm; font: icon.font; text: icon.name }
    FontMetrics { id: fm; font: icon.font }
    readonly property rect ink: tm.tightBoundingRect
    leftPadding: ink.width > 0 ? width / 2 - (ink.x + ink.width / 2) : 0
    topPadding: ink.height > 0 ? height / 2 - (fm.ascent + ink.y + ink.height / 2) : 0
}
