import QtQuick
import QtTest
import "../modules/dashboard/focusnav.js" as Nav

// Moving around the dashboard with the keyboard: which control the ring goes
// to, and what each key means (modules/dashboard/focusnav.js).
TestCase {
    name: "FocusNav"

    // a 2×2 grid of controls, and a wide one under them
    readonly property var a: ({ id: "a", x: 0, y: 0, w: 100, h: 30 })
    readonly property var b: ({ id: "b", x: 200, y: 0, w: 100, h: 30 })
    readonly property var c: ({ id: "c", x: 0, y: 100, w: 100, h: 30 })
    readonly property var d: ({ id: "d", x: 200, y: 100, w: 100, h: 30 })
    readonly property var wide: ({ id: "wide", x: 0, y: 200, w: 300, h: 30 })
    readonly property var grid: [a, b, c, d, wide]
    function to(from, dir) { const r = Nav.nearest(grid, from, dir); return r ? r.id : ""; }

    // ── the nearest control in a direction ──
    function test_right_goes_to_the_one_beside_it() { compare(to(a, "right"), "b"); }
    function test_down_goes_to_the_one_under_it() { compare(to(a, "down"), "c"); }
    function test_left_and_up_go_back() { compare(to(d, "left"), "c"); compare(to(d, "up"), "b"); }
    function test_one_in_line_beats_a_closer_one_off_to_the_side() {
        // from b, down: d is straight below; c is as near in y but off to the left
        compare(to(b, "down"), "d");
    }
    function test_a_wide_control_is_reached_from_anything_above_it() { compare(to(c, "down"), "wide"); compare(to(d, "down"), "wide"); }
    function test_from_a_wide_control_up_goes_to_the_nearest_above() { compare(to(wide, "up"), "c"); }
    function test_nothing_that_way_stays_put() { compare(Nav.nearest(grid, a, "left"), null); compare(Nav.nearest(grid, a, "up"), null); }
    function test_with_no_ring_yet_any_arrow_starts_at_the_first_control() { compare(Nav.nearest(grid, null, "down").id, "a"); }
    function test_no_controls_gives_nothing() { compare(Nav.nearest([], null, "down"), null); }

    // ── reading order, for Tab ──
    function test_reading_order_is_rows_then_left_to_right() {
        compare(Nav.order([d, wide, b, c, a]).map(r => r.id), ["a", "b", "c", "d", "wide"]);
    }
    function test_controls_nearly_level_count_as_one_row() {
        const low = { id: "low", x: 0, y: 6, w: 50, h: 30 }, high = { id: "high", x: 100, y: 0, w: 50, h: 30 };
        compare(Nav.order([high, low]).map(r => r.id), ["low", "high"]);
    }
    function test_tab_steps_through_and_wraps() {
        compare(Nav.step(grid, a, 1).id, "b");
        compare(Nav.step(grid, wide, 1).id, "a");
        compare(Nav.step(grid, a, -1).id, "wide");
        compare(Nav.step(grid, null, 1).id, "a");
    }

    // ── what a key means ──
    readonly property var plain: ({ tabs: 7, tab: 2, adjustable: false, editing: false, ctrl: false, shift: false })
    function key(name, changes) { return Nav.action(name, Object.assign({}, plain, changes || {})); }

    function test_a_number_goes_to_that_tab() { compare(key("3"), { type: "tab", index: 2 }); }
    function test_a_number_past_the_last_tab_does_nothing() { compare(key("8"), { type: "none" }); }
    function test_ctrl_tab_goes_to_the_next_tab_and_wraps() {
        compare(key("Tab", { ctrl: true }), { type: "tab", index: 3 });
        compare(key("Tab", { ctrl: true, tab: 6 }), { type: "tab", index: 0 });
        compare(key("Tab", { ctrl: true, shift: true, tab: 0 }), { type: "tab", index: 6 });
    }
    function test_arrows_move_the_ring() { compare(key("Left"), { type: "move", dir: "left" }); compare(key("Down"), { type: "move", dir: "down" }); }
    function test_on_a_slider_left_and_right_adjust_but_up_and_down_still_move() {
        compare(key("Right", { adjustable: true }), { type: "adjust", dir: 1 });
        compare(key("Left", { adjustable: true }), { type: "adjust", dir: -1 });
        compare(key("Up", { adjustable: true }), { type: "move", dir: "up" });
    }
    function test_tab_steps_and_shift_tab_steps_back() { compare(key("Tab"), { type: "step", dir: 1 }); compare(key("Tab", { shift: true }), { type: "step", dir: -1 }); }
    function test_enter_and_space_press() { compare(key("Return"), { type: "press" }); compare(key("Space"), { type: "press" }); }
    function test_escape_closes() { compare(key("Escape"), { type: "close" }); }
    function test_while_typing_escape_only_leaves_the_field() { compare(key("Escape", { editing: true }), { type: "leave" }); }
    function test_while_typing_other_keys_are_the_fields() {
        compare(key("3", { editing: true }), { type: "none" });
        compare(key("Left", { editing: true }), { type: "none" });
        compare(key("Space", { editing: true }), { type: "none" });
    }
    function test_any_other_key_does_nothing() { compare(key("Q"), { type: "none" }); }

    // ── the hint strip: the keys that work on the focused control ──
    function test_hints_for_a_button() { compare(Nav.hints({ press: true }), "⏎ press · esc close"); }
    function test_hints_for_a_slider() { compare(Nav.hints({ press: true, adjust: true }), "←→ adjust · ⏎ press · esc close"); }
    function test_hints_for_the_calendar() { compare(Nav.hints({ calendar: true }), "←↑↓→ day · [ ] month · t today · esc close"); }
    function test_hints_with_nothing_focused() { compare(Nav.hints(null, 8), "←↑↓→ move · 1–8 tabs · esc close"); }
}
