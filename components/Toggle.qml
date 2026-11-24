import QtQuick
import qs.config

// An on/off switch.
Rectangle {
    id: sw
    property bool checked: false
    signal toggled()
    // the dashboard's keyboard ring stops here (modules/dashboard/focusnav.js)
    readonly property bool focusStop: true
    function focusPress(): void { sw.toggled(); }
    width: 36
    height: 20
    radius: 10
    color: checked ? Theme.tone("action") : Qt.alpha(Theme.text, 0.15)
    Behavior on color { ColorAnimation { duration: 180 } }
    // the thumb is a little jelly pill: it widens while pressed and stretches
    // as it slides across, anchored to the side it's leaving
    Rectangle {
        id: thumb
        y: 3
        property real stretch: 0
        readonly property real w: 14 + (tma.pressed ? 4 : 0) + stretch
        width: w
        height: 14
        radius: 7
        x: sw.checked ? sw.width - width - 3 : 3
        color: sw.checked ? Theme.frame : Theme.text
        Behavior on x { SpringAnimation { spring: 5; damping: 0.35; epsilon: 0.2 } }
        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 180 } }
        SequentialAnimation {
            id: squish
            NumberAnimation { target: thumb; property: "stretch"; to: 7; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: thumb; property: "stretch"; to: 0; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 2 }
        }
    }
    onCheckedChanged: squish.restart()
    scale: tma.pressed ? 0.94 : 1
    Behavior on scale { SpringAnimation { spring: 6; damping: 0.35 } }
    MouseArea { id: tma; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
}
