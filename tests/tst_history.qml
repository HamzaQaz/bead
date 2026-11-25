import QtQuick
import QtTest
import "../services/history.js" as H

// Update history and rollback (services/history.js): pacman's log read into
// one entry per transaction, the cached package files an undo needs, and
// held versions that bead's updates skip.
TestCase {
    name: "History"

    readonly property string log: [
        "[2026-11-20T09:00:00-0600] [PACMAN] Running 'pacman -Syu --noconfirm --noprogressbar'",
        "[2026-11-20T09:00:05-0600] [ALPM] transaction started",
        "[2026-11-20T09:00:06-0600] [ALPM] upgraded mesa (3:26.2.6-1 -> 3:26.3.1-5)",
        "[2026-11-20T09:00:06-0600] [ALPM] upgraded linux-cachyos (6.17.1-1 -> 6.17.2-1)",
        "[2026-11-20T09:00:07-0600] [ALPM] installed libnew (1.0-1)",
        "[2026-11-20T09:00:07-0600] [ALPM] removed oldthing (2.0-1)",
        "[2026-11-20T09:00:08-0600] [ALPM-SCRIPTLET] some output",
        "[2026-11-20T09:00:09-0600] [ALPM] transaction completed",
        "[2026-11-21T10:00:00-0600] [PACMAN] Running '/usr/bin/pacman -S --needed --noconfirm obs-studio'",
        "[2026-11-21T10:00:01-0600] [ALPM] transaction started",
        "[2026-11-21T10:00:02-0600] [ALPM] installed obs-studio (33.0.3-1)",
        "[2026-11-21T10:00:03-0600] [ALPM] transaction completed",
        "[2026-11-22T11:00:00-0600] [PACMAN] Running 'pacman -Syu'",
        "[2026-11-22T11:00:01-0600] [ALPM] transaction started",
        "[2026-11-22T11:00:02-0600] [ALPM] transaction completed",
        "[2026-11-23T12:00:00-0600] [PACMAN] Running 'pacman -U /var/cache/pacman/pkg/mesa-3:26.2.6-1-x86_64.pkg.tar.zst'",
        "[2026-11-23T12:00:01-0600] [ALPM] transaction started",
        "[2026-11-23T12:00:02-0600] [ALPM] downgraded mesa (3:26.3.1-5 -> 3:26.2.6-1)",
        "[2026-11-23T12:00:03-0600] [ALPM] transaction completed"
    ].join("\n")

    // ── reading the log ──
    function test_one_entry_per_transaction_newest_first_empty_ones_skipped() {
        const t = H.parse(log);
        compare(t.length, 3);
        compare(t[0].changes[0].op, "downgraded");
        compare(t[2].changes.length, 4);
        compare(t[2].time, "2026-11-20T09:00:06-0600");
    }
    function test_each_change_has_its_versions() {
        const c = H.parse(log)[2].changes;
        compare(c[0], { op: "upgraded", name: "mesa", from: "3:26.2.6-1", to: "3:26.3.1-5" });
        compare(c[2], { op: "installed", name: "libnew", from: "", to: "1.0-1" });
        compare(c[3], { op: "removed", name: "oldthing", from: "2.0-1", to: "" });
    }
    function test_what_ran_names_the_entry() {
        const t = H.parse(log);
        compare(H.label(t[2]), "System update");
        compare(H.label(t[1]), "Installed obs-studio");
        compare(H.label(t[0]), "Rolled back mesa");
    }
    function test_an_aur_build_installed_with_pacman_U_is_an_update_not_a_rollback() {
        const t = H.parse("[2026-11-24T23:07:26-0600] [PACMAN] Running 'pacman --upgrade --noconfirm -- /home/u/.cache/paru/clone/darkly-bin/darkly-bin-0.5.46-1-x86_64.pkg.tar.zst'\n"
            + "[2026-11-24T23:07:27-0600] [ALPM] transaction started\n[2026-11-24T23:07:27-0600] [ALPM] upgraded darkly-bin (0.5.45-1 -> 0.5.46-1)\n[2026-11-24T23:07:28-0600] [ALPM] transaction completed");
        compare(H.label(t[0]), "Updated darkly-bin");
        const u = H.parse("[2026-11-24T23:07:26-0600] [PACMAN] Running 'pacman -U /x/a-2-1-any.pkg.tar.zst'\n[2026-11-24T23:07:27-0600] [ALPM] transaction started\n[2026-11-24T23:07:27-0600] [ALPM] installed a (2-1)");
        compare(H.label(u[0]), "Installed a");
    }
    function test_an_unfinished_transaction_still_counts() {
        const t = H.parse("[2026-11-20T09:00:05-0600] [ALPM] transaction started\n[2026-11-20T09:00:06-0600] [ALPM] upgraded a (1-1 -> 2-1)");
        compare(t.length, 1);
        compare(t[0].changes[0].name, "a");
    }

    // ── the cache ──
    readonly property var files: [
        "/var/cache/pacman/pkg/mesa-3:26.2.6-1-x86_64_v3.pkg.tar.zst",
        "/var/cache/pacman/pkg/mesa-3:26.2.6-1-x86_64_v3.pkg.tar.zst.sig",
        "/var/cache/pacman/pkg/mesa-utils-3:26.2.6-1-x86_64.pkg.tar.zst",
        "/var/cache/pacman/pkg/oldthing-2.0-1-any.pkg.tar.xz",
        "/home/u/.cache/paru/clone/darkly-bin/darkly-bin-0.5.45-1-x86_64.pkg.tar.zst"
    ]
    function test_a_version_is_found_in_the_cache_by_exact_name() {
        compare(H.cached("mesa", "3:26.2.6-1", files), "/var/cache/pacman/pkg/mesa-3:26.2.6-1-x86_64_v3.pkg.tar.zst");
        compare(H.cached("mesa", "3:26.3.1-5", files), "");
        compare(H.cached("darkly-bin", "0.5.45-1", files), "/home/u/.cache/paru/clone/darkly-bin/darkly-bin-0.5.45-1-x86_64.pkg.tar.zst");
        // "mesa-utils" is its own package, not "mesa"
        compare(H.cached("mesa-utils", "3:26.2.6-1", files), "/var/cache/pacman/pkg/mesa-utils-3:26.2.6-1-x86_64.pkg.tar.zst");
        compare(H.cached("mesa", "3:26.2.6-1", files.slice(2)), "");
    }

    // ── undoing an update ──
    function test_undo_puts_back_old_versions_and_removed_packages() {
        const t = H.parse(log)[2];
        const p = H.undo(t, files, { "mesa": "3:26.3.1-5", "linux-cachyos": "6.17.2-1", "libnew": "1.0-1" });
        compare(p.files, ["/var/cache/pacman/pkg/mesa-3:26.2.6-1-x86_64_v3.pkg.tar.zst", "/var/cache/pacman/pkg/oldthing-2.0-1-any.pkg.tar.xz"]);
        compare(p.missing, ["linux-cachyos"]);   // its old version isn't cached
        compare(p.kept, ["libnew"]);             // new in that update: left installed
        compare(p.holds, [{ name: "mesa", version: "3:26.3.1-5" }]);   // what it's rolled back from
    }
    function test_a_package_changed_since_is_left_alone() {
        const t = H.parse(log)[2];
        const p = H.undo(t, files, { "mesa": "3:26.4.0-1", "linux-cachyos": "6.17.2-1" });
        compare(p.files.indexOf("/var/cache/pacman/pkg/mesa-3:26.2.6-1-x86_64_v3.pkg.tar.zst"), -1);
        compare(p.changed, ["mesa"]);
    }
    function test_undo_of_one_package() {
        const t = H.parse(log)[2];
        const p = H.undo(t, files, { "mesa": "3:26.3.1-5" }, "mesa");
        compare(p.files, ["/var/cache/pacman/pkg/mesa-3:26.2.6-1-x86_64_v3.pkg.tar.zst"]);
        compare(p.holds, [{ name: "mesa", version: "3:26.3.1-5" }]);
    }

    // ── holds: the version you rolled back from is skipped, a newer one isn't ──
    function test_a_held_version_is_skipped_until_a_newer_one() {
        const holds = [{ name: "mesa", version: "3:26.3.1-5" }];
        compare(H.ignored(holds, [{ name: "mesa", to: "3:26.3.1-5" }, { name: "zlib", to: "1.3-2" }]), ["mesa"]);
        compare(H.ignored(holds, [{ name: "mesa", to: "3:26.3.2-1" }]), []);
    }
    function test_holds_drop_once_the_next_version_is_out() {
        const holds = [{ name: "mesa", version: "3:26.3.1-5" }, { name: "zlib", version: "1.3-2" }];
        compare(H.keepHolds(holds, [{ name: "mesa", to: "3:26.3.2-1" }, { name: "zlib", to: "1.3-2" }]), [{ name: "zlib", version: "1.3-2" }]);
        // nothing waiting for it: still held
        compare(H.keepHolds(holds, []).length, 2);
    }

    // ── when, in words (pacman's log times carry their offset: -0600) ──
    function test_when_reads_today_yesterday_or_a_date() {
        const now = new Date("2026-11-25T10:00:00-06:00");
        compare(H.when("2026-11-25T00:56:05-0600", now), "Today " + Qt.formatTime(new Date("2026-11-25T00:56:05-06:00"), "HH:mm"));
        compare(H.when("2026-11-24T23:11:58-0600", now), "Yesterday " + Qt.formatTime(new Date("2026-11-24T23:11:58-06:00"), "HH:mm"));
        compare(H.when("2026-11-20T09:00:06-0600", now), Qt.formatDate(new Date("2026-11-20T09:00:06-06:00"), "ddd d MMM"));
    }
}
