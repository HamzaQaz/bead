pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// Draws a still wallpaper on every screen (live ones are linux-wallpaperengine's
// job). A new picture fades in on top of the old one; only once it's fully in
// does the old one go, so the crossfade never dips to black.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win
        required property ShellScreen modelData
        screen: modelData
        visible: Wallpaper.kind === "still" && Wallpaper.current !== ""
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.namespace: "bead-background"
        color: "black"

        readonly property string src: Wallpaper.kind === "still" ? Wallpaper.url(Wallpaper.current) : ""
        property Item front: a   // the layer showing now
        onSrcChanged: show(src)
        Component.onCompleted: if (src) show(src)

        // load into the back layer, and bring it forward once it's ready
        function show(url: string): void {
            if (!url) return;
            const back = front === a ? b : a;
            back.wanted = url;
            back.opacity = 0;
            back.source = "";     // a source equal to the old one would never reload
            back.source = url;
        }
        function ready(layer: Item): void {
            if (layer.wanted !== src || layer === front) return; // superseded meanwhile
            const old = front;
            front = layer;
            layer.z = 1; old.z = 0;
            layer.opacity = 1;
            old.fadeOut = true;   // dropped once the new one has fully faded in
        }

        component Layer: Image {
            id: layer
            property string wanted: ""
            property bool fadeOut: false
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(win.width, win.height)
            asynchronous: true
            cache: false
            opacity: 0
            Behavior on opacity { NumberAnimation { id: fade; duration: 600; easing.type: Easing.OutCubic } }
            onStatusChanged: if (status === Image.Ready) win.ready(layer)
            onOpacityChanged: if (opacity === 1 && win.front === layer) { const o = layer === a ? b : a; if (o.fadeOut) { o.fadeOut = false; o.opacity = 0; } }
        }
        Layer { id: a }
        Layer { id: b }
    }
}
