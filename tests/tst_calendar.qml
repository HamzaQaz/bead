import QtQuick
import QtTest
import "../modules/dashboard/calendar.js" as Cal

// The dashboard calendar: the month grid, and moving the selected day with keys
// (modules/dashboard/calendar.js). Days are {y, m, d} with m 0-based.
TestCase {
    name: "Calendar"
    readonly property var today: ({ y: 2026, m: 10, d: 24 }) // Tue 24 Nov 2026

    // ── the grid ──
    function test_grid_starts_on_the_monday_before_the_first() {
        const g = Cal.grid({ y: 2026, m: 10, d: 1 }, today);
        compare(g[0].n, 26); compare(g[0].inMonth, false); // Mon 26 Oct
        compare(g[6].n, 1); compare(g[6].inMonth, true);   // Sun 1 Nov
    }
    function test_grid_marks_today_and_the_selected_day() {
        const g = Cal.grid({ y: 2026, m: 10, d: 3 }, today);
        compare(g.filter(c => c.today).map(c => c.n), [24]);
        compare(g.filter(c => c.selected).map(c => c.n), [3]);
    }
    function test_grid_keeps_six_rows_only_when_the_month_needs_them() {
        compare(Cal.grid({ y: 2026, m: 10, d: 1 }, today).length, 42); // Nov 2026 runs to Mon 30th, row 6
        compare(Cal.grid({ y: 2026, m: 1, d: 1 }, today).length, 35);  // Feb 2026 starts on a Sunday: five rows
    }
    function test_february_2027_fits_in_five_rows() {
        compare(Cal.grid({ y: 2027, m: 1, d: 1 }, today).length, 35);
    }

    // ── keys ──
    function key(sel, name) { return Cal.key(sel, name, today); }
    function test_right_is_the_next_day() { compare(key({ y: 2026, m: 10, d: 24 }, "Right").day, { y: 2026, m: 10, d: 25 }); }
    function test_down_is_a_week_later() { compare(key({ y: 2026, m: 10, d: 10 }, "Down").day, { y: 2026, m: 10, d: 17 }); }
    function test_left_off_monday_leaves_the_calendar() { compare(key({ y: 2026, m: 10, d: 23 }, "Left"), null); }
    function test_right_off_sunday_leaves_the_calendar() { compare(key({ y: 2026, m: 10, d: 29 }, "Right"), null); }
    function test_up_from_the_first_week_leaves_it() { compare(key({ y: 2026, m: 10, d: 4 }, "Up"), null); }
    function test_down_from_the_last_week_leaves_it() { compare(key({ y: 2026, m: 10, d: 26 }, "Down"), null); }
    function test_left_on_the_first_runs_into_the_month_before() {
        compare(key({ y: 2026, m: 11, d: 1 }, "Left").day, { y: 2026, m: 10, d: 30 }); // Tue 1 Dec → Mon 30 Nov
    }
    function test_brackets_page_months_keeping_the_day() {
        compare(key({ y: 2026, m: 10, d: 24 }, "]").day, { y: 2026, m: 11, d: 24 });
        compare(key({ y: 2026, m: 0, d: 15 }, "[").day, { y: 2025, m: 11, d: 15 });
    }
    function test_paging_clamps_to_the_end_of_a_short_month() {
        compare(key({ y: 2027, m: 0, d: 31 }, "]").day, { y: 2027, m: 1, d: 28 });
    }
    function test_t_goes_back_to_today() { compare(key({ y: 2025, m: 2, d: 9 }, "t").day, today); }
    function test_other_keys_are_not_the_calendars() { compare(key(today, "Return"), null); compare(key(today, "x"), null); }
    function test_scroll_pages_months() {
        compare(Cal.page({ y: 2026, m: 10, d: 24 }, 1), { y: 2026, m: 11, d: 24 });
        compare(Cal.page({ y: 2026, m: 0, d: 24 }, -1), { y: 2025, m: 11, d: 24 });
    }
}
