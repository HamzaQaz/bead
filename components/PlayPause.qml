import QtQuick
import QtQuick.Shapes

// The play / pause glyph as one shape that morphs: the two pause bars bend
// into the two halves of the play triangle (and back) with a springy settle. The triangle sits a touch right of the box
// centre, where the eye puts its middle.
Item {
    id: root
    property bool playing: false   // true shows pause
    property color color: "white"
    property real size: 24
    width: size
    height: size

    // 0 = play, 1 = pause
    property real t: playing ? 1 : 0
    Behavior on t { SpringAnimation { spring: 7; damping: 0.42; epsilon: 0.002 } }
    function lerp(a: real, b: real): real { return a + (b - a) * t; }
    // play halves and pause bars, in units of size
    readonly property var playL: [[0.24, 0.12], [0.55, 0.30], [0.55, 0.70], [0.24, 0.88]]
    readonly property var playR: [[0.55, 0.30], [0.86, 0.50], [0.86, 0.50], [0.55, 0.70]]
    readonly property var pauseL: [[0.22, 0.14], [0.42, 0.14], [0.42, 0.86], [0.22, 0.86]]
    readonly property var pauseR: [[0.58, 0.14], [0.78, 0.14], [0.78, 0.86], [0.58, 0.86]]
    function pt(a: var, b: var, i: int, k: int): real { return size * lerp(a[i][k], b[i][k]); }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: root.color
            strokeColor: root.color
            strokeWidth: root.size * 0.07   // rounds the corners
            joinStyle: ShapePath.RoundJoin
            startX: root.pt(root.playL, root.pauseL, 0, 0); startY: root.pt(root.playL, root.pauseL, 0, 1)
            PathLine { x: root.pt(root.playL, root.pauseL, 1, 0); y: root.pt(root.playL, root.pauseL, 1, 1) }
            PathLine { x: root.pt(root.playL, root.pauseL, 2, 0); y: root.pt(root.playL, root.pauseL, 2, 1) }
            PathLine { x: root.pt(root.playL, root.pauseL, 3, 0); y: root.pt(root.playL, root.pauseL, 3, 1) }
            PathLine { x: root.pt(root.playL, root.pauseL, 0, 0); y: root.pt(root.playL, root.pauseL, 0, 1) }
        }
        ShapePath {
            fillColor: root.color
            strokeColor: root.color
            strokeWidth: root.size * 0.07
            joinStyle: ShapePath.RoundJoin
            startX: root.pt(root.playR, root.pauseR, 0, 0); startY: root.pt(root.playR, root.pauseR, 0, 1)
            PathLine { x: root.pt(root.playR, root.pauseR, 1, 0); y: root.pt(root.playR, root.pauseR, 1, 1) }
            PathLine { x: root.pt(root.playR, root.pauseR, 2, 0); y: root.pt(root.playR, root.pauseR, 2, 1) }
            PathLine { x: root.pt(root.playR, root.pauseR, 3, 0); y: root.pt(root.playR, root.pauseR, 3, 1) }
            PathLine { x: root.pt(root.playR, root.pauseR, 0, 0); y: root.pt(root.playR, root.pauseR, 0, 1) }
        }
    }
}
