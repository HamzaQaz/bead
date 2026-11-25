pragma Singleton

import QtQuick
import Quickshell

// The island's resting size (Island.qml keeps it current), for things that
// have to land exactly on it: the welcome intro's bead.
Singleton {
    property real restW: 160
    property bool tucked: false   // tucked into the frame (a window's near the top)
    readonly property real restH: 34
    // what it's doing now, and its size (the target, not mid-spring): Settings'
    // Customise previews crop the live screen to it
    property string state: "rest"
    // a Customise preview of it is open in Settings: it doesn't tuck under windows meanwhile
    readonly property bool previewing: SettingsApp.open && SettingsApp.query.trim() === "" && ["island", "motion", "look"].includes(SettingsApp.page)
    property real w: 160
    property real h: 34
}
