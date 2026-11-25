import QtQuick
import qs.config

// Text that changes with a small roll: the old words lift and fade as the new
// ones rise in, and the width eases so whatever's beside it slides instead
// of jumping. For values that change while you're looking (a clock, a
// widget's reading, on/off). With motion off, or while hidden, it just swaps.
//   RollText { text: …; color: …; font.pixelSize: Theme.body }
Item {
    id: r

    property string text: ""
    property color color: Theme.text
    property alias font: a.font
    property int textFormat: Text.PlainText
    property real maxWidth: Infinity     // past this it elides
    property real rise: 6                // how far the words travel (px)
    // ease the width as the words change. Off inside something that already
    // springs to fit its content (the island): a width that moves every frame
    // keeps restarting that spring, so it lags behind and clips
    property bool easeWidth: true

    readonly property Text cur: front ? a : b
    property bool front: true

    // a reading turning good or bad eases into its colour
    Behavior on color { enabled: Motion.on; ColorAnimation { duration: Motion.ms(320); easing.type: Easing.OutCubic } }

    implicitWidth: Math.min(maxWidth, cur.implicitWidth)
    implicitHeight: a.implicitHeight
    Behavior on implicitWidth { enabled: Motion.on && r.ready && r.easeWidth; NumberAnimation { duration: Motion.ms(240); easing.type: Easing.OutCubic } }

    property bool ready: false
    // the first text is bound so the size is right from the first frame (a row
    // takes a zero-size item for a new arrival and pops it in); after that the
    // binding is dropped and the roll sets each layer itself
    // figures all one width, so a changing number doesn't jiggle
    Component.onCompleted: { a.font.features = { "tnum": 1 }; a.text = text; ready = true; }

    onTextChanged: {
        if (!ready) return;
        if (!Motion.on || !visible || opacity < 0.05) { roll.stop(); cur.text = text; cur.y = 0; cur.opacity = 1; other().opacity = 0; return; }
        if (text === cur.text) return;
        roll.stop();
        const out = cur, inn = other();
        inn.text = text;
        front = !front;
        outY.target = outOp.target = out;
        inY.target = inOp.target = inn;
        outY.from = out.y; outOp.from = out.opacity;
        roll.start();
    }
    function other(): Text { return front ? b : a; }

    Text {
        id: a
        text: r.text
        width: Math.min(r.maxWidth, implicitWidth)
        elide: Text.ElideRight
        color: r.color
        textFormat: r.textFormat
    }
    Text {
        id: b
        width: Math.min(r.maxWidth, implicitWidth)
        elide: Text.ElideRight
        opacity: 0
        color: r.color
        font: a.font
        textFormat: r.textFormat
    }

    ParallelAnimation {
        id: roll
        NumberAnimation { id: outY; property: "y"; to: -r.rise; duration: Motion.ms(160); easing.type: Easing.InCubic }
        NumberAnimation { id: outOp; property: "opacity"; to: 0; duration: Motion.ms(130); easing.type: Easing.OutQuad }
        SequentialAnimation {
            PauseAnimation { duration: Motion.ms(50) }
            ParallelAnimation {
                NumberAnimation { id: inY; property: "y"; from: r.rise; to: 0; duration: Motion.ms(240); easing.type: Easing.OutCubic }
                NumberAnimation { id: inOp; property: "opacity"; from: 0; to: 1; duration: Motion.ms(200); easing.type: Easing.OutQuad }
            }
        }
    }
}
