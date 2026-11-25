import QtQuick
import QtTest
import "../services/focus.js" as F

// Focus modes (services/focus.js): what a mode changes, when it turns on by
// itself (a schedule, an app being open), and how your own choice and the
// automatic one take turns.
TestCase {
    name: "Focus"

    function mode(extra) { return F.clean(Object.assign({ id: "work", name: "Work" }, extra || {})); }
    // Wed 25 Nov 2026 (+ day) at h:m, local time
    function at(h, m, day) { return new Date(2026, 10, 25 + (day || 0), h, m || 0); }

    // ── a mode, checked ──
    function test_a_mode_gets_defaults_and_bad_fields_are_dropped() {
        const m = F.clean({ id: "x", name: "  Deep work  ", preset: 5, dnd: "yes", nightLight: "maybe", allow: ["Slack", 3, ""],
            schedule: { on: true, days: [1, 9, "x", 3], from: "25:00", to: "17:30" }, apps: ["steam_app_*", ""] });
        compare(m.name, "Deep work");
        compare(m.preset, "");
        compare(m.dnd, false);
        compare(m.nightLight, "");
        compare(m.allow, ["Slack"]);
        compare(m.schedule.days, [1, 3]);
        compare(m.schedule.from, "09:00");
        compare(m.schedule.to, "17:30");
        compare(m.apps, ["steam_app_*"]);
    }
    function test_a_mode_without_an_id_or_name_isnt_one() {
        compare(F.clean({ name: "" }), null);
        compare(F.clean("work"), null);
        compare(F.cleanAll([{ id: "a", name: "A" }, { id: "a", name: "Again" }, null]).length, 1);
    }
    function test_the_built_in_modes_are_valid() {
        const all = F.cleanAll(F.DEFAULTS);
        compare(all.length, F.DEFAULTS.length);
        verify(all.some(m => m.id === "work"));
    }

    // ── schedules ──
    function test_a_daytime_schedule_on_its_days() {
        const s = mode({ schedule: { on: true, days: [1, 2, 3, 4, 5], from: "09:00", to: "17:00" } }).schedule;
        verify(F.inSchedule(s, at(10, 0)));           // Wednesday 10:00
        verify(!F.inSchedule(s, at(8, 59)));
        verify(!F.inSchedule(s, at(17, 0)));           // ends at 17:00
        verify(!F.inSchedule(s, at(10, 0, 3)));         // Saturday
        verify(!F.inSchedule(Object.assign({}, s, { on: false }), at(10, 0)));
    }
    function test_an_overnight_schedule_belongs_to_the_day_it_starts() {
        const s = mode({ schedule: { on: true, days: [5], from: "22:00", to: "07:00" } }).schedule; // Fridays
        verify(F.inSchedule(s, at(23, 0, 2)));          // Friday 23:00
        verify(F.inSchedule(s, at(6, 30, 3)));          // Saturday 06:30: Friday's night
        verify(!F.inSchedule(s, at(6, 30, 2)));         // Friday 06:30: Thursday's night, not on
    }

    // ── apps ──
    function test_app_patterns_match_window_classes() {
        verify(F.appMatches(["steam_app_*"], ["kitty", "steam_app_570"]));
        verify(F.appMatches(["OBS"], ["com.obsproject.Studio", "obs"]));   // any case
        verify(!F.appMatches(["obs"], ["obsidian"]));                        // whole name, not a prefix
        verify(!F.appMatches([], ["kitty"]));
    }

    // ── which mode, by itself ──
    function test_an_open_app_beats_a_schedule_and_order_decides_between_schedules() {
        const modes = F.cleanAll([
            { id: "work", name: "Work", schedule: { on: true, days: [3], from: "09:00", to: "17:00" } },
            { id: "game", name: "Game", apps: ["steam_app_*"] },
            { id: "late", name: "Late", schedule: { on: true, days: [3], from: "10:00", to: "12:00" } }
        ]);
        compare(F.auto(modes, at(11, 0), ["kitty"]), "work");
        compare(F.auto(modes, at(11, 0), ["steam_app_1"]), "game");
        compare(F.auto(modes, at(20, 0), []), "");
    }

    // ── yours and the automatic one ──
    function test_your_choice_holds_until_the_automatic_one_changes() {
        // 09:00 the schedule turns Work on
        let r = F.resolve({ manual: null, lastAuto: "" }, "work");
        compare(r.active, "work");
        // you turn it off at 10:00: it stays off while the schedule still says Work
        r = F.resolve({ manual: "off", lastAuto: r.lastAuto }, "work");
        compare(r.active, "");
        compare(r.manual, "off");
        // 17:00 the schedule ends: your "off" is done with, nothing's on
        r = F.resolve(r, "");
        compare(r.active, "");
        compare(r.manual, null);
        // the next morning it comes on again
        compare(F.resolve(r, "work").active, "work");
    }
    function test_choosing_a_mode_by_hand_wins() {
        const r = F.resolve({ manual: "game", lastAuto: "work" }, "work");
        compare(r.active, "game");
    }

    // ── notifications in Do Not Disturb ──
    function test_allowed_apps_get_through() {
        const m = mode({ dnd: true, allow: ["Slack"] });
        verify(F.letsThrough(m, "Slack"));
        verify(F.letsThrough(m, "slack"));
        verify(!F.letsThrough(m, "Discord"));
        verify(!F.letsThrough(null, "Slack"));
    }

    // ── what it changes, in words ──
    function test_a_summary_of_what_a_mode_does() {
        compare(F.summary(mode({ preset: "focus", dnd: true, allow: ["Slack"], nightLight: "on" }), { focus: "Focus" }),
            "Focus look · Do Not Disturb (Slack gets through) · Night light on");
        compare(F.summary(mode({}), {}), "Changes nothing yet");
    }
}
