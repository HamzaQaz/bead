pragma Singleton

import QtQuick
import Quickshell

// The island's resting size (Island.qml keeps it current), for things that
// have to land exactly on it: the welcome intro's bead.
Singleton {
    property real restW: 160
    property bool tucked: false   // tucked into the frame (a window's near the top)
    readonly property real restH: 34
}
