pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import qs.components
import qs.config
import qs.services

// Notification history: a panel that slides out of the top-right corner of the
// primary monitor's frame, merged into it like the popup stack. Header with Do
// Not Disturb and clear-all; Today / Yesterday / Earlier sections; an app with
// several notifications is one group (newest shown, the rest on expand, × clears
// the group); per notification: click opens it, × dismisses it, action chips
// while the app still has it open. Esc or the toggle closes it.
// IPC target "notifs": toggle | open | close | clear | dnd.
Scope {
    id: root

    IpcHandler {
        target: "notifs"
        function toggle(): void { Notifs.panelOpen = !Notifs.panelOpen; }
        function open(): void { Notifs.panelOpen = true; }
        function close(): void { Notifs.panelOpen = false; }
        function clear(): void { Notifs.clear(); }
        // clear one app's notifications (by its name)
        function clearApp(app: string): void { Notifs.removeApp(app); }
        function dnd(): void { Notifs.dnd = !Notifs.dnd; }
    }

    // "now", "5m", "2h", "3d": refreshed every 30 s while open
    property real now: Date.now()
    Timer { interval: 30000; repeat: true; running: Notifs.panelOpen; onTriggered: root.now = Date.now() }
    Connections { target: Notifs; function onPanelOpenChanged() { root.now = Date.now(); } }
    function ago(t: real): string {
        const s = Math.max(0, (now - t) / 1000);
        if (s < 60) return "now";
        if (s < 3600) return Math.floor(s / 60) + "m";
        if (s < 86400) return Math.floor(s / 3600) + "h";
        return Math.floor(s / 86400) + "d";
    }

    // ── rows: sections, app groups, notifications ──
    // a group's key ("Today:Discord") -> expanded
    property var expanded: ({})
    function toggleGroup(gk: string): void {
        expanded = Object.assign({}, expanded, { [gk]: !expanded[gk] });
    }
    readonly property list<var> rows: {
        const d = new Date(now);
        const today = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
        const section = t => t >= today ? "Today" : t >= today - 86400000 ? "Yesterday" : "Earlier";
        const sections = [];
        for (const e of Notifs.entries) { // newest first
            const title = section(e.time);
            let sec = sections.find(x => x.title === title);
            if (!sec) { sec = { title, order: [], by: {} }; sections.push(sec); }
            const app = e.appName || "Notification";
            if (!sec.by[app]) { sec.by[app] = []; sec.order.push(app); }
            sec.by[app].push(e);
        }
        // headings only once there's more than today
        const headings = sections.length > 1 || (sections.length === 1 && sections[0].title !== "Today");
        const out = [];
        for (const sec of sections) {
            if (headings) out.push({ key: "s:" + sec.title, type: "section", title: sec.title });
            for (const app of sec.order) {
                const list = sec.by[app];
                if (list.length === 1) { out.push({ key: list[0].key, type: "notif", e: list[0], grouped: false }); continue; }
                const gk = sec.title + ":" + app;
                const open = !!expanded[gk];
                out.push({ key: "g:" + gk, type: "group", gk, app, open, count: list.length, keys: list.map(x => x.key), first: list[0] });
                for (const e of open ? list : list.slice(0, 1))
                    out.push({ key: e.key, type: "notif", e, grouped: true, more: open ? 0 : list.length - 1 });
            }
        }
        return out;
    }
    function iconOf(e: var): url {
        return e?.image ? e.image : e?.appIcon ? Quickshell.iconPath(e.appIcon, true) : "";
    }

    // Lucide
    readonly property string bellIcon: "M10.268 21a2 2 0 0 0 3.464 0 M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326"
    readonly property string bellOffIcon: "M10.268 21a2 2 0 0 0 3.464 0 M17 17H4a1 1 0 0 1-.74-1.673C4.59 13.956 6 12.499 6 8a6 6 0 0 1 .258-1.742 M2 2l20 20 M8.668 3.01A6 6 0 0 1 18 8c0 2.687.77 4.653 1.707 6.05"
    readonly property string trashIcon: "M3 6h18 M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6 M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"
    readonly property string xIcon: "M18 6 6 18 M6 6l12 12"
    readonly property string chevronIcon: "M6 9l6 6 6-6"

    component Glyph: Shape {
        id: g
        property string path: ""
        property color tone: Theme.text
        property real size: 16
        width: size; height: size
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: g.tone
            strokeWidth: 2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            scale: Qt.size(g.size / 24, g.size / 24)
            PathSvg { path: g.path }
        }
    }

    component RoundButton: Rectangle {
        id: rb
        property string icon: ""
        property bool active: false
        signal clicked()
        width: 30; height: 30; radius: 15
        color: Qt.alpha(Theme.text, active ? 0.16 : ma.containsMouse ? 0.10 : 0.05)
        Behavior on color { ColorAnimation { duration: 150 } }
        Glyph { anchors.centerIn: parent; size: 15; path: rb.icon; tone: rb.active ? Theme.tone("action") : Theme.subtext }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: rb.clicked() }
    }

    PanelWindow {
        id: win

        // the primary monitor, like the pop-ups (Settings.home)
        readonly property ShellScreen focused: Quickshell.screens.find(s => s.name === Settings.home) ?? Quickshell.screens[0]
        property ShellScreen held: focused
        screen: held
        Connections {
            target: Notifs
            function onPanelOpenChanged() { if (Notifs.panelOpen) win.held = win.focused; }
        }

        visible: Notifs.panelOpen || enter.value > 0.001
        anchors.top: true
        anchors.right: true
        readonly property real wallW: Theme.frameThickness / devicePixelRatio
        implicitWidth: panel.w + wallW + 40
        implicitHeight: screen?.height ?? 800
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "bead-history"
        // clicking into it gives it the keyboard (for Esc); it never grabs it
        WlrLayershell.keyboardFocus: Notifs.panelOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        mask: Region { item: Notifs.panelOpen ? hit : null }

        Spring { id: enter; to: Notifs.panelOpen ? 1 : 0; duration: Motion.dur * 0.8 }

        // the panel and the frame's corner as one shape (same shader as the stack)
        ShaderEffect {
            anchors.fill: parent
            visible: enter.value > 0.001
            fragmentShader: Qt.resolvedUrl("../../shaders/stack.frag.qsb")
            property size size: Qt.size(width, height)
            property vector4d inner: Qt.vector4d(-2000, win.wallW, width - win.wallW + 2000, height + 2000)
            property real innerRadius: 20 / win.devicePixelRatio
            property real radius: 20
            property real goo: 20
            property color fill: Theme.frame
            property vector4d p0: Qt.vector4d(panel.x + panel.slide, panel.y, panel.w + panel.tuck, panelH.value)
            property vector4d b0: Qt.vector4d(0, 0, 0, 0)
            property vector4d p1: b0; property vector4d p2: b0; property vector4d p3: b0
            property vector4d p4: b0; property vector4d p5: b0; property vector4d p6: b0; property vector4d p7: b0
            property vector4d b1: b0; property vector4d b2: b0; property vector4d b3: b0
            property vector4d b4: b0; property vector4d b5: b0; property vector4d b6: b0; property vector4d b7: b0
        }

        Spring { id: panelH; to: panel.h; settleWhenShrinking: true }

        Item {
            id: panel
            readonly property real w: 380
            readonly property real maxH: win.height * 0.7
            readonly property real headerH: 56
            readonly property real h: Math.min(maxH, Math.max(150, headerH + list.contentHeight + 14))
            readonly property real tuck: 20 + win.wallW // right side hidden in the frame
            readonly property real slide: (1 - enter.value) * (w + 40)
            readonly property real textIn: Math.max(0, Math.min(1, (enter.value - 0.5) / 0.5))

            x: win.width - win.wallW - w
            y: win.wallW + 6
            width: w
            height: panelH.value

            focus: Notifs.panelOpen
            Keys.onEscapePressed: Notifs.panelOpen = false

            Item {
                id: hit
                x: panel.slide
                width: panel.w + win.wallW
                height: panelH.value
            }

            Item {
                id: content
                x: panel.slide
                width: panel.w
                height: panelH.value
                clip: true
                opacity: panel.textIn

                // ── header ──
                Row {
                    x: 18
                    y: 18
                    spacing: 8
                    Text {
                        font.family: Theme.font
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: Theme.text
                        text: "Notifications"
                    }
                    Text {
                        anchors.baseline: parent.children[0].baseline
                        visible: Notifs.entries.length > 0
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.features: { "tnum": 1 }
                        color: Theme.subtext
                        text: Notifs.entries.length
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    y: 13
                    spacing: 6
                    RoundButton {
                        icon: Notifs.dnd ? root.bellOffIcon : root.bellIcon
                        active: Notifs.dnd
                        onClicked: Notifs.dnd = !Notifs.dnd
                    }
                    RoundButton {
                        icon: root.trashIcon
                        visible: Notifs.entries.length > 0
                        onClicked: Notifs.clear()
                    }
                }
                Text {
                    x: 18
                    y: 38
                    visible: Notifs.dnd
                    font.family: Theme.font
                    font.pixelSize: 11
                    color: Theme.subtext
                    text: "Do not disturb is on"
                }

                // ── empty ──
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: panel.headerH + 18
                    spacing: 8
                    visible: Notifs.entries.length === 0
                    Glyph { anchors.horizontalCenter: parent.horizontalCenter; size: 22; path: root.bellIcon; tone: Theme.neutral }
                    Text {
                        font.family: Theme.font
                        font.pixelSize: 13
                        color: Theme.subtext
                        text: "All caught up"
                    }
                }

                // ── list ──
                ListView {
                    id: list
                    x: 8
                    y: panel.headerH
                    width: panel.w - 16
                    height: panel.maxH - panel.headerH - 8
                    spacing: 4
                    boundsBehavior: Flickable.StopAtBounds
                    model: ScriptModel { values: root.rows; objectProp: "key" }

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
                        NumberAnimation { property: "x"; from: 24; to: 0; duration: 380; easing.type: Easing.OutCubic }
                    }
                    remove: Transition {
                        NumberAnimation { property: "opacity"; to: 0; duration: 180 }
                        NumberAnimation { property: "x"; to: 40; duration: 220; easing.type: Easing.InCubic }
                    }
                    displaced: Transition {
                        NumberAnimation { property: "y"; duration: 320; easing.type: Easing.InOutCubic }
                    }

                    delegate: Item {
                        id: item
                        required property var modelData
                        readonly property string type: modelData.type
                        width: list.width
                        height: type === "section" ? 30 : type === "group" ? 36 : row.height + (row.stacked ? 6 : 0)

                    // ── a section heading: Today / Yesterday / Earlier ──
                    Text {
                        visible: item.type === "section"
                        x: 12
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.8
                        color: Theme.subtext
                        text: item.modelData.title ?? ""
                    }

                    // ── an app's group: icon, name, count; click expands, × clears it ──
                    Item {
                        visible: item.type === "group"
                        anchors.fill: parent
                        MouseArea {
                            id: groupArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleGroup(item.modelData.gk)
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: 12
                            color: Qt.alpha(Theme.text, groupArea.containsMouse ? 0.05 : 0)
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        Image {
                            id: gIcon
                            x: 14
                            anchors.verticalCenter: parent.verticalCenter
                            width: 18; height: 18
                            sourceSize: Qt.size(36, 36)
                            source: item.type === "group" ? root.iconOf(item.modelData.first) : ""
                            visible: status === Image.Ready
                            fillMode: Image.PreserveAspectFit
                            mipmap: true
                        }
                        Glyph {
                            x: 15
                            anchors.verticalCenter: parent.verticalCenter
                            visible: gIcon.status !== Image.Ready
                            size: 15
                            path: root.bellIcon
                            tone: Theme.subtext
                        }
                        Row {
                            x: 42
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: Theme.font
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                                color: Theme.text
                                text: item.modelData.app ?? ""
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: countText.implicitWidth + 12
                                height: 18
                                radius: 9
                                color: Qt.alpha(Theme.tone("action"), 0.15)
                                Text {
                                    id: countText
                                    anchors.centerIn: parent
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.features: { "tnum": 1 }
                                    color: Theme.tone("action")
                                    text: item.modelData.count ?? ""
                                }
                            }
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: Theme.font
                                font.pixelSize: 11
                                color: Theme.subtext
                                text: item.modelData.open ? "Show less" : "Show all"
                            }
                            Glyph {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 14
                                path: root.chevronIcon
                                tone: Theme.subtext
                                rotation: item.modelData.open ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                            }
                            Rectangle { // clear the group
                                width: 24; height: 24; radius: 12
                                color: Qt.alpha(Theme.text, gxArea.containsMouse ? 0.14 : 0.07)
                                Glyph { anchors.centerIn: parent; size: 12; path: root.xIcon; tone: Theme.subtext }
                                MouseArea {
                                    id: gxArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { for (const k of item.modelData.keys) Notifs.remove(k); }
                                }
                            }
                        }
                    }

                    // a collapsed group's hidden ones, peeking out under the newest
                    Rectangle {
                        visible: row.stacked
                        x: 14
                        width: parent.width - 28
                        y: row.height - 8
                        height: 14
                        radius: 10
                        color: Qt.alpha(Theme.text, 0.05)
                    }

                    Rectangle {
                        id: row
                        visible: item.type === "notif"
                        readonly property var modelData: item.modelData.e ?? ({})
                        readonly property bool grouped: !!item.modelData.grouped
                        readonly property bool stacked: visible && (item.modelData.more ?? 0) > 0
                        readonly property var actions: (Notifs.live[modelData.key] ? modelData.actions ?? [] : []).filter(a => a.id !== "default" && a.label)
                        width: list.width
                        height: body.implicitHeight + 20
                        radius: 14
                        color: rowArea.containsMouse ? Qt.tint(Theme.frame, Qt.alpha(Theme.text, 0.06)) : row.stacked ? Qt.tint(Theme.frame, Qt.alpha(Theme.text, 0.03)) : "transparent"
                        Behavior on color { ColorAnimation { duration: 150 } }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Notifs.invoke(row.modelData.key, "default");
                                Notifs.remove(row.modelData.key);
                            }
                        }

                        Rectangle { // icon
                            x: 10; y: 12
                            width: 30; height: 30; radius: 15
                            color: Qt.alpha(row.modelData.urgency === NotificationUrgency.Critical ? Theme.tone("error") : Theme.tone("action"), 0.15)
                            readonly property url src: row.visible ? root.iconOf(row.modelData) : ""
                            Image {
                                id: img
                                anchors.centerIn: parent
                                width: 20; height: 20
                                sourceSize: Qt.size(48, 48)
                                source: parent.src
                                visible: status === Image.Ready
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                            }
                            Glyph {
                                anchors.centerIn: parent
                                visible: img.status !== Image.Ready
                                size: 15
                                path: root.bellIcon
                                tone: Theme.tone("action")
                            }
                        }

                        Column {
                            id: body
                            x: 50
                            y: 10
                            width: row.width - 50 - 36
                            spacing: 2
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 11
                                color: Theme.subtext
                                text: row.grouped ? root.ago(row.modelData.time) : (row.modelData.appName || "Notification") + "  ·  " + root.ago(row.modelData.time)
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 13
                                font.weight: Font.Medium
                                color: Theme.text
                                text: row.modelData.summary
                            }
                            Text {
                                width: parent.width
                                visible: text.length > 0
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 12
                                lineHeight: 17
                                lineHeightMode: Text.FixedHeight
                                color: Theme.subtext
                                textFormat: Text.StyledText
                                text: row.modelData.body
                            }
                            Flow {
                                width: parent.width
                                visible: row.actions.length > 0
                                topPadding: 6
                                spacing: 6
                                Repeater {
                                    model: row.actions
                                    delegate: Rectangle {
                                        id: chip
                                        required property var modelData
                                        width: chipLabel.implicitWidth + 18
                                        height: 24
                                        radius: 12
                                        color: Qt.alpha(Theme.tone("action"), chipArea.containsMouse ? 0.25 : 0.15)
                                        Text {
                                            id: chipLabel
                                            anchors.centerIn: parent
                                            font.family: Theme.font
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                            color: Theme.tone("action")
                                            text: chip.modelData.label
                                        }
                                        MouseArea {
                                            id: chipArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                Notifs.invoke(row.modelData.key, chip.modelData.id);
                                                Notifs.remove(row.modelData.key);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // dismiss (shown on hover)
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            y: 10
                            width: 24; height: 24; radius: 12
                            opacity: rowArea.containsMouse || xArea.containsMouse ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                            color: Qt.alpha(Theme.text, xArea.containsMouse ? 0.14 : 0.07)
                            Glyph { anchors.centerIn: parent; size: 12; path: root.xIcon; tone: Theme.subtext }
                            MouseArea {
                                id: xArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Notifs.remove(row.modelData.key)
                            }
                        }
                    }
                    }
                }
            }
        }
    }
}
