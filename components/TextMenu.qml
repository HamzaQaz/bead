import QtQuick

// Put inside a TextInput / TextEdit: right-click gives bead's text menu
// (cut, copy, paste, select all). Left clicks still go to the field.
MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.RightButton
    cursorShape: Qt.IBeamCursor
    onPressed: e => Menus.text(parent, e.x, e.y)
}
