import QtQuick
import QtTest
import "../services/shelf.js" as S

// The island shelf (services/shelf.js): files you put down on the island and
// drag out into any app. Folders stay after a drag, everything else leaves.
TestCase {
    name: "Shelf"

    function file(path, extra) { return Object.assign(S.item(path, false, 1), extra || {}); }

    // ── what a dropped thing is ──
    function test_kinds_come_from_the_extension() {
        compare(S.kindOf("/a/shot.PNG", false), "image");
        compare(S.kindOf("/a/clip.webm", false), "video");
        compare(S.kindOf("/a/notes.pdf", false), "file");
        compare(S.kindOf("/a/no-extension", false), "file");
    }
    function test_a_folder_is_a_folder_whatever_its_name() {
        compare(S.kindOf("/a/photos.png", true), "folder");
    }
    function test_dropped_urls_become_paths() {
        compare(S.pathsOf(["file:///home/me/My%20Shot.png", "file:///tmp/x"]), ["/home/me/My Shot.png", "/tmp/x"]);
    }
    function test_urls_that_are_not_files_are_dropped() {
        compare(S.pathsOf(["https://example.com/a.png", "", "file:///ok"]), ["/ok"]);
    }
    function test_an_item_is_named_after_its_file() {
        const it = S.item("/home/me/Downloads/report.pdf", false, 5);
        compare(it.name, "report.pdf");
        compare(it.kind, "file");
        compare(it.path, "/home/me/Downloads/report.pdf");
        verify(it.id !== "");
    }
    function test_text_is_named_after_its_first_line() {
        const it = S.textItem("  hello there\nsecond line", 5);
        compare(it.kind, "text");
        compare(it.name, "hello there");
        compare(it.text, "  hello there\nsecond line");
    }

    function test_browser_links_are_told_apart_from_files() {
        compare(S.webOf(["file:///a", "https://x.org/p.png", "HTTP://y.org/"]), ["https://x.org/p.png", "HTTP://y.org/"]);
    }
    function test_a_fetched_link_is_named_after_its_path() {
        compare(S.webName("https://i.example.org/a/My%20Cat.jpg?w=200#x"), "My Cat.jpg");
        compare(S.webName("https://example.org/"), "download");
        compare(S.webName("https://example.org/page"), "download");
        compare(S.webName("https://example.org/..evil.png"), "evil.png");
    }

    function test_a_browser_drag_carrying_the_file_itself_is_found() {
        compare(S.carried(["text/uri-list", "application/octet-stream;name=\"OIF-17.jpg\""]),
                { format: "application/octet-stream;name=\"OIF-17.jpg\"", name: "OIF-17.jpg" });
        compare(S.carried(["text/uri-list", "text/html"]), null);
        compare(S.carried(["application/octet-stream;name=\"../../x.png\""]).name, "x.png");
    }
    function test_bytes_are_base64_encoded_exactly() {
        const b = new Uint8Array([0, 1, 2, 250, 255, 128, 77]).buffer;
        compare(S.base64(b), "AAEC+v+ATQ==");
        compare(S.base64(new Uint8Array([104, 105]).buffer), "aGk=");
        compare(S.base64(new Uint8Array([]).buffer), "");
    }

    // ── putting things down ──
    function test_new_things_go_first() {
        const out = S.add([file("/a")], [file("/b")]);
        compare(out.map(i => i.path), ["/b", "/a"]);
    }
    function test_putting_the_same_file_down_again_moves_it_to_the_front() {
        const out = S.add([file("/a"), file("/b")], [file("/b")]);
        compare(out.map(i => i.path), ["/b", "/a"]);
    }
    function test_the_shelf_holds_at_most_max_items() {
        let l = [];
        for (let i = 0; i < S.MAX + 5; i++) l = S.add(l, [file("/f" + i)]);
        compare(l.length, S.MAX);
        compare(l[0].path, "/f" + (S.MAX + 4));
    }

    // ── taking things off ──
    function test_a_file_leaves_after_it_is_dragged_out() {
        const a = file("/a"), b = file("/b");
        const r = S.afterDrag([a, b], a.id);
        compare(r.items.map(i => i.path), ["/b"]);
        compare(r.removed.path, "/a");
    }
    function test_a_folder_stays_after_it_is_dragged_out() {
        const d = S.item("/home/me/Assets", true, 1);
        const r = S.afterDrag([d], d.id);
        compare(r.items.length, 1);
        compare(r.removed, null);
    }
    function test_undo_puts_it_back_where_it_was() {
        const a = file("/a"), b = file("/b"), c = file("/c");
        const r = S.afterDrag([a, b, c], b.id);
        compare(S.putBack(r.items, r.removed, r.at).map(i => i.path), ["/a", "/b", "/c"]);
    }
    function test_removing_something_not_there_changes_nothing() {
        const a = file("/a");
        const r = S.afterDrag([a], "nope");
        compare(r.items.length, 1);
        compare(r.removed, null);
    }

    // ── dragging out ──
    function test_files_drag_out_as_a_uri_list() {
        compare(S.uriList("/home/me/My Shot#1.png"), "file:///home/me/My%20Shot%231.png\r\n");
    }

    // ── downloads ──
    function test_half_finished_downloads_are_ignored() {
        verify(S.isPartial("movie.mp4.part"));
        verify(S.isPartial("setup.exe.crdownload"));
        verify(S.isPartial(".hidden"));
        verify(S.isPartial("x.tmp"));
        verify(!S.isPartial("report.pdf"));
    }
}
