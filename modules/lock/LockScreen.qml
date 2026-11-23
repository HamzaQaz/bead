pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.services

// The session lock: a LockContent on every screen while locked. In preview
// mode the same content shows in ordinary overlay windows (no lock).
Scope {
    WlSessionLock {
        locked: Lock.locked
        WlSessionLockSurface {
            id: surface
            color: "black"
            LockContent { anchors.fill: parent; screen: surface.screen }
        }
    }

    Variants {
        model: Lock.preview && !Lock.locked ? Quickshell.screens : []
        PanelWindow {
            id: pw
            required property ShellScreen modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "black"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "bead-lock-preview"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            LockContent { anchors.fill: parent; screen: pw.modelData }
        }
    }

    // capture the screen once at startup: the first capture is set up
    // asynchronously, and while locked the compositor refuses to start one
    Loader {
        active: true
        asynchronous: true
        onLoaded: active = false
        sourceComponent: ScreencopyView { captureSource: Quickshell.screens[0] }
    }
}
