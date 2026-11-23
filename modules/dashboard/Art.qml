import QtQuick
import QtQuick.Effects
import qs.components
import qs.config

// Rounded album art with a music-note placeholder. A new cover loads behind
// the old one and fades in over it (with a small settle) once it's ready, so
// a track change never flashes empty.
Item {
    id: root
    property url source: ""
    property real radius: 12
    readonly property bool ready: a.status === Image.Ready || b.status === Image.Ready

    // which layer is in front; the other loads the next cover
    property bool frontA: true
    Component.onCompleted: a.source = source // the first cover, straight in
    onSourceChanged: {
        const back = frontA ? b : a;
        if (String((frontA ? a : b).source) === String(source)) return;
        back.source = source;
    }

    Rectangle { anchors.fill: parent; radius: root.radius; color: Qt.alpha(Theme.text, 0.08) }
    Rectangle { id: mask; anchors.fill: parent; radius: root.radius; visible: false; layer.enabled: true }

    component Layer: Item {
        id: layerItem
        property alias source: img.source
        property alias status: img.status
        property bool front: false
        anchors.fill: parent
        z: front ? 1 : 0
        opacity: front ? 1 : 0
        scale: front ? 1 : 1.04
        Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 520; easing.type: Easing.OutCubic } }
        Image {
            id: img
            anchors.fill: parent
            sourceSize: Qt.size(400, 400)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
        }
        MultiEffect { anchors.fill: parent; source: img; maskEnabled: true; maskSource: mask; visible: img.status === Image.Ready }
    }
    Layer {
        id: a
        front: root.frontA
        onStatusChanged: if (status === Image.Ready && !front && String(source) === String(root.source)) root.frontA = true
    }
    Layer {
        id: b
        front: !root.frontA
        onStatusChanged: if (status === Image.Ready && !front && String(source) === String(root.source)) root.frontA = false
    }

    Icon { anchors.centerIn: parent; visible: !root.ready; name: "music_note"; size: Math.min(root.width, root.height) * 0.38; color: Theme.subtext }
}
