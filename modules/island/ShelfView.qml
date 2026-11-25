pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.components
import qs.config
import qs.services
import "../../services/shelf.js" as S

// The island shelf (services/Shelf.qml): what hovering the island shows while
// the shelf holds something, what a drag over the island grows into, and the
// moment after a screenshot, recording, download or copied image.
//   ┌──────────────────────────────────────────┐
//   │  ╱▢  ▢╲  ▢   ▢                     (⌫)   │   a loose pile: hover one to lift it
//   │          mockup-v3.png                    │   the hovered one's name
//   └──────────────────────────────────────────┘
// A file dragged out leaves (an undo toast offers it back); folders stay.
Item {
    id: root

    property bool active: false
    property bool dropping: false   // something is being dragged over the island
    property bool showMoment: false // offering Shelf.moment instead of the shelf
    signal tookOut(var item)        // a drag out ended (for the undo toast)

    readonly property real pad: 14
    readonly property real tile: 64
    readonly property real gap: 10
    readonly property int perRow: 7
    readonly property var shown: showMoment && Shelf.moment ? [Shelf.moment] : Shelf.items
    readonly property int slots: shown.length + (dropping && !showMoment ? 1 : 0)
    readonly property int cols: Math.max(1, Math.min(perRow, slots))
    readonly property int rows: Math.max(1, Math.min(2, Math.ceil(slots / perRow)))
    readonly property real clearW: Shelf.count > 0 && !dropping ? 32 + gap : 0
    readonly property real wantW: showMoment ? 320
        : Math.max(200, pad * 2 + cols * tile + (cols - 1) * gap + clearW)
    readonly property real wantH: showMoment ? pad * 2 + 72
        : pad + rows * tile + (rows - 1) * gap + 10 + 16 + pad - 2

    property string hoveredName: ""
    readonly property string caption: dropping ? "Drop to keep it here"
        : hoveredName || (Shelf.count === 1 ? "1 thing · drag it into any app" : Shelf.count + " things · drag one into any app")

    // a file's type, as a tile shows it: "PDF", "ZIP"…
    function extOf(name: string): string {
        const i = name.lastIndexOf(".");
        return i > 0 && name.length - i <= 6 ? name.slice(i + 1).toUpperCase() : "";
    }

    // ── one thing ──
    component Tile: Item {
        id: t
        required property var modelData
        property int slot: 0          // its place in the pile (for the tilt)
        property bool big: false
        readonly property bool isText: modelData.kind === "text"
        readonly property bool real: !!modelData.path || isText
        readonly property bool lifted: hov.hovered || drag.active
        width: big ? 72 : root.tile; height: width
        z: lifted ? 10 : 0

        // a loose pile: each a little askew, straightened when you reach for it
        readonly property real tilt: big ? -4 : [-4, 3, -2, 4, -3, 2, -1][slot % 7]
        rotation: lifted ? 0 : tilt
        scale: drag.active ? 0.92 : hov.hovered ? 1.08 : 1
        Behavior on rotation { SpringAnimation { spring: 5; damping: 0.32; epsilon: 0.05 } }
        Behavior on scale { SpringAnimation { spring: 6; damping: 0.3; epsilon: 0.002 } }
        opacity: drag.active ? 0.4 : 1
        Behavior on opacity { NumberAnimation { duration: 140 } }

        // a soft shadow under the card
        Rectangle {
            anchors.fill: card; anchors.topMargin: 3; anchors.bottomMargin: -3
            radius: card.radius
            color: Qt.rgba(0, 0, 0, t.lifted ? 0.45 : 0.28)
        }
        ClippingRectangle {
            id: card
            anchors.fill: parent
            radius: 14
            color: t.modelData.kind === "folder" ? Qt.alpha(Theme.tone("action"), 0.16) : Qt.tint(Theme.frame, Qt.alpha(Theme.text, 0.09))
            border.width: 1
            border.color: Qt.alpha(Theme.text, t.lifted ? 0.22 : 0.08)

            Image {
                id: pic
                anchors.fill: parent
                visible: status === Image.Ready
                source: t.modelData.kind === "image" && t.modelData.path ? "file://" + t.modelData.path : ""
                sourceSize: Qt.size(160, 160)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
            }
            // text: the start of it, like a note
            Text {
                visible: t.isText
                anchors.fill: parent; anchors.margins: 8
                text: t.modelData.text
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 4
                font.family: Theme.font; font.pixelSize: 9
                lineHeight: 0.95
                color: Theme.text
            }
            // anything else: its icon and type
            Column {
                visible: !pic.visible && !t.isText
                anchors.centerIn: parent
                spacing: 1
                Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: ({ folder: "folder", video: "movie", image: "image" })[t.modelData.kind] ?? "draft"
                    size: t.modelData.kind === "folder" ? 28 : 22
                    fill: 1
                    color: t.modelData.kind === "folder" ? Theme.tone("action") : Theme.subtext
                }
                Text {
                    visible: t.modelData.kind !== "folder" && text !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.extOf(t.modelData.name)
                    font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.6
                    color: Theme.text
                }
            }
        }
        // take one off without using it
        Rectangle {
            visible: hov.hovered && !root.showMoment && !drag.active
            x: parent.width - 14; y: -6
            width: 20; height: 20; radius: 10
            color: xHov.hovered ? Theme.tone("error") : Theme.frame
            border.width: 1; border.color: Qt.alpha(Theme.text, 0.18)
            Icon { anchors.centerIn: parent; name: "close"; size: 12; color: Theme.text }
            HoverHandler { id: xHov; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: Shelf.remove(t.modelData.id) }
        }

        HoverHandler {
            id: hov
            cursorShape: t.real ? Qt.OpenHandCursor : Qt.ArrowCursor
            onHoveredChanged: if (hovered) root.hoveredName = t.modelData.kind === "folder" ? t.modelData.name + " · stays after you drag it" : t.modelData.name; else if (root.hoveredName.startsWith(t.modelData.name)) root.hoveredName = ""
        }

        // drag it into any app: a file as a file, text as text
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
        Drag.proposedAction: Qt.CopyAction
        Drag.mimeData: t.isText ? ({ "text/plain": t.modelData.text }) : ({ "text/uri-list": S.uriList(t.modelData.path) })
        Drag.hotSpot: Qt.point(width / 2, height / 2)
        Drag.onDragFinished: {
            t.Drag.active = false;
            Shelf.momentHeld = false;
            if (Shelf.droppedBack) { Shelf.droppedBack = false; return; } // let go over the island itself
            if (root.showMoment) { Shelf.dropMoment(); return; }
            if (t.modelData.kind !== "folder") root.tookOut(t.modelData);
            Shelf.used(t.modelData.id);
        }
        DragHandler {
            id: drag
            enabled: t.real
            target: null
            onActiveChanged: {
                if (!active) return;
                Shelf.momentHeld = root.showMoment;
                card.grabToImage(r => { t.Drag.imageSource = r.url; t.Drag.active = true; });
            }
        }
    }

    // ── the pile ──
    Grid {
        id: pile
        visible: !root.showMoment
        x: root.pad; y: root.pad
        columns: root.perRow
        spacing: root.gap
        // new things pop in; the rest make room
        add: Transition { NumberAnimation { property: "scale"; from: 0.4; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
        move: Transition { NumberAnimation { properties: "x,y"; duration: 320; easing.type: Easing.OutCubic } }

        // the drop slot, while something hovers the island
        Rectangle {
            visible: root.dropping
            width: root.tile; height: root.tile
            radius: 14
            color: Qt.alpha(Theme.tone("action"), 0.12)
            border.width: 1.5
            border.color: Qt.alpha(Theme.tone("action"), 0.7)
            Icon { anchors.centerIn: parent; name: "add"; size: 26; color: Theme.tone("action") }
            SequentialAnimation on scale {
                running: root.dropping; loops: Animation.Infinite
                NumberAnimation { to: 1.07; duration: 520; easing.type: Easing.InOutSine }
                NumberAnimation { to: 0.97; duration: 520; easing.type: Easing.InOutSine }
            }
        }
        Repeater {
            model: ScriptModel { values: root.showMoment ? [] : root.shown.slice(0, root.perRow * 2 - (root.dropping ? 1 : 0)); objectProp: "id" }
            delegate: Tile { required property int index; slot: index }
        }
    }

    // sweep it all away
    Rectangle {
        visible: !root.showMoment && root.clearW > 0
        x: root.width - root.pad - 32
        y: root.pad + (root.tile - 32) / 2
        width: 32; height: 32; radius: 16
        color: clearHov.hovered ? Qt.alpha(Theme.tone("error"), 0.2) : Qt.alpha(Theme.text, 0.06)
        Behavior on color { ColorAnimation { duration: 140 } }
        Icon { anchors.centerIn: parent; name: "delete_sweep"; size: 18; color: clearHov.hovered ? Theme.tone("error") : Theme.subtext }
        HoverHandler { id: clearHov; cursorShape: Qt.PointingHandCursor; onHoveredChanged: root.hoveredName = hovered ? "Clear the shelf" : "" }
        TapHandler { onTapped: Shelf.clear() }
    }

    // the hovered one's name (or how many there are)
    RollText {
        visible: !root.showMoment
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height - root.pad - 14
        maxWidth: root.width - root.pad * 2
        rise: 5
        font.family: Theme.font
        font.pixelSize: 11
        color: root.dropping ? Theme.tone("action") : root.hoveredName ? Theme.text : Theme.subtext
        text: root.caption
    }

    // ── the moment: one thing, just made ──
    Item {
        visible: root.showMoment && !!Shelf.moment
        anchors.fill: parent
        HoverHandler { onHoveredChanged: Shelf.momentHeld = hovered }
        Loader {
            x: root.pad; anchors.verticalCenter: parent.verticalCenter
            active: root.showMoment && !!Shelf.moment
            sourceComponent: Tile { modelData: Shelf.moment; big: true }
        }
        Column {
            x: root.pad + 72 + 14; anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - root.pad
            spacing: 4
            Label { width: parent.width; elide: Text.ElideMiddle; text: Shelf.moment?.name ?? ""; font.pixelSize: 13; color: Theme.text }
            Label { text: "Drag it anywhere, or keep it"; font.pixelSize: 11; color: Theme.subtext }
            Row {
                spacing: 8
                topPadding: 4
                Action { text: "Keep"; glyph: "inventory_2"; onHit: Shelf.keepMoment() }
            }
        }
        // the seconds left, running down (held while you're on it)
        Rectangle {
            x: root.pad; y: parent.height - 6
            width: (parent.width - root.pad * 2) * Shelf.momentLeft
            height: 2; radius: 1
            color: Qt.alpha(Theme.tone("action"), 0.6)
        }
    }
}
