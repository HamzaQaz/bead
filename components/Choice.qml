import QtQuick
import qs.config

// a segmented choice
Rectangle {
    id: ch
    property list<var> options: []   // { v, t }
    property string value: ""
    signal chose(string v)
    // a stop for the dashboard's keyboard ring: Left/Right pick the one beside, Enter the next round
    readonly property bool focusStop: true
    function focusAdjust(dir: int): void {
        const i = options.findIndex(o => o.v === value), n = options[Math.max(0, Math.min(options.length - 1, i + dir))];
        if (n && n.v !== value) chose(n.v);
    }
    function focusPress(): void {
        if (!options.length) return;
        chose(options[(options.findIndex(o => o.v === value) + 1) % options.length].v);
    }
    width: seg.width + 4
    height: 26
    radius: 13
    color: Qt.alpha(Theme.text, 0.06)
    Rectangle { // the pill slides to the chosen one
        readonly property Item at: seg.children[ch.options.findIndex(o => o.v === ch.value)] ?? null
        visible: !!at
        x: 2 + (at?.x ?? 0)
        y: 2
        width: at?.width ?? 0
        height: 22
        radius: 11
        color: Theme.tone("action")
        Behavior on x { SpringAnimation { spring: 5; damping: 0.34; epsilon: 0.2 } }
        Behavior on width { SpringAnimation { spring: 5; damping: 0.34; epsilon: 0.2 } }
    }
    Row {
        id: seg
        x: 2; y: 2
        Repeater {
            model: ch.options
            Item {
                id: opt
                required property var modelData
                width: optText.implicitWidth + 18
                height: 22
                Text {
                    id: optText
                    anchors.centerIn: parent
                    font.family: Theme.font; font.pixelSize: Theme.caption; font.weight: Font.Medium
                    color: ch.value === opt.modelData.v ? Theme.frame : Theme.text
                    Behavior on color { ColorAnimation { duration: 150 } }
                    text: opt.modelData.t
                }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ch.chose(opt.modelData.v) }
            }
        }
    }
}
