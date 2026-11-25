import QtQuick
import QtTest
import "../services/widgets.js" as W

// Widgets (services/widgets.js): a widget checked from the file, the command
// each template runs, and how its output becomes what's shown.
TestCase {
    name: "Widgets"

    function w(template, fields, extra) { return W.clean(Object.assign({ id: "x", template: template, fields: fields }, extra || {})); }

    // ── a widget, checked ──
    function test_a_widget_gets_its_template_defaults() {
        const s = w("server", { target: " 10.0.0.2 " });
        compare(s.fields.target, "10.0.0.2");
        compare(s.label, "Server up");
        compare(s.icon, "dns");
        compare(s.every, 30);
        compare(s.pinned, false);
    }
    function test_unknown_templates_and_missing_fields_are_dropped() {
        compare(W.clean({ id: "a", template: "nope", fields: {} }), null);
        compare(w("server", { target: "" }), null);
        compare(W.clean({ template: "server", fields: { target: "h" } }), null);
    }
    function test_optional_fields_can_be_empty_and_choices_fall_back() {
        compare(w("number", { url: "https://a", path: "n" }).fields.unit, "");
        compare(w("github", { repo: "o/r", show: "bogus" }).fields.show, "ci");
    }
    function test_intervals_have_a_floor() {
        compare(w("command", { cmd: "date" }, { every: 1 }).every, 60);
        compare(w("command", { cmd: "date" }, { every: 15 }).every, 15);
    }
    function test_duplicate_ids_keep_the_first() {
        const l = W.cleanAll([{ id: "a", template: "command", fields: { cmd: "1" } }, { id: "a", template: "command", fields: { cmd: "2" } }]);
        compare(l.length, 1);
        compare(l[0].fields.cmd, "1");
    }
    function test_new_ids_skip_taken_ones() {
        compare(W.newId("server", [{ id: "server-1" }, { id: "server-2" }]), "server-3");
        compare(W.newId("github", []), "github-1");
    }

    // ── commands ──
    function test_a_host_is_pinged_and_a_url_is_loaded() {
        compare(W.command(w("server", { target: "10.0.0.2" }))[0], "ping");
        const c = W.command(w("server", { target: "https://example.com" }));
        compare(c[0], "curl");
        compare(c[c.length - 1], "https://example.com");
    }
    function test_what_you_type_is_never_run_by_a_shell_except_commands() {
        const evil = "x; rm -rf ~";
        compare(W.command(w("server", { target: evil })).slice(-1)[0], evil);
        compare(W.command(w("github", { repo: evil, show: "ci" })).indexOf(evil), 4);
        compare(W.command(w("command", { cmd: "date" })), ["sh", "-c", "date"]);
    }
    function test_a_toggle_click_runs_the_other_command() {
        const t = w("toggle", { check: "c", on: "up", off: "down" });
        compare(W.action(t, true), ["sh", "-c", "down"]);
        compare(W.action(t, false), ["sh", "-c", "up"]);
        compare(W.action(w("command", { cmd: "d" }), true), null);
    }

    // ── output, read ──
    function test_server_by_ping() {
        const s = w("server", { target: "h" });
        compare(W.parse(s, "64 bytes from h: icmp_seq=1 ttl=64 time=0.412 ms\n", 0), { value: "up · 0 ms", tone: "success" });
        compare(W.parse(s, "64 bytes: time=12.6 ms", 0).value, "up · 13 ms");
        compare(W.parse(s, "", 1), { value: "down", tone: "error" });
    }
    function test_server_by_url() {
        const s = w("server", { target: "https://a" });
        compare(W.parse(s, "200 0.084", 0), { value: "up · 84 ms", tone: "success" });
        compare(W.parse(s, "503 0.1", 0), { value: "HTTP 503", tone: "warning" });
        compare(W.parse(s, "000 0.0", 28).tone, "error");
    }
    function test_number_follows_the_field_path() {
        const n = w("number", { url: "https://a", path: "players.online", unit: "players" });
        compare(W.parse(n, '{"players":{"online":14}}', 0), { value: "14 players", tone: "" });
        compare(W.parse(w("number", { url: "u", path: "list.1" }), '{"list":[5,7]}', 0).value, "7");
        compare(W.parse(w("number", { url: "u", path: "p" }), '{"p":12345.6}', 0).value, "12,346");
        compare(W.parse(n, '{"players":{}}', 0).tone, "warning");
        compare(W.parse(n, "<html>", 0).value, "not JSON");
        compare(W.parse(n, "", 22).value, "no answer");
    }
    function test_github_ci_prs_and_release() {
        const ci = w("github", { repo: "o/r", show: "ci" });
        compare(W.parse(ci, '[{"status":"completed","conclusion":"success"}]', 0), { value: "passing", tone: "success" });
        compare(W.parse(ci, '[{"status":"completed","conclusion":"failure"}]', 0).tone, "error");
        compare(W.parse(ci, '[{"status":"in_progress","conclusion":""}]', 0).progress, -1);
        compare(W.parse(ci, "[]", 0).value, "no runs");
        compare(W.parse(w("github", { repo: "o/r", show: "prs" }), '[{"number":1},{"number":2}]', 0).value, "2 PRs");
        compare(W.parse(w("github", { repo: "o/r", show: "release" }), '{"tagName":"v0.4.0"}', 0).value, "v0.4.0");
        compare(W.parse(ci, "", 1).value, "gh failed");
    }
    function test_toggle_is_on_while_the_check_succeeds() {
        const t = w("toggle", { check: "c", on: "a", off: "b" });
        compare(W.parse(t, "", 0).on, true);
        compare(W.parse(t, "", 3), { value: "off", tone: "", on: false });
    }
    function test_command_text_or_json() {
        const c = w("command", { cmd: "x" });
        compare(W.parse(c, "\n  up 3 days  \nmore\n", 0), { value: "up 3 days", tone: "" });
        compare(W.parse(c, '{"value":42,"tone":"warning","icon":"bolt","progress":1.5}', 0), { value: "42", tone: "warning", icon: "bolt", progress: 1 });
        compare(W.parse(c, '{"value":"a","tone":"purple"}', 0).tone, "");
        compare(W.parse(c, "", 2), { value: "failed (2)", tone: "error" });
    }

    // ── the island ──
    function test_at_most_four_chips_and_a_count_of_the_rest() {
        const l = [1, 2, 3, 4, 5, 6].map(i => ({ id: "w" + i, pinned: i !== 2 }));
        const c = W.chips(l);
        compare(c.shown.map(x => x.id), ["w1", "w3", "w4", "w5"]);
        compare(c.more, 1);
    }
}
