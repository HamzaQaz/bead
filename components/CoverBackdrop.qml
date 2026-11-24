import QtQuick
import QtQuick.Effects
import qs.config

// The album cover as a whole background: filling the space (cropped, not
// stretched), softly blurred, under a veil of the frame's colour so what's on
// top stays readable; darker towards the bottom, where the controls sit.
// Nothing shows without a cover. Used by the media tab, the dashboard's
// player and the island's media card.
Item {
    id: root
    property string source: ""
    property real radius: 0
    property real blur: 0.5        // 0 sharp … 1 very soft
    property real veil: 0.42       // how much frame colour lies over it
    readonly property bool ready: img.status === Image.Ready && source !== ""

    Image {
        id: img
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(512, 512)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
    }
    Rectangle { id: mask; anchors.fill: parent; radius: root.radius; visible: false; layer.enabled: true }
    MultiEffect {
        anchors.fill: parent
        source: img
        blurEnabled: root.blur > 0
        blur: root.blur
        blurMax: 48
        saturation: 0.2
        maskEnabled: true
        maskSource: mask
        opacity: root.ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 450 } }
    }
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        opacity: root.ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 450 } }
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Theme.frame, root.veil * 0.75) }
            GradientStop { position: 1; color: Qt.alpha(Theme.frame, Math.min(0.92, root.veil * 1.35)) }
        }
    }
}
