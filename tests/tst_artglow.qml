import QtQuick
import QtTest
import "../modules/island/artglow.js" as Glow

// The island's glow colour from an album cover's main colours (artglow.js).
TestCase {
    name: "ArtGlow"
    function c(r, g, b) { return { r: r, g: g, b: b }; }

    function test_it_picks_the_most_vivid_colour() {
        const p = Glow.pick([c(0.1, 0.1, 0.1), c(0.8, 0.2, 0.1), c(0.6, 0.6, 0.6)]);
        compare(p.r, 0.8); compare(p.g, 0.2);
    }
    function test_a_dark_vivid_colour_loses_to_a_bright_one() {
        const p = Glow.pick([c(0.15, 0.0, 0.0), c(0.2, 0.5, 0.9)]);
        compare(p.b, 0.9);
    }
    function test_a_grey_cover_gets_no_glow() { compare(Glow.pick([c(0.5, 0.5, 0.5), c(0.1, 0.1, 0.1), c(0.9, 0.9, 0.88)]), null); }
    function test_no_colours_no_glow() { compare(Glow.pick([]), null); compare(Glow.pick(null), null); }
    function test_the_glow_is_lifted_so_it_shows_on_dark() {
        const p = Glow.pick([c(0.4, 0.1, 0.05)]);
        verify(Math.max(p.r, p.g, p.b) >= 0.75);
    }
}
