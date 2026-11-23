import QtQuick
import qs.config

// A Material Symbols Rounded icon (the font Caelestia uses), by name:
// Icon { name: "partly_cloudy_day" }. `fill` animates the filled variant.
// The box is size × size and the glyph's outline is centred in it (the
// font's line metrics would otherwise sit it low and off centre), so
// anchors.centerIn really centres the glyph. Set `ref` to the family's full
// glyph (e.g. "wifi") so partial ones (wifi_1_bar) keep their place.
Text {
    id: icon
    property string name: ""
    property real size: 20
    property real fill: 0
    property string ref: ""   // glyph whose outline sets the centring
    Behavior on fill { NumberAnimation { duration: 200 } }

    font.family: "Material Symbols Rounded"
    font.pixelSize: size
    font.variableAxes: { "FILL": fill, "opsz": Math.max(20, Math.min(48, size)), "wght": 400 }
    color: Theme.text
    text: name
    // curve rendering: sub-pixel placement (so the centring holds at fractional
    // scales) and, unlike QtRendering, correct filled variants
    renderType: Text.CurveRendering

    width: size  // callers may override
    height: size
    horizontalAlignment: Text.AlignLeft
    verticalAlignment: Text.AlignTop
    TextMetrics { id: tm; font: icon.font; text: icon.ref || icon.name }
    FontMetrics { id: fm; font: icon.font }
    readonly property rect ink: tm.tightBoundingRect
    leftPadding: ink.width > 0 ? width / 2 - (ink.x + ink.width / 2) : 0
    topPadding: ink.height > 0 ? height / 2 - (fm.ascent + ink.y + ink.height / 2) : 0
}
