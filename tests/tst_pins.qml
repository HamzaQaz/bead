import QtQuick
import QtTest
import "../services/pins.js" as Pins

// Pinned clips: things you paste again and again, kept on top of the
// clipboard list and never expiring (services/pins.js).
TestCase {
    name: "Pins"

    readonly property var mail: ({ id: "p1", text: "me@example.org", added: 100 })
    readonly property var addr: ({ id: "p2", text: "1 Example Street", added: 200 })

    // ── what can be pinned ──
    function test_plain_text_can_be_pinned() { compare(Pins.whyNot({ type: "text", image: null }), ""); }
    function test_a_secret_cannot_be_pinned() { compare(Pins.whyNot({ type: "secret", image: null }), "Keys and tokens can't be pinned"); }
    function test_an_image_cannot_be_pinned() { compare(Pins.whyNot({ type: "image", image: { w: 4, h: 4 } }), "Only text can be pinned"); }

    // ── pinning and unpinning ──
    function test_a_new_pin_goes_on_top() {
        const out = Pins.add([mail], "1 Example Street", 200);
        compare(out.map(p => p.text), ["1 Example Street", "me@example.org"]);
        compare(out[0].added, 200);
    }
    function test_pinning_the_same_text_again_changes_nothing() {
        const out = Pins.add([addr, mail], "me@example.org", 300);
        compare(out.map(p => p.text), ["1 Example Street", "me@example.org"]);
    }
    function test_pinning_ignores_surrounding_blank_space_when_comparing() {
        compare(Pins.add([mail], "  me@example.org\n", 300).length, 1);
    }
    function test_empty_text_is_not_pinned() { compare(Pins.add([mail], "   ", 300).length, 1); }
    function test_each_pin_gets_its_own_id() {
        const out = Pins.add(Pins.add([], "a", 1), "b", 1);
        verify(out[0].id !== out[1].id);
    }
    function test_unpinning_removes_just_that_one() { compare(Pins.remove([addr, mail], "p2").map(p => p.id), ["p1"]); }
    function test_text_is_known_as_pinned_or_not() {
        verify(Pins.has([mail], "me@example.org"));
        verify(!Pins.has([mail], "someone@example.org"));
    }

    // ── the list: pins first, then the history without what's pinned ──
    function test_pins_come_before_the_history() {
        const rows = Pins.rows([mail], [{ id: "7", text: "hello", type: "text" }], "");
        compare(rows.map(r => r.text), ["me@example.org", "hello"]);
        verify(rows[0].pinned && !rows[1].pinned);
    }
    function test_a_history_entry_that_is_pinned_shows_once() {
        const rows = Pins.rows([mail], [{ id: "7", text: "me@example.org", type: "text" }, { id: "8", text: "hello", type: "text" }], "");
        compare(rows.map(r => r.text), ["me@example.org", "hello"]);
    }
    function test_searching_narrows_pins_too() {
        const rows = Pins.rows([mail, addr], [{ id: "8", text: "hello street", type: "text" }], "street");
        compare(rows.map(r => r.text), ["1 Example Street", "hello street"]);
    }
    function test_a_pinned_row_has_an_id_that_cannot_clash_with_the_history() {
        compare(Pins.rows([mail], [], "")[0].id, "pin:p1");
    }

    // ── the file ──
    function test_reading_a_broken_or_empty_file_gives_no_pins() {
        compare(Pins.parse("").length, 0);
        compare(Pins.parse("{not json").length, 0);
        compare(Pins.parse('{"pins": "nope"}').length, 0);
    }
    function test_reading_skips_entries_without_text() {
        compare(Pins.parse('{"pins":[{"id":"p1","text":"a","added":1},{"id":"p2"},{"id":"p3","text":""}]}').map(p => p.id), ["p1"]);
    }
    function test_what_is_written_reads_back_the_same() {
        compare(Pins.parse(Pins.serialise([addr, mail])), [addr, mail]);
    }
}
