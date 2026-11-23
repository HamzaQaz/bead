import QtQuick

// A bar panel's body. Rows that appear (a Wi-Fi network in range, a device
// connecting) grow in with a little spring; the rows around them glide to
// their new places instead of jumping.
Column {
    add: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.9; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
        }
    }
    move: Transition {
        NumberAnimation { properties: "y"; duration: 320; easing.type: Easing.OutCubic }
        // a row that was mid-way through growing in finishes it
        NumberAnimation { property: "opacity"; to: 1; duration: 200 }
        NumberAnimation { property: "scale"; to: 1; duration: 260; easing.type: Easing.OutCubic }
    }
}
