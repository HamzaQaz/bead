import QtQuick
import QtTest
import "../services/pkgs.js" as Pkgs

// bead's installer: reading what pacman, paru and flatpak print, and ranking
// search results across them (services/pkgs.js).
TestCase {
    name: "Pkgs"

    // ── repos: expac -Ss '%r\t%n\t%v\t%m\t%d' ──
    readonly property string expac: "cachyos-extra-v3\tkitty\t0.51.1-1.1\t86337926\tA modern terminal\nextra\tkitty\t0.51.1-1\t85911902\tA modern terminal\nextra\tkitty-shell\t1.0-1\t2048\tShell integration\n"
    function test_repo_results_keep_the_first_repo_of_a_name() {
        const r = Pkgs.parseRepo(expac, ["kitty"]);
        compare(r.length, 2);
        compare(r[0].repo, "cachyos-extra-v3");
        compare(r[0].size, 86337926);
        compare(r[0].installed, true);
        compare(r[1].installed, false);
        compare(r[0].source, "repo");
    }

    // ── AUR: paru -Ssa ──
    readonly property string aur: "aur/tor-browser-bin 16.0.1-1 [+1311 ~3.86]\n    Tor Browser Bundle\naur/foo-git r12.abc-1 [+3 ~0.00] [Installed]\n    A foo\naur/old 1-1 [+0 ~0.00] [Out-of-date: 2024-01-02]\n    Old thing\n"
    function test_aur_results_with_votes_and_descriptions() {
        const r = Pkgs.parseAur(aur, []);
        compare(r.map(x => x.name), ["tor-browser-bin", "foo-git", "old"]);
        compare(r[0].votes, 1311);
        compare(r[0].desc, "Tor Browser Bundle");
        compare(r[1].installed, true);
        compare(r[2].outdated, true);
        compare(r[0].source, "aur");
    }

    // ── Flathub: a cached `flatpak remote-ls --app` list, searched here ──
    readonly property string catalog: "org.mozilla.firefox\tFirefox\t161.0\tFast, private browser\ncom.discordapp.Discord\tDiscord\t0.0.9\tChat for gamers\none.ablaze.floorp\tFloorp\t12.2\tA Firefox-based browser\n"
    function test_flathub_search_matches_name_id_and_description() {
        const r = Pkgs.searchFlathub(Pkgs.parseCatalog(catalog), "firefox", ["one.ablaze.floorp"]);
        compare(r.map(x => x.name), ["org.mozilla.firefox", "one.ablaze.floorp"]);
        compare(r[0].title, "Firefox");
        compare(r[1].installed, true);
        compare(r[0].source, "flathub");
    }

    // ── ranking across sources ──
    function test_exact_names_come_first_then_prefixes_then_the_rest() {
        const r = Pkgs.rank([
            { source: "aur", name: "firefox-nightly", title: "", desc: "" },
            { source: "repo", name: "librewolf", title: "", desc: "a firefox fork" },
            { source: "flathub", name: "org.mozilla.firefox", title: "Firefox", desc: "" },
            { source: "repo", name: "firefox", title: "", desc: "" }
        ], "firefox");
        compare(r.map(x => x.name), ["firefox", "org.mozilla.firefox", "firefox-nightly", "librewolf"]);
    }
    function test_on_a_tie_repos_beat_flathub_beat_the_aur() {
        const r = Pkgs.rank([{ source: "aur", name: "zed" }, { source: "flathub", name: "dev.zed.Zed", title: "Zed" }, { source: "repo", name: "zed" }], "zed");
        compare(r.map(x => x.source), ["repo", "flathub", "aur"]);
    }

    // ── progress lines ──
    function test_pacman_steps() {
        compare(Pkgs.progress("(2/5) installing kitty"), { step: 2, of: 5, pct: -1, text: "Installing kitty" });
        compare(Pkgs.progress("( 1/3) checking keys in keyring").text, "Checking keys in keyring");
    }
    function test_percentages_anywhere() { compare(Pkgs.progress("Installing 1/2… ████ 45%  2.1 MB/s").pct, 45); }
    function test_noise_is_not_progress() { compare(Pkgs.progress(""), null); compare(Pkgs.progress(":: Proceed with installation? [Y/n]"), null); }

    // ── updates ──
    function test_updates_from_each_source_with_restart_tags() {
        const u = Pkgs.parseUpdates("linux-cachyos 7.3.4-1 -> 7.3.5-1\nkitty 0.51-1 -> 0.52-1\n", "darkly-bin 0.5.45-1 -> 0.5.46-1\n", "org.mozilla.firefox\t161.0\n");
        compare(u.map(x => x.name), ["linux-cachyos", "kitty", "darkly-bin", "org.mozilla.firefox"]);
        compare(u.map(x => x.source), ["repo", "repo", "aur", "flathub"]);
        compare(u[0].restart, true);
        compare(u[1].restart, false);
        compare(u[1].to, "0.52-1");
    }
    function test_what_needs_a_restart() {
        for (const n of ["linux", "linux-cachyos", "linux-zen-headers", "nvidia-open-dkms", "nvidia-utils", "systemd", "glibc", "mesa", "amd-ucode", "intel-ucode"]) verify(Pkgs.restartAfter(n), n);
        for (const n of ["kitty", "linux-firmware-whence", "firefox", "systemd-ui"]) verify(!Pkgs.restartAfter(n), n);
    }

    // ── sizes ──
    function test_sizes_read_like_people_say_them() {
        compare(Pkgs.size(0), "");
        compare(Pkgs.size(2048), "2 KB");
        compare(Pkgs.size(86337926), "82 MB");
        compare(Pkgs.size(3.4 * 1024 * 1024 * 1024), "3.4 GB");
    }

    // ── the Apps tab: which package each app is, its size, sorting ──
    function test_owners_from_pacman_qo() {
        const o = Pkgs.parseOwned("/usr/share/applications/kitty.desktop is owned by kitty 0.51.1-1.1\n/usr/share/applications/org.gnome.Nautilus.desktop is owned by nautilus 49.1-1\nerror: No package owns /usr/share/applications/x.desktop\n");
        compare(o["kitty"], "kitty");
        compare(o["org.gnome.Nautilus"], "nautilus");
        compare(o["x"], undefined);
    }
    function test_sizes_as_flatpak_prints_them() {
        compare(Pkgs.bytes("1.2 GB"), Math.round(1.2 * 1024 * 1024 * 1024));
        compare(Pkgs.bytes("512.0 kB"), 512 * 1024);
        compare(Pkgs.bytes("80 MB"), 80 * 1024 * 1024);
        compare(Pkgs.bytes(""), 0);
    }
    function test_apps_sort_by_size_or_by_last_used() {
        const apps = [{ name: "B", size: 10, used: 0 }, { name: "A", size: 30, used: 5 }, { name: "C", size: 20, used: 9 }];
        compare(Pkgs.sortApps(apps, "size").map(a => a.name), ["A", "C", "B"]);
        compare(Pkgs.sortApps(apps, "used").map(a => a.name), ["C", "A", "B"]);
        compare(Pkgs.sortApps(apps, "name").map(a => a.name), ["A", "B", "C"]);
    }
    function test_last_used_reads_plainly() {
        const now = new Date(2026, 10, 24, 15, 0).getTime();
        compare(Pkgs.ago(0, now), "Never opened from bead");
        compare(Pkgs.ago(now - 5 * 60000, now), "Opened 5 min ago");
        compare(Pkgs.ago(now - 3 * 3600000, now), "Opened 3 h ago");
        compare(Pkgs.ago(now - 2 * 86400000, now), "Opened 2 days ago");
        compare(Pkgs.ago(now - 86400000, now), "Opened yesterday");
    }

    // ── popularity: pkgstats (repos), Flathub installs, AUR votes ──
    function test_popularity_files_read_as_maps() {
        compare(Pkgs.parsePop("firefox\t61.2\nkitty\t9.5\n")["kitty"], 9.5);
        compare(Pkgs.parsePop("")["x"], undefined);
    }
    function test_popularity_is_zero_to_one_per_source() {
        const pop = { repo: { firefox: 61.2 }, flathub: { "org.mozilla.firefox": 250000, "a.b.C": 10 } };
        verify(Pkgs.popularity({ source: "repo", name: "firefox" }, pop) > 0.9);    // most Arch users have it
        compare(Pkgs.popularity({ source: "repo", name: "unknown" }, pop), 0);
        compare(Pkgs.popularity({ source: "flathub", name: "org.mozilla.firefox" }, pop), 1);
        verify(Pkgs.popularity({ source: "flathub", name: "a.b.C" }, pop) < 0.25);
        verify(Pkgs.popularity({ source: "aur", name: "x", votes: 5000 }, pop) <= 0.8); // unreviewed: never quite the top
        compare(Pkgs.popularity({ source: "aur", name: "x", votes: 0 }, pop), 0);
    }
    function test_popular_apps_come_first_after_an_exact_name() {
        const pop = { repo: { "obsidian-icon-theme": 0.9, "obs-studio": 30 }, flathub: { "com.obsproject.Studio": 200000 } };
        const r = Pkgs.rank([
            { source: "repo", name: "obsidian-icon-theme" },
            { source: "aur", name: "obs-git", votes: 12 },
            { source: "flathub", name: "com.obsproject.Studio", title: "OBS Studio" },
            { source: "repo", name: "obs-studio" },
            { source: "repo", name: "obs" }
        ], "obs", pop);
        compare(r.map(x => x.name), ["obs", "com.obsproject.Studio", "obs-studio", "obsidian-icon-theme", "obs-git"]);
    }
    function test_repos_and_flathub_are_on_one_scale() {
        // a repo package 1 in 10 Arch users have is about as popular as a Flatpak with ~25k installs a month
        const pop = { repo: { kitty: 10 }, flathub: { "a.b.C": 25000 } };
        verify(Math.abs(Pkgs.popularity({ source: "repo", name: "kitty" }, pop) - Pkgs.popularity({ source: "flathub", name: "a.b.C" }, pop)) < 0.05);
    }
    function test_an_exact_repo_package_beats_an_exact_more_popular_flatpak() {
        const pop = { repo: { discord: 2 }, flathub: { "com.discordapp.Discord": 200000 } };
        const r = Pkgs.rank([{ source: "flathub", name: "com.discordapp.Discord", title: "Discord" }, { source: "repo", name: "discord" }], "discord", pop);
        compare(r[0].source, "repo");
    }
    function test_a_popular_description_match_beats_an_obscure_name_match() {
        const pop = { repo: { firefox: 61 }, flathub: {} };
        const r = Pkgs.rank([{ source: "aur", name: "browser-thing", votes: 2 }, { source: "repo", name: "firefox", desc: "Web browser" }], "browser", pop);
        compare(r[0].name, "firefox");
    }

    function test_libraries_count_for_less() {
        for (const n of ["libxmlb", "python-requests", "ruby-observer", "perl-json", "lib32-mesa", "qt6-base", "kf6-kio", "gst-plugins-good", "foo-libs", "foo-docs"]) verify(Pkgs.library(n), n);
        for (const n of ["firefox", "obs-studio", "kitty", "libreoffice-fresh", "librewolf"]) verify(!Pkgs.library(n), n);
    }
    function test_a_word_in_the_description_counts_a_letter_run_does_not() {
        const pop = { repo: { libxmlb: 88, "obs-vkcapture": 0.5 }, flathub: {} };
        const r = Pkgs.rank([
            { source: "repo", name: "libxmlb", desc: "Library to help create and query binary XML blobs" },
            { source: "repo", name: "obs-vkcapture", desc: "OBS Linux Vulkan/OpenGL game capture" }
        ], "obs", pop);
        compare(r[0].name, "obs-vkcapture");
    }
    function test_a_popular_repo_browser_is_near_the_top() {
        const pop = { repo: { firefox: 69.78, chromium: 39.65 }, flathub: { "com.brave.Browser": 160409, "ru.yandex.Browser": 7597 } };
        const r = Pkgs.rank([
            { source: "flathub", name: "ru.yandex.Browser", title: "Yandex Browser", desc: "Web browser from Yandex" },
            { source: "flathub", name: "com.brave.Browser", title: "Brave", desc: "Fast Internet, AI, Adblock" },
            { source: "repo", name: "chromium", desc: "A web browser built for speed" },
            { source: "repo", name: "firefox", desc: "Fast, Private & Safe Web Browser" }
        ], "browser", pop);
        verify(r.findIndex(x => x.name === "firefox") <= 1, JSON.stringify(r.map(x => x.name)));
        compare(r[r.length - 1].name, "ru.yandex.Browser");
    }
}
