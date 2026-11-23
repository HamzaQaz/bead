import QtQuick
import QtQuick.Shapes
import qs.config

// A drawer that grows out of the bar's edge, joined to it with concave
// corners like the frame's own. It centres on anchorY; when that brings it
// near the top or bottom frame it docks there instead, merging into the
// frame with a concave corner. It sizes itself to its content.
Item {
    id: root

    property bool open: false
    property real anchorY: 0
    property real frameTop: 0      // the frame's inner edges
    property real frameBottom: 0
    property real contentW: 0
    property real contentH: 0
    default property alias content: slot.data

    readonly property real r: 16      // concave corners
    readonly property real outer: 18  // outer corners
    readonly property real pad: 14
    readonly property real snap: 70   // dock when this close to the frame
    readonly property real bodyW: contentW + pad * 2
    readonly property real bodyH: contentH + pad * 2

    readonly property real natY: anchorY - bodyH / 2
    readonly property bool dockBottom: natY + bodyH > frameBottom - snap
    readonly property bool dockTop: !dockBottom && natY < frameTop + snap
    readonly property real bodyY: dockBottom ? frameBottom - bodyH : dockTop ? frameTop : natY
    readonly property real topExt: dockTop ? 0 : r
    readonly property real botExt: dockBottom ? 0 : r

    property real progress: open ? 1 : 0
    Behavior on progress { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

    y: bodyY - topExt
    width: bodyW * progress + (dockTop || dockBottom ? r : 0)
    height: bodyH + topExt + botExt
    clip: true
    visible: progress > 0.001
    // moving between panels glides; opening starts in place
    Behavior on y { enabled: root.progress > 0.99; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Behavior on height { enabled: root.progress > 0.99; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            fillColor: Theme.frame
            strokeColor: "transparent"
            PathSvg {
                path: {
                    const r = root.r, R = root.outer, t = root.topExt;
                    const W = Math.max(root.bodyW * root.progress, r + R);
                    const yb = t + root.bodyH;
                    let p = root.dockTop
                        ? `M 0 0 H ${W + r} A ${r} ${r} 0 0 0 ${W} ${r} `
                        : `M 0 0 A ${r} ${r} 0 0 0 ${r} ${r} H ${W - R} A ${R} ${R} 0 0 1 ${W} ${r + R} `;
                    p += root.dockBottom
                        ? `V ${yb - r} A ${r} ${r} 0 0 0 ${W + r} ${yb} H 0 Z`
                        : `V ${yb - R} A ${R} ${R} 0 0 1 ${W - R} ${yb} H ${r} A ${r} ${r} 0 0 0 0 ${yb + r} Z`;
                    return p;
                }
            }
        }
    }

    Item {
        id: slot
        // the content travels in with the shape (from a little behind it) and
        // shows once most of the shape is out, so nothing sits cut off at its
        // moving edge
        x: root.pad - 22 * (1 - root.progress)
        y: root.topExt + root.pad
        width: root.contentW
        height: root.contentH
        opacity: Math.max(0, root.progress * 2.2 - 1.2)
    }
}
