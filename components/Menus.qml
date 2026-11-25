pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Right-click menus (ContextMenu), one at a time. open() shows rows next to a
// point in an item; tray() shows an app's own menu (a tray icon's) in bead's
// style; text() is the menu for a text field (cut, copy, paste, select all).
Singleton {
    id: root
    property var current: null

    function open(item: Item, x: real, y: real, items: var): var { return show(item, x, y, { items: items }); }
    function tray(item: Item, x: real, y: real, handle: var): var { return handle ? show(item, x, y, { handle: handle }) : null; }
    function close(): void { if (current) { try { current.dismiss(); } catch (e) {} } current = null; }
    function show(item: Item, x: real, y: real, props: var): var {
        close();
        if (!item) return null;
        current = menu.createObject(item, Object.assign({ target: item, at: Qt.point(x, y) }, props));
        return current;
    }

    // a text field. The selection is kept as it was at the right-click: the
    // menu takes the keyboard, and the field drops its selection when it loses it
    function text(input: Item, x: real, y: real): var {
        if (!input) return null;
        const s = input.selectionStart, e = input.selectionEnd;
        const hidden = input.echoMode !== undefined && input.echoMode !== TextInput.Normal;
        const ro = !!input.readOnly;
        const sel = e > s;
        const again = () => { input.forceActiveFocus(); input.select(s, e); };
        return open(input, x, y, [
            { t: "Cut", g: "content_cut", keys: "Ctrl+X", enabled: sel && !ro && !hidden, act: () => { again(); input.cut(); } },
            { t: "Copy", g: "content_copy", keys: "Ctrl+C", enabled: sel && !hidden, act: () => { again(); input.copy(); } },
            { t: "Paste", g: "content_paste", keys: "Ctrl+V", enabled: !ro, act: () => { again(); input.paste(); } },
            { sep: true },
            { t: "Select all", g: "select_all", keys: "Ctrl+A", enabled: (input.length ?? input.text.length) > 0, act: () => { input.forceActiveFocus(); input.selectAll(); } },
            { t: "Clear", g: "backspace", enabled: !ro && (input.length ?? input.text.length) > 0, act: () => { input.forceActiveFocus(); input.selectAll(); input.remove(0, input.length ?? input.text.length); } }
        ]);
    }

    Component { id: menu; ContextMenu {} }

    // show one without a click (screenshots, checking it): "island"
    signal demo(string what)
    IpcHandler {
        target: "menus"
        function demo(what: string): void { root.demo(what); }
        function close(): void { root.close(); }
        function open(): bool { return !!root.current; }
    }
}
