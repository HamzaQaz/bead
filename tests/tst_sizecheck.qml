import QtQuick
import QtTest
import "../config/sizecheck.js" as SizeCheck

// Changing bead's size: what the Settings row says before it's applied, and
// the keep-or-go-back check after the restart (config/sizecheck.js).
TestCase {
    name: "SizeCheck"

    function test_a_size_reads_as_a_percentage() {
        compare(SizeCheck.percent(1), "100%");
        compare(SizeCheck.percent(1.15), "115%");
        compare(SizeCheck.percent(1.35), "135%");
    }
    function test_the_row_says_from_what_to_what_and_fits_its_narrow_column() { compare(SizeCheck.changeHint(1, 1.35), "100% → 135%"); }

    // a pick is something to apply only if it's a different size
    function test_picking_the_size_in_use_is_nothing_to_apply() { compare(SizeCheck.pick("1.15", 1.15), ""); }
    function test_picking_another_size_is_kept_until_applied() { compare(SizeCheck.pick("1.35", 1.15), "1.35"); }

    // after the restart: is there a size change still to confirm?
    function test_no_earlier_size_means_nothing_to_confirm() { verify(!SizeCheck.pending(1.35, 0)); }
    function test_an_earlier_size_that_differs_needs_confirming() { verify(SizeCheck.pending(1.35, 1)); }
    function test_an_earlier_size_that_is_the_same_does_not() { verify(!SizeCheck.pending(1.15, 1.15)); }

    // the countdown on the island
    function test_the_prompt_names_the_size_and_the_seconds_left() {
        compare(SizeCheck.prompt(1.35, 9), "Size is now 135% · tap to keep · back in 9 s");
    }
    function test_counting_down_ends_in_going_back() {
        compare(SizeCheck.next(3), { left: 2, revert: false });
        compare(SizeCheck.next(1), { left: 0, revert: true });
    }
}
