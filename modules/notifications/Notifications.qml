pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Wayland
import qs.components
import qs.config

// The desktop notification server (org.freedesktop.Notifications), shown as a
// stack of sileo pills in the top-right corner of the focused monitor.
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

    function remove(key: int): void {
        popups = popups.filter(p => p.key !== key);
    }

    NotificationServer {
        id: server
        keepOnReload: false
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: false
        imageSupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            root.popups = [root.snapshot(n), ...root.popups];
        }
    }

    PanelWindow {
        id: win

        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        visible: root.popups.length > 0
        anchors.top: true
        anchors.right: true
        margins.top: 28
        margins.right: 4
        implicitWidth: 350 + 24
        implicitHeight: Math.min(screen?.height ?? 1080, 1000)
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "bead-notifications"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // clicks only land on the pills themselves
        mask: Region {
            regions: stack.children.filter(c => c.hitRegion).map(c => c.hitRegion)
        }

        Column {
            id: stack
            x: 12
            y: 6
            width: 350

            Repeater {
                model: ScriptModel {
                    values: root.popups
                    objectProp: "key"
                }

                delegate: Pill {
                    id: pill

                    required property var modelData
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
