pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Wayland
import qs.components
import qs.config

// The desktop notification server (org.freedesktop.Notifications), shown as a
// stack of sileo pills that grow out of the right edge of Caelestia's screen
// frame, top-right of the focused monitor.
//
// Only one server can own the name. If another (Caelestia) holds it, Quickshell
// waits and takes over as soon as it is released, and the other does the same
// for us, so whichever started first wins and the other is the fallback.
Scope {
    id: root

    // Popups on screen, newest first. Each entry is a plain snapshot, so a pill
    // can finish animating after its notification object is gone.
    property list<var> popups: []
    property int serial: 0

    function snapshot(n: Notification): var {
        return {
            key: ++serial,
            notif: n,
            id: n.id,
            appName: n.appName,
            summary: n.summary,
            body: n.body,
            image: n.image,
            appIcon: n.appIcon,
            urgency: n.urgency,
            timeout: n.expireTimeout,
            actions: n.actions.map(a => ({ id: a.identifier, label: a.text }))
        };
    }

    // at most `maxShown` on screen: the oldest ones expire
    readonly property int maxShown: 4
    function trim(): void {
        for (const c of stack.children)
            if (c.pillRect !== undefined && c.index >= maxShown) c.dismiss("timeout");
    }

    function remove(key: int): void {
        popups = popups.filter(p => p.key !== key);
    }

    NotificationServer {
        id: server
        keepOnReload: true // live reloads keep the D-Bus name
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: false
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            if (root.popups.length === 0) win.held = win.focused; // stay put while shown
            root.popups = [root.snapshot(n), ...root.popups];
            Qt.callLater(root.trim);
        }
    }

    PanelWindow {
        id: win

        // the focused monitor when the first popup arrives; the stack stays there
        readonly property ShellScreen focused: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        property ShellScreen held: focused
        screen: held
        visible: root.popups.length > 0
        anchors.top: true
        anchors.right: true
        // the frame strip, in logical px (QT_SCALE_FACTOR applies)
        readonly property real wallW: Theme.frameThickness / devicePixelRatio
        implicitWidth: 350 + 40 + wallW
        implicitHeight: screen?.height ?? 800
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore // the real corner, over the frame
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "bead-notifications"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // clicks only land on the pills themselves
        mask: Region {
            regions: stack.children.filter(c => c.hitRegion).map(c => c.hitRegion)
        }

        // One shape for everything: Caelestia's frame (top + right edges and its
        // rounded inner corner, redrawn in the same colour) melted together
        // with every pill, so the stack is a single blob growing out of the corner.
        ShaderEffect {
            id: blob
            anchors.fill: parent
            fragmentShader: Qt.resolvedUrl("../../shaders/stack.frag.qsb")
            readonly property var shapes: stack.children.filter(c => c.pillRect !== undefined)
            function pr(i: int): vector4d {
                const c = shapes[i];
                if (!c) return Qt.vector4d(0, 0, 0, 0);
                const r = c.pillRect;
                return Qt.vector4d(stack.x + c.x + r.x, stack.y + c.y + r.y, r.width, r.height);
            }
            function br(i: int): vector4d {
                const c = shapes[i];
                if (!c) return Qt.vector4d(0, 0, 0, 0);
                const r = c.bodyRect;
                return Qt.vector4d(stack.x + c.x + r.x, stack.y + c.y + r.y, r.width, r.height);
            }
            property size size: Qt.size(width, height)
            property vector4d inner: Qt.vector4d(-2000, win.wallW, width - win.wallW + 2000, height + 2000)
            property real innerRadius: 20 / win.devicePixelRatio
            property real radius: 16
            property real goo: 20
            property color fill: Theme.frame
            property vector4d p0: pr(0); property vector4d p1: pr(1); property vector4d p2: pr(2); property vector4d p3: pr(3)
            property vector4d p4: pr(4); property vector4d p5: pr(5); property vector4d p6: pr(6); property vector4d p7: pr(7)
            property vector4d b0: br(0); property vector4d b1: br(1); property vector4d b2: br(2); property vector4d b3: br(3)
            property vector4d b4: br(4); property vector4d b5: br(5); property vector4d b6: br(6); property vector4d b7: br(7)
        }

        Column {
            id: stack
            x: win.width - width
            y: win.wallW + 6 // close enough to melt into the top edge
            width: 350 + win.wallW

            Repeater {
                model: ScriptModel {
                    values: root.popups
                    objectProp: "key"
                }

                delegate: Pill {
                    id: pill

                    required property var modelData
                    required property int index
                    readonly property Notification notif: modelData.notif
                    property Region hitRegion: Region { item: pill.hitItem }

                    kind: modelData.urgency === NotificationUrgency.Critical ? "error" : "notify"
                    title: modelData.summary || modelData.appName || "Notification"
                    desc: modelData.body
                    iconSource: modelData.image ? modelData.image
                        : modelData.appIcon ? Quickshell.iconPath(modelData.appIcon, true) : ""
                    buttons: modelData.actions.filter(a => a.id !== "default" && a.label)
                    duration: modelData.urgency === NotificationUrgency.Critical ? 0
                        : modelData.timeout > 0 ? modelData.timeout : 6000
                    sticky: modelData.urgency === NotificationUrgency.Critical
                    align: "right"
                    edge: true
                    drawShape: false // the blob above draws it
                    gap: 6           // close enough to melt into each other
                    calm: true
                    autoExpand: index === 0 // only the newest opens by itself
                    compact: index > 0      // older ones are just their icon
                    wallW: win.wallW
                    fill: Theme.frame

                    // a replaced notification (same id, new content) updates in place
                    Connections {
                        target: pill.notif
                        ignoreUnknownSignals: true
                        function onSummaryChanged() { pill.resync(); }
                        function onBodyChanged() { pill.resync(); }
                        function onImageChanged() { pill.resync(); }
                        function onClosed() { pill.dismiss("closed"); }
                    }
                    function resync(): void {
                        if (!notif) return;
                        title = notif.summary || notif.appName || "Notification";
                        desc = notif.body;
                        refresh();
                    }

                    onClicked: {
                        const def = notif?.actions.find(a => a.identifier === "default");
                        if (def) def.invoke();
                        dismiss("dismissed");
                    }
                    onAnswered: id => notif?.actions.find(a => a.identifier === id)?.invoke()
                    onFinished: reason => {
                        if (notif) {
                            if (reason === "timeout") notif.expire();
                            else if (reason !== "closed") notif.dismiss();
                        }
                        root.remove(modelData.key);
                    }
                }
            }
        }
    }
}
