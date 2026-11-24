import QtQuick
import QtTest
import "../modules/island/overview.js" as Ov

// The overview's small decisions (modules/island/overview.js): where a window
// dropped on "New workspace" goes, and stepping through a card's windows.
TestCase {
    name: "Overview"

    function test_a_new_workspace_is_the_lowest_unused_number() {
        compare(Ov.freeWorkspace([1, 2, 3]), 4);
        compare(Ov.freeWorkspace([1, 3, 4]), 2);
        compare(Ov.freeWorkspace([]), 1);
        compare(Ov.freeWorkspace([2, -98, 1]), 3);   // special workspaces don't count
    }
    function test_down_steps_into_the_windows_and_stops_at_the_last() {
        compare(Ov.step(-1, 3, 1), 0);
        compare(Ov.step(0, 3, 1), 1);
        compare(Ov.step(2, 3, 1), 2);
    }
    function test_up_steps_back_out_to_the_card() {
        compare(Ov.step(1, 3, -1), 0);
        compare(Ov.step(0, 3, -1), -1);
        compare(Ov.step(-1, 3, -1), -1);
    }
    function test_an_empty_card_has_nothing_to_pick() {
        compare(Ov.step(-1, 0, 1), -1);
        compare(Ov.step(4, 2, -1), 0);   // windows went away: clamp to the last, then up one
    }
    function test_windows_are_picked_in_reading_order() {
        const ws = [{ a: "c", at: [960, 0] }, { a: "b", at: [0, 540] }, { a: "a", at: [0, 0] }];
        compare(Ov.readingOrder(ws, w => w.at).map(w => w.a), ["a", "c", "b"]);
    }
}
