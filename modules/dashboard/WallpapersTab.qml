pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.components
import qs.config
import qs.services

// Wallpapers: every still and live wallpaper as a thumbnail, two rows that
// scroll sideways (the wheel works too). Click one to switch; the colours
// follow. Filter by kind; shuffle picks another at random.
Item {
    id: root

    property string filter: "all"   // all | still | live
    readonly property list<var> shown: filter === "still" ? Wallpaper.stills : filter === "live" ? Wallpaper.lives : [...Wallpaper.lives, ...Wallpaper.stills]
    readonly property var cur: [...Wallpaper.lives, ...Wallpaper.stills].find(w => Wallpaper.isCurrent(w)) ?? null

    component Chip: Rectangle {
        id: chip
        property string label: ""
        property string glyph: ""
        property bool on: false
        signal hit()
        height: 30
        width: chipRow.implicitWidth + 24
        radius: 15
        color: on ? Theme.tone("action") : Qt.alpha(Theme.text, cma.containsMouse ? 0.11 : 0.06)
        Behavior on color { ColorAnimation { duration: 160 } }
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Icon { visible: chip.glyph !== ""; anchors.verticalCenter: parent.verticalCenter; name: chip.glyph; size: 16; fill: 1; color: chip.on ? Theme.frame : Theme.text }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold
                color: chip.on ? Theme.frame : Theme.text
                text: chip.label
            }
        }
        MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: chip.hit() }
    }

    // ── header: filters, what's on, shuffle ──
    Row {
        id: head
        spacing: 6
        Chip { label: "All"; on: root.filter === "all"; onHit: root.filter = "all" }
        Chip { label: "Live · " + Wallpaper.lives.length; glyph: "animation"; on: root.filter === "live"; onHit: root.filter = "live" }
        Chip { label: "Still · " + Wallpaper.stills.length; glyph: "image"; on: root.filter === "still"; onHit: root.filter = "still" }
    }
    Row {
        anchors.right: parent.right
        spacing: 10
        Label {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 300)
            elide: Text.ElideRight
            font.pixelSize: 12
            text: Wallpaper.busy ? "Switching…" : root.cur ? "Now: " + (root.cur.title ?? root.cur.name) : ""
        }
        Chip { glyph: "shuffle"; label: "Shuffle"; onHit: Wallpaper.random(root.filter) }
    }

    // ── the strip ──
    GridView {
        id: grid
        y: head.height + 12
        width: parent.width
        height: parent.height - y
        flow: GridView.FlowTopToBottom
        cellHeight: height / 2
        cellWidth: Math.round(cellHeight * 16 / 9) + 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.shown
        cacheBuffer: 600
        // open on the current one
        function showCurrent(): void {
            const i = root.shown.findIndex(w => Wallpaper.isCurrent(w));
            if (i >= 0) positionViewAtIndex(i, GridView.Center);
        }
        onCountChanged: showCurrent()
        onVisibleChanged: if (visible) showCurrent()

        WheelHandler {
            onWheel: e => {
                const d = e.angleDelta.y || e.angleDelta.x;
                grid.contentX = Math.max(0, Math.min(grid.contentWidth - grid.width, grid.contentX - d));
            }
        }

        delegate: Item {
            id: cell
            required property var modelData
            readonly property bool live: !!modelData.id
            readonly property bool on: Wallpaper.isCurrent(modelData)
            width: grid.cellWidth
            height: grid.cellHeight

            Rectangle {
                id: card
                anchors.fill: parent
                anchors.margins: 4
                radius: 12
                color: Qt.alpha(Theme.text, 0.06)
                // round the picture's corners (clip alone keeps them square)
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: mask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1
                }
                scale: ma.pressed ? 0.96 : ma.containsMouse ? 1.02 : 1
                Behavior on scale { SpringAnimation { spring: 5; damping: 0.32; epsilon: 0.002 } }

                Image {
                    anchors.fill: parent
                    source: Wallpaper.url(cell.live ? cell.modelData.preview : cell.modelData.path)
                    sourceSize: Qt.size(320, 180)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                // name on hover (or always for the current one)
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: 26
                    opacity: ma.containsMouse || cell.on ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.7) }
                    }
                    Text {
                        x: 8; width: parent.width - 16
                        anchors.bottom: parent.bottom; anchors.bottomMargin: 5
                        elide: Text.ElideRight
                        font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold
                        color: "white"
                        text: cell.live ? cell.modelData.title : cell.modelData.name
                    }
                }
                // live badge
                Rectangle {
                    visible: cell.live
                    x: 6; y: 6
                    width: 22; height: 22; radius: 11
                    color: Qt.rgba(0, 0, 0, 0.55)
                    Icon { anchors.centerIn: parent; name: cell.modelData.type === "video" ? "movie" : "animation"; size: 14; fill: 1; color: "white" }
                }
                // current: a check
                Rectangle {
                    visible: cell.on
                    anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 6
                    width: 22; height: 22; radius: 11
                    color: Theme.tone("action")
                    Icon { anchors.centerIn: parent; name: "check"; size: 15; fill: 1; color: Theme.frame }
                }
            }
            Rectangle {
                id: mask
                anchors.fill: card
                radius: 12
                visible: false
                layer.enabled: true
            }
            // the ring sits outside the masked card
            Rectangle {
                anchors.fill: card
                anchors.margins: -2
                radius: 14
                scale: card.scale
                color: "transparent"
                border.width: 2
                border.color: Theme.tone("action")
                visible: cell.on
            }
            MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Wallpaper.pick(cell.modelData) }
        }
    }
}
