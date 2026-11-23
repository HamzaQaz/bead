import QtQuick

// Steps through glyph names while running (e.g. Wi-Fi bars filling up while
// connecting); `current` is the frame to show, the last one when stopped.
Item {
    id: sweep
    property list<string> frames: []
    property bool running: false
    property int interval: 260
    property int i: 0
    readonly property string current: frames.length ? frames[running ? i % frames.length : frames.length - 1] : ""
    Timer {
        interval: sweep.interval
        repeat: true
        running: sweep.running
        onTriggered: sweep.i++
        onRunningChanged: sweep.i = 0
    }
}
