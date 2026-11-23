// toast: a desktop notification in the style of sileo (https://sileo.aaryan.design).
// QML port of sileo v0.1.6: same geometry, colours, Lucide icons, spring curve,
// gooey morph, autopilot expand/collapse, hover-to-hold and swipe-to-dismiss.
//
// Launched per toast by the `toast` CLI, configured through TOAST_* variables:
//   TOAST_TYPE      success | error | warning | info | action | loading | confirm | choose
//   TOAST_TITLE     pill text
//   TOAST_DESC      body text (optional; the toast only expands when it has one)
//   TOAST_POSITION  top-left | top-center | top-right | bottom-left | bottom-center | bottom-right
//   TOAST_DURATION  ms before it dismisses itself; 0 = stays until dismissed
//   TOAST_BUTTON    action/confirm primary button label
//   TOAST_NO        confirm secondary button label
//   TOAST_CHOICES   choose: button labels separated by newlines
//   TOAST_GRAB=1    take keyboard focus on show (otherwise only after a click)
//   TOAST_REACT     per-button reaction, newline-separated and in button order, as
//                   "type:Title" (e.g. "success:Allowed"). After that button is clicked
//                   the result is printed at once, the body folds up and the pill
//                   morphs into the reaction before leaving.
//   TOAST_ICON      custom badge icon: an image path, or a glyph/emoji
//   TOAST_FILL / TOAST_ROUNDNESS / TOAST_AUTOPILOT=0 / TOAST_EXPAND_DELAY
//   TOAST_THEME     caelestia (default: colours follow the wallpaper scheme) | sileo
//   TOAST_STATE     JSON file watched for updates (promise toasts)
// Prints TOAST_RESULT:<button|no|dismissed|timeout> when it closes.

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    function env(k: string, d: string): string { return Quickshell.env(k) || d; }

    // ── options ──
    readonly property string position: env("TOAST_POSITION", "top-center")
    readonly property bool bottom: position.startsWith("bottom")
    readonly property string align: position.endsWith("left") ? "left" : position.endsWith("right") ? "right" : "center"
    readonly property string buttonLabel: env("TOAST_BUTTON", "")
    readonly property string noLabel: env("TOAST_NO", "Cancel")
    readonly property string icon: env("TOAST_ICON", "")
    readonly property bool iconIsImage: icon.startsWith("/") || /\.(svg|png|jpe?g|webp)$/i.test(icon)
    readonly property bool autopilot: env("TOAST_AUTOPILOT", "1") !== "0"
    readonly property int expandDelay: parseInt(env("TOAST_EXPAND_DELAY", "700"))
    readonly property string stateFile: env("TOAST_STATE", "")
    readonly property var choices: env("TOAST_CHOICES", "").split("\n").filter(c => c.length > 0)
    readonly property bool grab: env("TOAST_GRAB", "") === "1"
    readonly property var reacts: env("TOAST_REACT", "").split("\n")

    // ── content (mutable: promise toasts update it) ──
    property string st: env("TOAST_TYPE", "success")
    property string titleText: env("TOAST_TITLE", st)
    property string desc: env("TOAST_DESC", "")
    property int duration: parseInt(env("TOAST_DURATION", "6000"))
    readonly property bool hasDesc: desc.length > 0 || buttons.length > 0
    readonly property bool sticky: st === "confirm" || st === "choose" // questions stay open until answered
    readonly property var buttons: st === "choose" ? choices.map((c, i) => ({ id: "choice:" + i, label: c, tone: tones.action, react: reacts[i] || "" }))
        : st === "confirm" ? [{ id: "button", label: buttonLabel || "Confirm", tone: tones.action, react: reacts[0] || "" },
                              { id: "no", label: noLabel, tone: c("outline", "#a3a3a3"), react: reacts[1] || "" }]
        : st === "action" && buttonLabel ? [{ id: "button", label: buttonLabel, tone: tones.action, react: reacts[0] || "" }]
        : []

    // ── sileo constants ──
    readonly property int pillH: 40
    readonly property int toastW: 350
    readonly property int roundness: parseInt(env("TOAST_ROUNDNESS", "16"))
    readonly property real blur: roundness * 0.5
    readonly property int pillPadding: 10
    readonly property int dur: 600
    // ── theme: the Caelestia scheme (generated from the wallpaper), live-reloaded ──
    readonly property bool themed: env("TOAST_THEME", "caelestia") !== "sileo"
    property var scheme: ({})
    function c(key: string, fallback: string): color {
        return themed && scheme[key] ? "#" + scheme[key] : fallback;
    }
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/caelestia/scheme.json"
        blockLoading: true // colours ready before the first frame
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.scheme = JSON.parse(text()).colours || {}; } catch (e) {} }
    }
    readonly property color fill: env("TOAST_FILL", "") || c("surfaceContainer", "#1a1a1a")
    readonly property color descColor: themed && scheme.onSurfaceVariant ? Qt.alpha(c("onSurfaceVariant", "#ffffff"), 0.8) : Qt.rgba(1, 1, 1, 0.5)
    readonly property string font: "Noto Sans"
    // --sileo-state-* (oklch values from sileo, converted to sRGB)
    // sileo's tones, or the scheme's matching roles
    readonly property var tones: ({
        success: c("success", "#3ac530"), loading: c("outline", "#737373"), error: c("error", "#fb2c36"),
        warning: c("term2", "#f0b100"), info: c("tertiary", "#00a6f4"),
        action: c("primary", "#2b7fff"), confirm: c("primary", "#2b7fff"), choose: c("primary", "#2b7fff")
    })
    // Lucide icons as bundled in sileo (24x24 viewBox)
    readonly property string circle10: "M22 12a10 10 0 1 1-20 0a10 10 0 1 1 20 0"
    readonly property var icons: ({
        success: "M20 6 9 17l-5-5",
        error: "M18 6 6 18 M6 6l12 12",
        loading: "M21 12a9 9 0 1 1-6.219-8.56",
        warning: circle10 + " M12 8v4 M12 16h.01",                         // CircleAlert
        info: circle10 + " M16 12a4 4 0 1 1-8 0a4 4 0 1 1 8 0"
            + " M4.93 4.93 9.17 9.17 M14.83 9.17 19.07 4.93"
            + " M14.83 14.83 19.07 19.07 M9.17 14.83 4.93 19.07",          // LifeBuoy
        action: "M5 12h14 M12 5l7 7-7 7",                                   // ArrowRight
        confirm: "M5 12h14 M12 5l7 7-7 7",
        choose: circle10 + " M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3 M12 17h.01" // CircleHelp
    })
    function tone(s: string): color { return tones[s] || tones.success; }

    // sileo's --sileo-spring-easing (CSS linear() sampling of its spring)
    readonly property var curve: [
        [0, 0], [0.006, 0.002], [0.012, 0.007], [0.018, 0.015], [0.024, 0.026], [0.031, 0.041],
        [0.038, 0.06], [0.053, 0.108], [0.066, 0.157], [0.08, 0.214], [0.137, 0.467], [0.163, 0.577],
        [0.177, 0.631], [0.191, 0.682], [0.205, 0.73], [0.218, 0.771], [0.231, 0.808], [0.245, 0.844],
        [0.258, 0.874], [0.272, 0.903], [0.286, 0.928], [0.301, 0.952], [0.316, 0.972], [0.331, 0.988],
        [0.357, 1.01], [0.385, 1.025], [0.416, 1.034], [0.45, 1.038], [0.501, 1.035], [0.642, 1.012],
        [0.73, 1.003], [0.837, 0.999], [1, 1]
    ]
    function springEase(t: real): real {
        if (t <= 0) return 0;
        if (t >= 1) return 1;
        for (let i = 1; i < curve.length; i++) {
            const p1 = curve[i];
            if (t <= p1[0]) {
                const p0 = curve[i - 1];
                return p0[1] + (p1[1] - p0[1]) * (t - p0[0]) / (p1[0] - p0[0]);
            }
        }
        return 1;
    }
    function settleEase(t: real): real { // bounce-free spring, used when the body closes
        if (t >= 1) return 1;
        const w = 7.5, e = x => 1 - (1 + w * x) * Math.exp(-w * x);
        return e(t) / e(1);
    }

    component Spring: QtObject {
        id: s
        property real to: 0
        property int duration: root.dur
        property bool settleWhenShrinking: false
        property real start: 0
        property real target: 0
        property bool bouncy: true
        property real t: 1
        readonly property real value: start + (target - start) * (bouncy ? root.springEase(t) : root.settleEase(t))
        Component.onCompleted: { start = to; target = to; }
        onToChanged: {
            const v = value;
            bouncy = !(settleWhenShrinking && to < v);
            start = v;
            target = to;
            anim.restart();
        }
        property NumberAnimation anim: NumberAnimation { target: s; property: "t"; from: 0; to: 1; duration: s.duration }
    }

    // ── lifecycle ──
    property bool expanded: false
    property bool hovered: false
    property bool leaving: false
    property bool started: false
    property string result: "dismissed"
    property bool printed: false   // result already reported (reactions report on click)
    property bool reacting: false
    property string reaction: ""
    readonly property bool open: expanded && hasDesc && st !== "loading" && !leaving && !reacting

    function begin(): void {
        if (started) return;
        started = true;
        enter.to = 1;
        schedule();
    }

    // sileo autopilot: expand shortly after showing, collapse 2s before dismissing.
    function schedule(): void {
        expandTimer.stop(); collapseTimer.stop(); dismissTimer.stop();
        if (hasDesc && (autopilot || sticky) && st !== "loading") expandTimer.start();
        if (duration > 0 && !hovered) {
            dismissTimer.interval = duration;
            dismissTimer.start();
            if (autopilot && !sticky && duration - 2000 > expandDelay + root.dur) {
                collapseTimer.interval = duration - 2000;
                collapseTimer.start();
            }
        }
    }

    function dismiss(why: string): void {
        if (leaving) return;
        result = why;
        const wasOpen = open;
        leaving = true;
        expandTimer.stop(); collapseTimer.stop(); dismissTimer.stop();
        if (wasOpen) exitDelay.start(); // let the body fold into the pill first
        else enter.to = 0;
    }

    // A clicked button: report at once, then fold the body and morph the pill into
    // the reaction ("success:Allowed") before leaving. No reaction = plain dismiss.
    function answer(id: string, react: string): void {
        if (leaving || reacting) return;
        if (!react) { dismiss(id); return; }
        result = id;
        console.log("TOAST_RESULT:" + id);
        printed = true;
        reaction = react;
        reacting = true;
        expandTimer.stop(); collapseTimer.stop(); dismissTimer.stop();
        reactSwap.start();
    }
    Timer { // after the body has folded into the pill
        id: reactSwap; interval: 460
        onTriggered: {
            const i = root.reaction.indexOf(":");
            root.st = i > 0 ? root.reaction.slice(0, i) : "success";
            root.titleText = i > 0 ? root.reaction.slice(i + 1) : root.reaction;
            reactHold.start();
        }
    }
    Timer { id: reactHold; interval: 1300; onTriggered: { root.leaving = true; enter.to = 0; } }

    function applyState(text: string): void {
        if (!text || !text.trim()) return;
        let s;
        try { s = JSON.parse(text); } catch (e) { return; }
        if (s.type) st = s.type;
        if (s.title !== undefined) titleText = s.title;
        if (s.desc !== undefined) desc = s.desc;
        if (s.duration !== undefined) duration = s.duration;
        console.log("TOAST_ACK");
        expanded = false;
        if (started) schedule();
    }

    Timer { id: expandTimer; interval: root.expandDelay; onTriggered: root.expanded = true }
    Timer { id: collapseTimer; onTriggered: root.expanded = false }
    Timer { id: dismissTimer; onTriggered: root.dismiss("timeout") }
    Timer { id: exitDelay; interval: 480; onTriggered: enter.to = 0 }
    Timer { interval: 400; running: true; onTriggered: root.begin() } // fallback if the visibility signal is missed

    // Hover holds the toast (and opens it), like sileo; leaving restarts the timers.
    onHoveredChanged: {
        if (leaving || reacting) return;
        if (hovered) {
            collapseTimer.stop(); dismissTimer.stop(); expandTimer.stop();
            if (hasDesc && st !== "loading") expanded = true;
        } else {
            if (!sticky) expanded = false;
            if (duration > 0) { dismissTimer.interval = duration; dismissTimer.start(); }
        }
    }

    FileView {
        path: root.stateFile
        watchChanges: root.stateFile !== ""
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.applyState(text())
    }

    Spring { id: enter; to: 0; duration: root.dur * 0.66 }
    Connections {
        target: enter
        function onTChanged() {
            if (root.leaving && enter.t >= 1 && enter.target === 0) {
                if (!root.printed) console.log("TOAST_RESULT:" + root.result);
                Qt.quit();
            }
        }
    }

    PanelWindow {
        id: win
        anchors.top: !root.bottom
        anchors.bottom: root.bottom
        anchors.left: root.align === "left"
        anchors.right: root.align === "right"
        margins.top: 28
        margins.bottom: 16
        margins.left: 4
        margins.right: 4
        implicitWidth: root.toastW + 24
        implicitHeight: 420
        color: "transparent"
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "toast"
        // Never steal the keyboard by default: a stray Enter must not answer a question.
        WlrLayershell.keyboardFocus: root.grab ? WlrKeyboardFocus.Exclusive
            : root.buttons.length ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        mask: Region { item: hit }

        onBackingWindowVisibleChanged: if (backingWindowVisible) Qt.callLater(root.begin)

        Item {
            id: toast
            focus: true
            x: 12
            width: root.toastW
            height: parent.height
            readonly property real dir: root.bottom ? 1 : -1 // enter/exit slide direction
            y: 6 * dir * (1 - Math.min(enter.value, 1)) + swipeY
            opacity: Math.max(0, Math.min(1, enter.value))
            scale: 0.95 + 0.05 * enter.value
            transformOrigin: root.bottom ? Item.Bottom : Item.Top
            property real swipeY: 0
            Behavior on swipeY { enabled: !drag.active; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            Keys.onReturnPressed: if (root.st === "confirm" || root.st === "action") root.answer("button", root.buttons[0].react)
            Keys.onEscapePressed: root.dismiss(root.st === "confirm" ? "no" : "dismissed")

            // ── geometry ──
            readonly property real base: height // bottom edge for bottom positions
            readonly property real contentH: content.implicitHeight
            readonly property real expandedH: Math.max(root.pillH * 2.25, root.pillH + contentH)
            Spring { id: pillW; to: Math.min(root.toastW, Math.max(root.pillH, headerCurrent.implicitWidth + 16 + root.pillPadding)) }
            Spring { id: pillHt; to: root.open ? root.pillH + root.blur * 3 : root.pillH }
            Spring { id: bodyHt; to: root.open ? toast.expandedH - root.pillH : 0; settleWhenShrinking: true }
            Spring { id: headerLift; to: root.open ? 1 : 0 }
            readonly property real pillX: root.align === "left" ? 0
                : root.align === "right" ? root.toastW - pillW.value
                : (root.toastW - pillW.value) / 2
            readonly property real pillTop: root.bottom ? base - root.pillH : 0
            readonly property real bodyTop: root.bottom ? base - root.pillH - Math.max(0, bodyHt.value) : root.pillH

            // ── the gooey shape ──
            readonly property real pad: root.blur * 2
            ShaderEffect {
                x: -toast.pad; y: -toast.pad
                width: toast.width + toast.pad * 2
                height: toast.height + toast.pad * 2
                fragmentShader: Qt.resolvedUrl("goo.frag.qsb")
                property size size: Qt.size(width, height)
                property vector4d pill: Qt.vector4d(toast.pad + toast.pillX,
                    toast.pad + (root.bottom ? toast.base - pillHt.value : 0), pillW.value, pillHt.value)
                property vector4d body: Qt.vector4d(toast.pad, toast.pad + toast.bodyTop, root.toastW, Math.max(0, bodyHt.value))
                property real radius: root.roundness
                property real goo: root.blur * 2.5
                property color fill: root.fill
                property color shadow: "transparent"
            }

            // input region + hover + swipe
            Item {
                id: hit
                x: root.open ? 0 : toast.pillX
                y: root.bottom ? toast.bodyTop : 0
                width: root.open ? root.toastW : pillW.value
                height: root.pillH + Math.max(0, bodyHt.value)
                HoverHandler { onHoveredChanged: root.hovered = hovered }
                // sileo swipe: follow up to 20px, dismiss past 30px
                DragHandler {
                    id: drag
                    target: null
                    xAxis.enabled: false
                    property real dy: 0
                    onActiveTranslationChanged: { dy = activeTranslation.y; toast.swipeY = Math.max(-20, Math.min(20, dy)); }
                    onActiveChanged: if (!active) {
                        if (Math.abs(dy) > 30) root.dismiss(root.st === "confirm" ? "no" : "dismissed");
                        toast.swipeY = 0;
                        dy = 0;
                    }
                }
            }

            // ── header: badge + title, cross-fading with blur on change ──
            component HeaderInner: Row {
                id: hi
                property string st: "success"
                property string label: ""
                spacing: 8
                height: root.pillH - 16

                Rectangle { // data-sileo-badge
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24; radius: 12
                    color: Qt.alpha(root.tone(hi.st), 0.2)
                    readonly property bool custom: root.icon !== "" && hi.st !== "loading"
                    Shape {
                        id: glyph
                        visible: !parent.custom
                        anchors.centerIn: parent
                        width: 16; height: 16
                        preferredRendererType: Shape.CurveRenderer
                        RotationAnimation on rotation {
                            running: hi.st === "loading"
                            loops: Animation.Infinite
                            from: 0; to: 360; duration: 1000
                            onRunningChanged: if (!running) glyph.rotation = 0
                        }
                        ShapePath {
                            strokeColor: root.tone(hi.st)
                            strokeWidth: 2
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            scale: Qt.size(16 / 24, 16 / 24)
                            PathSvg { path: root.icons[hi.st] || root.icons.success }
                        }
                    }
                    Image {
                        visible: parent.custom && root.iconIsImage
                        anchors.centerIn: parent
                        width: 16; height: 16
                        sourceSize: Qt.size(32, 32)
                        source: visible ? "file://" + root.icon.replace(/^~/, Quickshell.env("HOME")) : ""
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    Text {
                        visible: parent.custom && !root.iconIsImage
                        anchors.centerIn: parent
                        font.pixelSize: 13
                        color: root.tone(hi.st)
                        text: root.icon
                    }
                }
                Text { // data-sileo-title: 13.2px / 500, capitalised
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: root.font
                    font.pointSize: 13.2 * 0.75
                    font.weight: Font.Medium
                    font.capitalization: Font.Capitalize
                    color: root.tone(hi.st)
                    text: hi.label
                }
            }

            Item {
                id: header
                x: toast.pillX + 8
                y: toast.pillTop + 8 - 3 * headerLift.value * toast.dir
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
                    st: root.st
                    label: root.titleText
                    layer.enabled: curBlur.value > 0.01
                    layer.effect: MultiEffect { blurEnabled: true; blur: curBlur.value; blurMax: 12 }
                    QtObject { id: curBlur; property real value: 0.5 }
                    Component.onCompleted: headerIn.restart()
                }

                property string lastSt: root.st
                property string lastLabel: root.titleText
                Connections {
                    target: root
                    function onTitleTextChanged() { header.swap(); }
                    function onStChanged() { header.swap(); }
                }
                function swap(): void {
                    if (lastSt === root.st && lastLabel === root.titleText) return;
                    headerPrev.st = lastSt;
                    headerPrev.label = lastLabel;
                    lastSt = root.st;
                    lastLabel = root.titleText;
                    headerOut.restart();
                    headerIn.restart();
                }
                ParallelAnimation {
                    id: headerOut
                    NumberAnimation { target: headerPrev; property: "opacity"; from: 1; to: 0; duration: root.dur * 0.7; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: prevBlur; property: "value"; from: 0; to: 0.5; duration: root.dur * 0.7; easing.type: Easing.InOutQuad }
                }
                ParallelAnimation {
                    id: headerIn
                    NumberAnimation { target: headerCurrent; property: "opacity"; from: 0; to: 1; duration: root.dur; easing.type: Easing.OutCubic }
                    NumberAnimation { target: curBlur; property: "value"; from: 0.5; to: 0; duration: root.dur; easing.type: Easing.OutCubic }
                }
            }

            // ── content (data-sileo-description) ──
            Column {
                id: content
                y: root.bottom ? toast.base - toast.expandedH : root.pillH
                width: root.toastW
                padding: 16
                spacing: 12
                enabled: root.open
                opacity: 0
                Connections {
                    target: root
                    function onOpenChanged() {
                        contentFade.stop();
                        contentPause.duration = root.open ? root.dur * 0.3 : root.dur * 0.04;
                        contentOpacity.duration = root.open ? root.dur * 0.6 : root.dur * 0.08;
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
                    font.family: root.font
                    font.pixelSize: 14
                    lineHeight: 20
                    lineHeightMode: Text.FixedHeight
                    color: root.descColor
                    textFormat: Text.StyledText
                    text: root.desc
                }

                // data-sileo-button: 28px, padding 0 .625rem, 12px / 500, tone @15% (hover 25%)
                Flow {
                    visible: root.buttons.length > 0
                    width: root.toastW - 32
                    spacing: 8
                    Repeater {
                        model: root.buttons
                        delegate: Rectangle {
                            required property var modelData
                            width: lbl.implicitWidth + 20
                            height: 28
                            radius: 14
                            color: Qt.alpha(modelData.tone, ma.containsMouse ? 0.25 : 0.15)
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                id: lbl
                                anchors.centerIn: parent
                                font.family: root.font
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: modelData.tone
                                text: modelData.label
                            }
                            MouseArea {
                                id: ma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.answer(modelData.id, modelData.react)
                            }
                        }
                    }
                }
            }
        }
    }
}
