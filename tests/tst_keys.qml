import QtQuick
import QtTest
import "../modules/island/keys.js" as Keys

// The keys sheet: bead's keyboard shortcuts, searchable from the launcher
// (modules/island/keys.js, data/keys.json).
TestCase {
    name: "Keys"

    readonly property var list: [
        { keys: "SUPER + Tab", what: "workspace overview", group: "Windows" },
        { keys: "SUPER + SHIFT + S", what: "screenshot area", group: "Capture" },
        { keys: "XF86AudioPlay", what: "play / pause", group: "Media" }
    ]

    // ── how a combination reads ──
    function test_a_combination_becomes_its_key_caps() { compare(Keys.caps("SUPER + SHIFT + S"), ["Super", "Shift", "S"]); }
    function test_a_lone_modifier_released_reads_as_tapping_it() { compare(Keys.caps("SUPER + SUPER_L"), ["Super"]); }
    function test_media_and_named_keys_read_plainly() {
        compare(Keys.caps("XF86AudioPlay"), ["Play"]);
        compare(Keys.caps("XF86MonBrightnessUp"), ["Brightness +"]);
        compare(Keys.caps("SUPER + Period"), ["Super", "."]);
        compare(Keys.caps("Print"), ["PrtSc"]);
    }
    function test_what_it_does_starts_with_a_capital() { compare(Keys.title("workspace overview"), "Workspace overview"); }

    // ── searching ──
    function test_no_search_lists_them_all_in_order() { compare(Keys.find(list, "").map(k => k.what), ["workspace overview", "screenshot area", "play / pause"]); }
    function test_search_matches_what_it_does() { compare(Keys.find(list, "screen").map(k => k.what), ["screenshot area"]); }
    function test_search_matches_the_keys_themselves() { compare(Keys.find(list, "shift").map(k => k.what), ["screenshot area"]); }
    function test_search_matches_the_group() { compare(Keys.find(list, "media").map(k => k.what), ["play / pause"]); }
    function test_every_word_must_match() { compare(Keys.find(list, "super screen").length, 1); compare(Keys.find(list, "super play").length, 0); }

    // ── the file ──
    function test_a_broken_file_gives_no_keys() { compare(Keys.parse("{").length, 0); compare(Keys.parse('{"a":1}').length, 0); }
    function test_entries_without_keys_or_meaning_are_skipped() {
        compare(Keys.parse('[{"keys":"SUPER + K","what":"dashboard","group":"Panels"},{"keys":"SUPER + X"},{"what":"nothing"}]').length, 1);
    }

    // ── asking for it in the ordinary search ──
    function test_typing_keys_or_shortcuts_asks_for_the_sheet() {
        verify(Keys.asksFor("keys"));
        verify(Keys.asksFor("Shortcuts"));
        verify(Keys.asksFor("keyb"));
        verify(!Keys.asksFor("k"));
        verify(!Keys.asksFor("kitty"));
    }
}
