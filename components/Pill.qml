import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import qs.config

// A sileo toast: a pill (badge + title) that grows a gooey body with the
// description and buttons. Same geometry, spring, autopilot, hover-to-hold and
// swipe-to-dismiss as sileo. It manages its own life: show it, and it emits
// `finished(reason)` once it has fully animated away.
//
// Its height follows what is visible (pill, body, and how far it has entered), so
// pills placed in a Column push each other around smoothly.
Item {
    id: root

    // ── content (may change while shown: the header morphs) ──
    property string kind: "info"          // success error warning info action loading notify
    property string title: ""
    property string desc: ""              // rich text
    property url iconSource: ""           // custom badge image (app icon, avatar…)
    property string iconGlyph: ""         // or a glyph/emoji
    property var buttons: []              // [{ id, label, tone?, react? }]
    property int duration: 6000           // ms; 0 = stays until dismissed
    property bool sticky: false           // stay expanded until answered
    property bool autopilot: true
    property int expandDelay: 700
    property bool autoExpand: true        // open the body by itself (else only on hover)
    property bool compact: false          // just the badge (until hovered)
    // calm: nothing that changes our height bounces, so neighbours in a stack
    // glide instead of wobbling. The pill itself keeps its spring.
    property bool calm: false

    // ── layout ──
    property string align: "right"       // left | center | right
    // Edge mode: the pill grows out of a wall (the screen frame) on its right,
    // `wallW` px wide, instead of fading in. It slides out of the wall and melts
    // into it on the way back. Our width then includes the wall.
    property bool edge: false
    property real wallW: 0
    property color fill: Theme.fill
    // false: don't draw the shape; a parent draws it from pillRect/bodyRect
    // (so a whole stack can be one merged blob)
    property bool drawShape: true
    readonly property rect pillRect: Qt.rect(toast.pillX + toast.slide, 0, pillW.value + toast.tuck, pillHt.value)
    readonly property rect bodyRect: Qt.rect(toast.slide, pillH, toastW + toast.tuck, Math.max(0, bodyHt.value))
    property real gap: 10                 // space below it when stacked
    readonly property int pillH: 40
    readonly property int toastW: 350
    property int roundness: 16
    readonly property real blur: roundness * 0.5
    readonly property int pillPadding: 10

    // ── signals ──
    signal answered(string id)            // a button was clicked
    signal clicked()                      // the pill/body itself was clicked
    signal finished(string reason)        // gone: dismissed | timeout | <button id> | closed

    // ── state ──
    property bool expanded: false
    property bool hovered: false
    property bool leaving: false
    property bool reacting: false
    property string result: "dismissed"
    readonly property bool hasBody: desc.length > 0 || buttons.length > 0
    readonly property bool open: expanded && hasBody && kind !== "loading" && !leaving && !reacting
    readonly property Item hitItem: hit

    width: toastW + (edge ? wallW : 0)
    height: (pillH + Math.max(0, bodyHt.value) + gap) * (calm ? presence : Math.max(0, Math.min(1, enter.value)))
    // how much room we take in a stack: eases in/out without overshoot
    property real presence: 0
    Behavior on presence { NumberAnimation { duration: 420; easing.type: Easing.InOutCubic } }
    // keep painting beyond our (shrinking) height while leaving
    clip: false

    function tone(k: string): color { return Theme.tone(k); }
    readonly property string circle10: "M22 12a10 10 0 1 1-20 0a10 10 0 1 1 20 0"
    readonly property var icons: ({
        success: "M20 6 9 17l-5-5",
        error: "M18 6 6 18 M6 6l12 12",
        loading: "M21 12a9 9 0 1 1-6.219-8.56",
        warning: circle10 + " M12 8v4 M12 16h.01",
        info: circle10 + " M16 12a4 4 0 1 1-8 0a4 4 0 1 1 8 0"
            + " M4.93 4.93 9.17 9.17 M14.83 9.17 19.07 4.93"
            + " M14.83 14.83 19.07 19.07 M9.17 14.83 4.93 19.07",
        action: "M5 12h14 M12 5l7 7-7 7",
        notify: "M10.268 21a2 2 0 0 0 3.464 0 M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326" // Bell
    })

    // ── lifecycle ──
    Component.onCompleted: { enter.to = 1; presence = 1; schedule(); }

    onAutoExpandChanged: {
        if (autoExpand || leaving || reacting) return;
        expandTimer.stop();
        if (!hovered && !sticky) expanded = false;
    }

    function retract(): void { enter.to = 0; presence = 0; }
    function maybeFinish(): void {
        if (leaving && enter.t >= 1 && enter.target === 0 && (!calm || presence <= 0.001))
            finished(result);
    }
    onPresenceChanged: maybeFinish()

    function schedule(): void {
        expandTimer.stop(); collapseTimer.stop(); dismissTimer.stop();
        if (hasBody && autoExpand && (autopilot || sticky) && kind !== "loading") expandTimer.start();
        if (duration > 0 && !hovered) {
            dismissTimer.interval = duration;
            dismissTimer.start();
            if (autopilot && !sticky && duration - 2000 > expandDelay + Motion.dur) {
                collapseTimer.interval = duration - 2000;
                collapseTimer.start();
            }
        }
    }

    // Restart the timers after the content changed (e.g. a replaced notification).
    function refresh(): void {
        if (leaving || reacting) return;
        expanded = false;
        schedule();
    }

    function dismiss(why: string): void {
        if (leaving) return;
        result = why;
        const wasOpen = open;
        leaving = true;
        expandTimer.stop(); collapseTimer.stop(); dismissTimer.stop();
        if (wasOpen) exitDelay.start(); // fold the body into the pill first
        else retract();
    }

    // A clicked button: report it at once, then (with a reaction like
    // "success:Done") fold the body and morph the pill into it before leaving.
    function answer(id: string, react: string): void {
        if (leaving || reacting) return;
        answered(id);
        if (!react) { dismiss(id); return; }
        result = id;
        reacting = true;
        expandTimer.stop(); collapseTimer.stop(); dismissTimer.stop();
        reactSwap.react = react;
        reactSwap.start();
    }
    Timer {
        id: reactSwap
        property string react: ""
        interval: 460
        onTriggered: {
            const i = react.indexOf(":");
            root.kind = i > 0 ? react.slice(0, i) : "success";
            root.title = i > 0 ? react.slice(i + 1) : react;
            reactHold.start();
        }
    }
    Timer { id: reactHold; interval: 1300; onTriggered: { root.leaving = true; root.retract(); } }

    Timer { id: expandTimer; interval: root.expandDelay; onTriggered: root.expanded = true }
    Timer { id: collapseTimer; onTriggered: root.expanded = false }
    Timer { id: dismissTimer; onTriggered: root.dismiss("timeout") }
    Timer { id: exitDelay; interval: 480; onTriggered: root.retract() }

    onHoveredChanged: {
        if (leaving || reacting) return;
        if (hovered) {
            collapseTimer.stop(); dismissTimer.stop(); expandTimer.stop();
            if (hasBody && kind !== "loading") expanded = true;
        } else {
            if (!sticky) expanded = false;
            if (duration > 0) { dismissTimer.interval = duration; dismissTimer.start(); }
        }
    }

    Spring { id: enter; to: 0; duration: Motion.dur * 0.66 }
    Connections {
        target: enter
        function onTChanged() {
            root.maybeFinish();
        }
    }

    // ── visuals ──
    Item {
        id: toast
        width: root.toastW
        height: root.pillH + Math.max(0, bodyHt.value)
        y: root.edge ? 0 : -6 * (1 - Math.min(enter.value, 1))
        opacity: root.edge ? 1 : Math.max(0, Math.min(1, enter.value))
        scale: root.edge ? 1 : 0.95 + 0.05 * enter.value
        transformOrigin: Item.Top

        // edge mode: how far the shape is pushed back into the wall
        readonly property real slide: root.edge ? (1 - enter.value) * (root.toastW + root.roundness) + Math.max(-12, swipeX) : 0
        readonly property real textIn: Math.max(0, Math.min(1, enter.value * 1.6 - 0.6))
        // under the wall the pill's right side is hidden, so it extends into it
        readonly property real tuck: root.edge ? root.roundness + root.wallW : 0

        readonly property real contentH: content.implicitHeight
        readonly property real expandedH: Math.max(root.pillH * 2.25, root.pillH + contentH)
        Spring { id: pillW; to: root.compact && !root.hovered ? root.pillH : Math.min(root.toastW, Math.max(root.pillH, headerCurrent.implicitWidth + 16 + root.pillPadding)) }
        Spring { id: pillHt; to: root.open ? root.pillH + root.blur * 3 : root.pillH }
        Spring { id: bodyHt; to: root.open ? toast.expandedH - root.pillH : 0; settleWhenShrinking: true; bounce: !root.calm }
        Spring { id: headerLift; to: root.open ? 1 : 0 }
        readonly property real pillX: root.align === "left" ? 0
            : root.align === "right" ? root.toastW - pillW.value
            : (root.toastW - pillW.value) / 2

        // the gooey shape: pill and body melted together (SDF smooth-min)
        readonly property real pad: root.blur * 2
        ShaderEffect {
            visible: root.drawShape
            x: -toast.pad; y: -toast.pad
            width: toast.width + (root.edge ? root.wallW : 0) + toast.pad * 2
            height: toast.expandedH + root.blur * 4 + toast.pad * 2
            fragmentShader: Qt.resolvedUrl("../shaders/goo.frag.qsb")
            property size size: Qt.size(width, height)
            property vector4d pill: Qt.vector4d(toast.pad + toast.pillX + toast.slide, toast.pad, pillW.value + toast.tuck, pillHt.value)
            property vector4d body: Qt.vector4d(toast.pad + toast.slide, toast.pad + root.pillH, root.toastW + toast.tuck, Math.max(0, bodyHt.value))
            property vector4d wall: root.edge ? Qt.vector4d(toast.pad + root.toastW, 0, root.wallW, height) : Qt.vector4d(0, 0, 0, 0)
            property real radius: root.roundness
            property real goo: root.blur * 2.5
            property color fill: root.fill
            property color shadow: "transparent"
        }

        // input region, hover, click and swipe
        Item {
            id: hit
            x: (root.open ? 0 : toast.pillX) + toast.slide
            width: (root.open ? root.toastW : pillW.value) + (root.edge ? root.wallW : 0)
            height: root.pillH + Math.max(0, bodyHt.value)
            HoverHandler { onHoveredChanged: root.hovered = hovered }
            TapHandler { onTapped: root.clicked() }
            DragHandler {
                id: drag
                target: null
                property real dx: 0
                onActiveTranslationChanged: { dx = activeTranslation.x; toast.swipeX = root.edge ? Math.max(-12, dx) : Math.max(-24, Math.min(24, dx)); }
                onActiveChanged: if (!active) {
                    if (root.edge ? dx > 40 : Math.abs(dx) > 30) root.dismiss("dismissed");
                    toast.swipeX = 0;
                    dx = 0;
                }
            }
        }
        property real swipeX: 0
        Behavior on swipeX { enabled: !drag.active; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        transform: Translate { x: root.edge ? 0 : toast.swipeX }

        // header: badge + title, cross-fading with blur on change
        component HeaderInner: Row {
            id: hi
            property string kind: "info"
            property string label: ""
            spacing: 8
            height: root.pillH - 16

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 24; radius: 12
                color: Qt.alpha(root.tone(hi.kind), 0.2)
                readonly property bool hasImage: root.iconSource.toString() !== "" && hi.kind !== "loading" && img.status !== Image.Error
                readonly property bool hasGlyph: !hasImage && root.iconGlyph !== "" && hi.kind !== "loading"
                Shape {
                    id: glyph
                    visible: !parent.hasImage && !parent.hasGlyph
                    anchors.centerIn: parent
                    width: 16; height: 16
                    preferredRendererType: Shape.CurveRenderer
                    RotationAnimation on rotation {
                        running: hi.kind === "loading"
                        loops: Animation.Infinite
                        from: 0; to: 360; duration: 1000
                        onRunningChanged: if (!running) glyph.rotation = 0
                    }
                    ShapePath {
                        strokeColor: root.tone(hi.kind)
                        strokeWidth: 2
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        scale: Qt.size(16 / 24, 16 / 24)
                        PathSvg { path: root.icons[hi.kind] || root.icons.info }
                    }
                }
                Image {
                    id: img
                    visible: parent.hasImage
                    anchors.centerIn: parent
                    width: 18; height: 18
                    sourceSize: Qt.size(48, 48)
                    source: root.iconSource
                    fillMode: Image.PreserveAspectFit
                    asynchronous: false
                    smooth: true
                    mipmap: true
                }
                Text {
                    visible: parent.hasGlyph
                    anchors.centerIn: parent
                    font.pixelSize: 13
                    color: root.tone(hi.kind)
                    text: root.iconGlyph
                }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, root.toastW - 24 - 8 - 16 - root.pillPadding)
                elide: Text.ElideRight
                font.family: Theme.font
                font.pointSize: 13.2 * 0.75
                font.weight: Font.Medium
                color: root.tone(hi.kind)
                text: hi.label
            }
        }

        Item {
            id: header
            x: toast.pillX + 8 + toast.slide
            opacity: root.edge ? toast.textIn : 1
            y: 8 + 3 * headerLift.value
            width: Math.max(0, pillW.value - 16)
            height: root.pillH - 16
            clip: true
            scale: 1 - 0.1 * headerLift.value

            HeaderInner {
                id: headerPrev
                opacity: 0
                layer.enabled: opacity > 0
                layer.effect: MultiEffect { blurEnabled: true; blur: prevBlur.value; blurMax: 12 }
                QtObject { id: prevBlur; property real value: 0 }
            }
            HeaderInner {
                id: headerCurrent
                kind: root.kind
                label: root.title
                layer.enabled: curBlur.value > 0.01
                layer.effect: MultiEffect { blurEnabled: true; blur: curBlur.value; blurMax: 12 }
                QtObject { id: curBlur; property real value: 0.5 }
                Component.onCompleted: headerIn.restart()
            }

            property string lastKind: root.kind
            property string lastLabel: root.title
            Connections {
                target: root
                function onTitleChanged() { header.swap(); }
                function onKindChanged() { header.swap(); }
            }
            function swap(): void {
                if (lastKind === root.kind && lastLabel === root.title) return;
                headerPrev.kind = lastKind;
                headerPrev.label = lastLabel;
                lastKind = root.kind;
                lastLabel = root.title;
                headerOut.restart();
                headerIn.restart();
            }
            ParallelAnimation {
                id: headerOut
                NumberAnimation { target: headerPrev; property: "opacity"; from: 1; to: 0; duration: Motion.dur * 0.7; easing.type: Easing.InOutQuad }
                NumberAnimation { target: prevBlur; property: "value"; from: 0; to: 0.5; duration: Motion.dur * 0.7; easing.type: Easing.InOutQuad }
            }
            ParallelAnimation {
                id: headerIn
                NumberAnimation { target: headerCurrent; property: "opacity"; from: 0; to: 1; duration: Motion.dur; easing.type: Easing.OutCubic }
                NumberAnimation { target: curBlur; property: "value"; from: 0.5; to: 0; duration: Motion.dur; easing.type: Easing.OutCubic }
            }
        }

        // body: description + buttons
        Column {
            id: content
            x: toast.slide
            y: root.pillH
            width: root.toastW
            padding: 16
            spacing: 12
            enabled: root.open
            opacity: 0
            Connections {
                target: root
                function onOpenChanged() {
                    contentFade.stop();
                    contentPause.duration = root.open ? Motion.dur * 0.3 : Motion.dur * 0.04;
                    contentOpacity.duration = root.open ? Motion.dur * 0.6 : Motion.dur * 0.08;
                    contentOpacity.to = root.open ? 1 : 0;
                    contentFade.start();
                }
            }
            SequentialAnimation {
                id: contentFade
                PauseAnimation { id: contentPause }
                NumberAnimation { id: contentOpacity; target: content; property: "opacity"; easing.type: Easing.InOutQuad }
            }

            Text {
                visible: root.desc.length > 0
                width: root.toastW - 32
                wrapMode: Text.Wrap
                maximumLineCount: 8
                elide: Text.ElideRight
                font.family: Theme.font
                font.pixelSize: 14
                lineHeight: 20
                lineHeightMode: Text.FixedHeight
                color: Theme.subtext
                linkColor: Theme.tone("action")
                textFormat: Text.StyledText
                text: root.desc
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            Flow {
                visible: root.buttons.length > 0
                width: root.toastW - 32
                spacing: 8
                Repeater {
                    model: root.buttons
                    delegate: Rectangle {
                        id: btn
                        required property var modelData
                        required property int index
                        readonly property color tone: modelData.tone || (index === 0 ? Theme.tone("action") : Theme.neutral)
                        width: lbl.implicitWidth + 20
                        height: 28
                        radius: 14
                        color: Qt.alpha(tone, ma.containsMouse ? 0.25 : 0.15)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Text {
                            id: lbl
                            anchors.centerIn: parent
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: btn.tone
                            text: btn.modelData.label
                        }
                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.answer(btn.modelData.id, btn.modelData.react || "")
                        }
                    }
                }
            }
        }
    }
}
