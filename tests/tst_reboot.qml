import QtQuick
import QtTest
import "../services/reboot.js" as R

// Scheduling a restart after an update (services/reboot.js): the next time a
// clock time comes round, how it reads, and the systemd calendar string.
TestCase {
    name: "Reboot"
    readonly property var evening: new Date(2026, 10, 24, 22, 30)   // Tue 24 Nov, 22:30

    function test_a_later_time_today_is_today() {
        const t = R.next(23, 15, evening);
        compare(t.getDate(), 24);
        compare(t.getHours(), 23);
        compare(t.getMinutes(), 15);
    }
    function test_a_time_already_gone_is_tomorrow() {
        const t = R.next(3, 0, evening);
        compare(t.getDate(), 25);
        compare(t.getHours(), 3);
    }
    function test_the_same_minute_counts_as_gone() {
        compare(R.next(22, 30, evening).getDate(), 25);
    }
    function test_late_at_night_reads_as_tonight() {
        compare(R.label(new Date(2026, 10, 25, 3, 0), evening), "Tonight at 3:00");
        compare(R.label(new Date(2026, 10, 24, 23, 15), evening), "Tonight at 23:15");
    }
    function test_tomorrow_daytime_reads_as_tomorrow() {
        compare(R.label(new Date(2026, 10, 25, 9, 5), evening), "Tomorrow at 9:05");
    }
    function test_later_today_reads_as_today() {
        const morning = new Date(2026, 10, 24, 9, 0);
        compare(R.label(new Date(2026, 10, 24, 14, 0), morning), "Today at 14:00");
    }
    function test_soon_reads_in_minutes() {
        compare(R.label(new Date(2026, 10, 24, 22, 45), evening), "In 15 minutes");
    }
    function test_the_calendar_string_for_systemd() {
        compare(R.calendar(new Date(2026, 10, 25, 3, 0)), "2026-11-25 03:00:00");
    }
    function test_stepping_a_custom_time_wraps_round_the_clock() {
        compare(R.step(23, 45, 15), [0, 0]);
        compare(R.step(0, 0, -15), [23, 45]);
        compare(R.step(9, 10, 15), [9, 25]);
    }
}
