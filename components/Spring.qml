import QtQuick
import qs.config

// Animates `value` towards `to` along the sileo spring whenever `to` changes,
// starting from wherever it currently is (so interruptions stay smooth).
QtObject {
    id: s

    property real to: 0
    property int duration: Motion.dur
    property bool settleWhenShrinking: false
    property bool bounce: true            // false: always the bounce-free settle

    property real start: 0
    property real target: 0
    property bool bouncy: true
    property real t: 1
    readonly property real value: start + (target - start) * (bouncy ? Motion.spring(t) : Motion.settle(t))

    Component.onCompleted: { start = to; target = to; }
    onToChanged: {
        const v = value;
        bouncy = bounce && !(settleWhenShrinking && to < v);
        start = v;
        target = to;
        anim.restart();
    }

    property NumberAnimation anim: NumberAnimation { target: s; property: "t"; from: 0; to: 1; duration: s.duration }
}
