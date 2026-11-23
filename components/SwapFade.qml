import QtQuick

// The island's content swaps: the outgoing row fades out quickly and the
// incoming one waits for it, so two rows never draw over each other.
//   SwapFade on opacity {}
Behavior {
    id: b
    SequentialAnimation {
        PauseAnimation { duration: b.targetValue > 0.5 ? 110 : 0 }
        NumberAnimation { duration: b.targetValue > 0.5 ? 200 : 110; easing.type: Easing.OutCubic }
    }
}
