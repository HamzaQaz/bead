import QtQuick
import QtTest
import "../modules/notifications/stacks.js" as Stacks

// Pop-ups from one app stack into one pill (modules/notifications/stacks.js).
TestCase {
    name: "Stacks"
    function n(key, app, summary, extra) { return Object.assign({ key: key, appName: app, summary: summary, body: summary + " body", urgency: 1, sticky: false }, extra || {}); }

    function test_a_second_from_the_same_app_replaces_the_first() {
        const r = Stacks.merge([n(1, "Discord", "Ana")], n(2, "Discord", "Ben"));
        compare(r.gone, 1);
        compare(r.entry.key, 2);
        compare(r.entry.earlier.map(e => e.summary), ["Ana"]);
    }
    function test_it_keeps_the_newest_few_earlier_ones_newest_first() {
        let list = [n(1, "Discord", "a")];
        let e = null;
        for (let k = 2; k <= 6; k++) {
            const r = Stacks.merge(list, n(k, "Discord", String.fromCharCode(96 + k)));
            e = r.entry; list = [e];
        }
        compare(e.earlier.map(x => x.summary), ["e", "d", "c", "b"]);
        compare(e.count, 6);
    }
    function test_other_apps_do_not_stack() { compare(Stacks.merge([n(1, "Discord", "a")], n(2, "Signal", "b")), null); }
    function test_nameless_apps_do_not_stack() { compare(Stacks.merge([n(1, "", "a")], n(2, "", "b")), null); }
    function test_critical_ones_do_not_stack() {
        compare(Stacks.merge([n(1, "Mail", "a")], n(2, "Mail", "b", { urgency: 2 })), null);
        compare(Stacks.merge([n(1, "Mail", "a", { urgency: 2 })], n(2, "Mail", "b")), null);
    }
    function test_toasts_and_pinned_ones_do_not_stack() {
        compare(Stacks.merge([n(1, "x", "a", { spec: { id: "t" } })], n(2, "x", "b")), null);
        compare(Stacks.merge([n(1, "x", "a", { sticky: true })], n(2, "x", "b")), null);
    }
    function test_label_counts_the_whole_stack() {
        compare(Stacks.label(n(1, "Discord", "a")), "");
        compare(Stacks.label({ count: 3 }), "3");
    }
    function test_fan_lists_the_earlier_ones_as_plain_text() {
        const e = { earlier: [{ summary: "Ana", body: "hi <b>there</b>" }] };
        verify(Stacks.fan(e).indexOf("Ana") >= 0);
        verify(Stacks.fan(e).indexOf("hi there") >= 0); verify(Stacks.fan(e).indexOf("<b>") < 0);
        compare(Stacks.fan({}), "");
    }
}
