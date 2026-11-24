import QtQuick
import QtTest
import "../services/snooze.js" as Snooze

// Snoozing a notification: it goes away and comes back later as a fresh
// pop-up (services/snooze.js).
TestCase {
    name: "Snooze"

    // local times, so the tests read the same in any time zone
    function at(day, h, m) { return new Date(2026, 10, day, h, m, 0, 0).getTime(); }
    function hm(ms) { const d = new Date(ms); return [d.getDate(), d.getHours(), d.getMinutes()]; }

    // ── when it comes back ──
    function test_twenty_minutes_is_twenty_minutes_from_now() { compare(hm(Snooze.until("20m", at(24, 14, 10))), [24, 14, 30]); }
    function test_an_hour_is_an_hour_from_now() { compare(hm(Snooze.until("1h", at(24, 23, 30))), [25, 0, 30]); }
    function test_tomorrow_is_nine_the_next_morning() { compare(hm(Snooze.until("tomorrow", at(24, 14, 10))), [25, 9, 0]); }
    function test_tomorrow_said_in_the_small_hours_is_nine_the_same_morning() { compare(hm(Snooze.until("tomorrow", at(24, 1, 30))), [24, 9, 0]); }
    function test_an_unknown_choice_is_not_a_time() { compare(Snooze.until("next year", at(24, 14, 10)), 0); }

    // ── the list of what's snoozed ──
    function test_snoozing_adds_it() { compare(Snooze.add([], 7, 5000), [{ key: 7, until: 5000 }]); }
    function test_snoozing_again_replaces_the_earlier_time() { compare(Snooze.add([{ key: 7, until: 5000 }], 7, 9000), [{ key: 7, until: 9000 }]); }
    function test_cancelling_removes_it() { compare(Snooze.remove([{ key: 7, until: 5000 }, { key: 8, until: 6000 }], 7), [{ key: 8, until: 6000 }]); }
    function test_what_is_due_is_split_from_what_still_waits() {
        const r = Snooze.split([{ key: 7, until: 5000 }, { key: 8, until: 9000 }], 6000);
        compare(r.due, [7]);
        compare(r.waiting, [{ key: 8, until: 9000 }]);
    }
    function test_exactly_on_time_counts_as_due() { compare(Snooze.split([{ key: 7, until: 5000 }], 5000).due, [7]); }
    function test_a_snooze_whose_notification_is_gone_is_dropped() {
        compare(Snooze.prune([{ key: 7, until: 5000 }, { key: 8, until: 6000 }], [8]), [{ key: 8, until: 6000 }]);
    }
    function test_until_tells_when_one_comes_back_or_0() {
        compare(Snooze.when([{ key: 7, until: 5000 }], 7), 5000);
        compare(Snooze.when([{ key: 7, until: 5000 }], 9), 0);
    }

    // ── saying when ──
    function test_later_today_reads_as_a_time() { compare(Snooze.label(at(24, 14, 30), at(24, 14, 10)), "Back at 14:30"); }
    function test_another_day_says_tomorrow() { compare(Snooze.label(at(25, 9, 0), at(24, 14, 10)), "Back tomorrow at 9:00"); }
    function test_minutes_keep_two_digits() { compare(Snooze.label(at(24, 15, 5), at(24, 14, 10)), "Back at 15:05"); }

    // ── what the pop-up offers ──
    function test_choices_are_the_three_lengths() {
        compare(Snooze.choices.map(c => c.id), ["__snooze:20m", "__snooze:1h", "__snooze:tomorrow"]);
        compare(Snooze.choiceOf("__snooze:1h"), "1h");
        compare(Snooze.choiceOf("default"), "");
    }
}
