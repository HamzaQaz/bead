import QtQuick
import QtQuick.Effects
import "../../config"

// "bead." as the welcome's title: the word, with a bead as its full stop.
// The intro brings the letters into focus one after another (`reveal` 0 → 1:
// each rises a little out of a blur), grows the bead (`born` 0 → 1) and then
// sweeps a band of light across it all (`shine` 0 → 1). The ink runs from
// `from` to `to` across it (shaders/ink.frag) and glows softly. Size it by
// height; the width follows. `stop` is the bead's centre.
Item {
    id: wm
    property real reveal: 1
    property real born: 1
    property real shine: 0
    property color from: "white"
    property color to: "white"
    // the halo round the ink: 0 a soft dark shadow (for a bright backdrop),
    // 1 a glow in the ink's colour (for a dark one)
    property real glow: 1

    implicitHeight: 80
    width: letters.width + gap + d
    readonly property real d: height * 0.19         // the bead's size
    readonly property real gap: height * 0.04       // between the d and the bead
    readonly property real m: height * 0.3          // room round the ink for the glow and the blur
    readonly property real textY: (height - letters.height) / 2
    readonly property point stop: Qt.point(letters.width + gap + d / 2, textY + probe.baselineOffset - d / 2)
    readonly property real stagger: 0.22            // of a letter's own time, between one and the next

    Text { id: probe; visible: false; text: "bead"; font: wm.letterFont }
    readonly property font letterFont: Qt.font({ family: Theme.font, weight: Font.DemiBold, pixelSize: Math.max(1, Math.round(height * 0.86)), letterSpacing: -height * 0.02 })

    // drawn in white, coloured by the gradient, then given a soft glow
    Item {
        x: -wm.m; y: -wm.m
        width: wm.width + 2 * wm.m; height: wm.height + 2 * wm.m
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(wm.from.r * wm.glow, wm.from.g * wm.glow, wm.from.b * wm.glow, 0.45 + 0.15 * wm.glow)
            shadowBlur: 0.55
            shadowHorizontalOffset: 0
            shadowVerticalOffset: (1 - wm.glow) * wm.height * 0.03
        }
        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: ShaderEffect {
                property color from: wm.from
                property color to: wm.to
                property real shine: wm.shine
                fragmentShader: Qt.resolvedUrl("../../shaders/ink.frag.qsb")
            }
            Row {
                id: letters
                x: wm.m; y: wm.m + wm.textY
                Repeater {
                    model: ["b", "e", "a", "d"]
                    Item {
                        id: slot
                        required property string modelData
                        required property int index
                        // this letter's own 0 → 1, a little after the one before
                        readonly property real t: {
                            const x = Math.max(0, Math.min(1, wm.reveal * (1 + 3 * wm.stagger) - index * wm.stagger));
                            return 1 - Math.pow(1 - x, 3);
                        }
                        width: glyph.implicitWidth; height: glyph.implicitHeight
                        Text {
                            id: glyph
                            text: slot.modelData
                            color: "white"
                            font: wm.letterFont
                            opacity: slot.t
                            y: (1 - slot.t) * wm.height * 0.28
                            layer.enabled: slot.t < 0.999
                            layer.effect: MultiEffect {
                                blurEnabled: true
                                blur: 1 - slot.t
                                blurMax: 40
                                autoPaddingEnabled: true
                            }
                        }
                    }
                }
            }
            Rectangle { // the bead
                width: wm.d; height: wm.d; radius: wm.d / 2
                x: wm.m + wm.stop.x - wm.d / 2
                y: wm.m + wm.stop.y - wm.d / 2
                scale: wm.born
                visible: wm.born > 0.01
            }
        }
    }
}
