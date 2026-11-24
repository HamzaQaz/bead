import QtQuick
import qs.config

// A Material Symbols Rounded icon, by name: Icon { name: "partly_cloudy_day" }.
// The box is size × size and the glyph's outline is centred in it (the font's
// line metrics would otherwise sit it low and off centre), so
// anchors.centerIn really centres the glyph. Set `ref` to the family's full
// glyph (e.g. "wifi") so partial ones (wifi_1_bar) keep their place.
//
// `fill` (0 → 1) fills the glyph in. The font's FILL axis isn't animated:
// its in-between values draw half-formed shapes, and the glyph's bounds
// change with it, which used to nudge the icon sideways. Instead there are
// two layers fixed at FILL 0 and FILL 1, placed identically (by the
// outline's metrics), and the solid one fades and grows in over the outline.
Item {
    id: icon
    property string name: ""
    property real size: 20
    property real fill: 0
    property string ref: ""   // glyph whose outline sets the centring
    property color color: Theme.text
    Behavior on fill { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    width: size  // callers may override
    height: size
    implicitWidth: size
    implicitHeight: size

    TextMetrics { id: tm; font: outline.font; text: icon.ref || icon.name }
    FontMetrics { id: fm; font: outline.font }
    readonly property rect ink: tm.tightBoundingRect
    // optical centring: a play triangle's outline-centre sits left of where
    // the eye puts its middle (its weight is all on the flat side), so nudge it
    readonly property real optical: ({ play_arrow: 0.04, send: 0.03 })[name] ?? 0
    readonly property real padX: ink.width > 0 ? width / 2 - (ink.x + ink.width / 2) + optical * size : 0
    // vertically: Qt's tight bounds are wrong for this font (they always end at
    // the baseline), but every Material Symbol is drawn centred on its 1 em
    // grid, which sits on the baseline, so centre that grid instead
    readonly property real padY: height / 2 - (fm.ascent - size / 2)

    component Layer: Text {
        property real axis: 0
        anchors.fill: parent
        font.family: "Material Symbols Rounded"
        font.pixelSize: icon.size
        font.variableAxes: { "FILL": axis, "opsz": Math.max(20, Math.min(48, icon.size)), "wght": 400 }
        text: icon.name
        // curve rendering: sub-pixel placement (so the centring holds at
        // fractional scales) and, unlike QtRendering, correct filled variants
        renderType: Text.CurveRendering
        horizontalAlignment: Text.AlignLeft
        verticalAlignment: Text.AlignTop
        leftPadding: icon.padX
        topPadding: icon.padY
    }

    // the outline gives way as the solid arrives (its alpha, not opacity, so
    // a translucent colour doesn't get doubled where the two overlap)
    Layer {
        id: outline
        axis: 0
        visible: icon.fill < 0.999
        color: Qt.alpha(icon.color, icon.color.a * Math.min(1, (1 - icon.fill) * 1.6))
    }
    Layer {
        axis: 1
        visible: icon.fill > 0.001
        color: Qt.alpha(icon.color, icon.color.a * Math.min(1, icon.fill * 1.4))
        scale: 0.82 + 0.18 * icon.fill
    }
}
