import QtQuick
import QtTest
import "../modules/island/hover.js" as Hover

// When hovering the island grows it into the media card or the dashboard
// (modules/island/hover.js).
TestCase {
    name: "IslandHover"

    readonly property var resting: ({ expanded: false, popup: false, fullscreen: false, sinceClosed: 5000 })
    function when(changes) { return Object.assign({}, resting, changes); }

    function test_hovering_the_resting_island_opens_it() { verify(Hover.opens(resting)); }
    function test_hovering_a_popup_does_not_open_anything() {
        // a toast, a question, a volume level: the pointer is there to read or tap it
        verify(!Hover.opens(when({ popup: true })));
    }
    function test_an_island_already_open_is_not_opened_again() { verify(!Hover.opens(when({ expanded: true }))); }
    function test_just_after_closing_it_does_not_spring_back() { verify(!Hover.opens(when({ sinceClosed: 300 }))); }
    function test_under_fullscreen_hovering_does_nothing() { verify(!Hover.opens(when({ fullscreen: true }))); }
}
