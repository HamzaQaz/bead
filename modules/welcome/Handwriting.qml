import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import "script.js" as Script

// "bead." written by hand, in the manner of a "hello" screen: EMS Allure's
// pen line (script.js), one round pen moving left to right (`progress`
// 0 → 1 along the whole line, at an even pace), then the full stop drops in
// as a bead (`dot` 0 → 1). The ink runs from `from` to `to` across the word
// and glows softly. Size it by height; the width follows.
Item {
    id: hw
    property real progress: 1
    property real dot: 1
    property color from: "white"
    property color to: "white"
    property real weight: 0.062 // the pen's width, in heights (fine, for a script)
    // the halo round the ink: 0 a soft dark shadow (for a bright backdrop),
    // 1 a glow in the ink's colour (for a dark one)
    property real glow: 1

    implicitHeight: 80
    width: height * Script.aspect
    readonly property real m: height * 0.12 // room round the ink for the pen's width and the glow
    readonly property real total: Script.lengths.reduce((a, b) => a + b, 0)

    // the strokes as far as the pen has got (whole strokes, then part of the
    // one it's on), as lists of points in px
    readonly property var paths: {
        const out = [];
        let left = Math.max(0, Math.min(1, progress)) * total;
        const h = height, m = hw.m;
        for (let s = 0; s < Script.strokes.length && left > 0; s++) {
            const st = Script.strokes[s], n = st.length / 2;
            const len = Script.lengths[s];
            const upTo = left >= len ? n : Math.max(1, Math.floor(left / len * (n - 1)) + 1);
            const pts = [];
            for (let i = 0; i < upTo; i++)
                pts.push(Qt.point(m + st[2 * i] * h, m + st[2 * i + 1] * h));
            // the pen sits between two samples: finish at its exact place
            if (upTo < n) {
                const f = left / len * (n - 1) - (upTo - 1);
                pts.push(Qt.point(m + (st[2 * (upTo - 1)] + (st[2 * upTo] - st[2 * (upTo - 1)]) * f) * h,
                                  m + (st[2 * (upTo - 1) + 1] + (st[2 * upTo + 1] - st[2 * (upTo - 1) + 1]) * f) * h));
            }
            if (pts.length > 1) out.push(pts);
            left -= len;
        }
        return out;
    }

    // the ink: drawn in white, coloured by the gradient (shaders/ink.frag),
    // then given a soft glow
    Item {
        x: -hw.m; y: -hw.m
        width: hw.width + 2 * hw.m; height: hw.height + 2 * hw.m
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: Qt.rgba(hw.from.r * hw.glow, hw.from.g * hw.glow, hw.from.b * hw.glow, 0.45 + 0.15 * hw.glow)
            shadowBlur: 0.55
            shadowHorizontalOffset: 0
            shadowVerticalOffset: (1 - hw.glow) * hw.height * 0.03
        }
        Item {
            id: ink
            anchors.fill: parent
            layer.enabled: true
            layer.samples: 4
            layer.effect: ShaderEffect {
                property color from: hw.from
                property color to: hw.to
                fragmentShader: Qt.resolvedUrl("../../shaders/ink.frag.qsb")
            }
            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "white"
                    strokeWidth: hw.height * hw.weight
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathMultiline { paths: hw.paths }
                }
            }
            Rectangle { // the bead
                readonly property real d: hw.height * 0.15
                width: d; height: d; radius: d / 2
                x: hw.m + Script.dot[0] * hw.height - d / 2
                y: hw.m + (Script.dot[1] - 0.03) * hw.height - d / 2
                scale: hw.dot
                visible: hw.dot > 0.01
            }
        }
    }
}
