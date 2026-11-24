.pragma library
// Hovering the island a moment grows it (the media card while something
// plays, else the dashboard). Not always: tests/tst_hover.qml.
//
// s: { expanded, popup (a toast, question or level is showing: the pointer
//      is there to read or tap it), fullscreen, sinceClosed (ms) }
function opens(s) {
    return !s.expanded && !s.popup && !s.fullscreen && s.sinceClosed > 600;
}
