import QtQuick
import QtTest
import "../services/store.js" as S

// The App Store (services/store.js): packages from the repos, Flathub and the
// AUR merged into one result per app (repos preferred), need-based search
// from bead's curated list, and a one-line reason for each result.
TestCase {
    name: "Store"
    function repo(name, desc, extra) { return Object.assign({ source: "repo", name: name, title: name, desc: desc || "" }, extra || {}); }
    function fh(id, title, desc) { return { source: "flathub", name: id, title: title, desc: desc || "" }; }
    function aur(name, desc, votes) { return { source: "aur", name: name, title: name, desc: desc || "", votes: votes || 0 }; }
    readonly property var curated: ({
        categories: [{ id: "media", title: "Media", icon: "movie", apps: [{ name: "obs-studio", why: "Record or stream your screen" }] }],
        needs: { "screen recorder": ["obs-studio", "kooha"], "recorder": ["obs-studio", "kooha"] }
    })

    function test_the_same_app_from_three_places_is_one_result() {
        const apps = S.merge([repo("obs-studio", "Streaming"), fh("com.obsproject.Studio", "OBS Studio", "Live streaming"), aur("obs-studio-git", "dev")]);
        compare(apps.length, 1);
        compare(apps[0].sources.map(s => s.source), ["repo", "flathub", "aur"]);
    }
    function test_the_repos_are_the_default_source() {
        const apps = S.merge([fh("org.telegram.desktop", "Telegram Desktop"), repo("telegram-desktop")]);
        compare(apps[0].best.source, "repo");
        compare(apps[0].title, "Telegram Desktop");   // the friendlier Flathub title
    }
    function test_flathub_when_the_repos_dont_have_it() {
        const apps = S.merge([aur("spotify"), fh("com.spotify.Client", "Spotify")]);
        compare(apps[0].best.source, "flathub");
    }
    function test_in_the_aur_the_plain_package_then_bin_then_git() {
        const apps = S.merge([aur("zen-browser-git"), aur("zen-browser-bin"), aur("zen-browser")]);
        compare(apps.length, 1);
        compare(apps[0].best.name, "zen-browser");
        compare(S.merge([aur("zen-browser-git"), aur("zen-browser-bin")])[0].best.name, "zen-browser-bin");
    }
    function test_flatpak_ids_match_by_their_last_part() {
        compare(S.merge([repo("firefox"), fh("org.mozilla.firefox", "Firefox")]).length, 1);
    }
    function test_different_apps_stay_apart() {
        compare(S.merge([repo("obs-studio"), repo("obsidian")]).length, 2);
    }
    function test_libraries_are_not_apps() {
        compare(S.merge([repo("libobs"), repo("python-requests"), repo("obs-studio")]).map(a => a.key), ["obsstudio"]);
    }
    function test_installed_anywhere_is_installed() {
        const apps = S.merge([repo("telegram-desktop"), Object.assign(fh("org.telegram.desktop", "Telegram Desktop"), { installed: true })]);
        verify(apps[0].installed);
        compare(apps[0].installedFrom, "flathub");
    }
    function test_a_need_names_the_curated_apps() {
        compare(S.needs("screen recorder", curated), ["obs-studio", "kooha"]);
        compare(S.needs("Recorder ", curated), ["obs-studio", "kooha"]);
        compare(S.needs("obs", curated), []);
    }
    function test_curated_answers_to_a_need_come_first() {
        const apps = S.merge([repo("audacity", "Record audio"), repo("kooha", "Screen recorder"), repo("obs-studio", "Streaming")]);
        const out = S.order(apps, "recorder", curated);
        compare(out.map(a => a.key), ["obsstudio", "kooha", "audacity"]);
    }
    function test_the_reason_is_the_curated_one_else_the_summary() {
        const apps = S.merge([repo("obs-studio", "Free software for live streaming. And more."), repo("kooha", "Elegantly record your screen. Simple.")]);
        compare(S.reason(apps[0], curated), "Record or stream your screen");
        compare(S.reason(apps[1], curated), "Elegantly record your screen");
    }
    function test_the_store_front_lists_categories() {
        const front = S.front(curated);
        compare(front[0].title, "Media");
        compare(front[0].apps[0].name, "obs-studio");
    }
    function test_the_install_command_for_each_source() {
        compare(S.installArgs({ source: "repo", name: "kooha" }), ["install", "repo", "kooha"]);
        compare(S.installArgs({ source: "flathub", name: "com.spotify.Client" }), ["install", "flathub", "com.spotify.Client"]);
        compare(S.installArgs({ source: "aur", name: "zen-browser-bin" }), ["install", "aur", "zen-browser-bin"]);
    }
    function test_a_launcher_install_query() {
        compare(S.launcherQuery("install obs"), "obs");
        compare(S.launcherQuery("Install  screen recorder"), "screen recorder");
        compare(S.launcherQuery("installer"), "");
        compare(S.launcherQuery("obs"), "");
    }

    // ── an install's progress, line by line (bead-sysupdate install …) ──
    function run(lines) { let st = S.installStart(); for (const l of lines) st = S.installStep(st, l); return st; }
    function test_an_install_starts_waiting_for_the_password() {
        compare(S.installStart().phase, "auth");
        compare(S.installFraction(S.installStart()), 0);
    }
    function test_pacman_downloads_then_installs_each_package() {
        let st = run(["Packages (2) kooha-2.3-1  gst-plugin-rs-0.13-1"]);
        compare(st.n, 2);
        compare(st.phase, "download");
        st = run(["Packages (2) kooha-2.3-1  gst-plugin-rs-0.13-1", " kooha-2.3-1-x86_64 downloading..."]);
        compare(st.dl, 1);
        compare(S.installFraction(st), 0.25);
        st = run(["Packages (2) a-1-1 b-1-1", " a-1-1-x86_64 downloading...", " b-1-1-x86_64 downloading...", "installing a..."]);
        compare(st.phase, "install");
        compare(S.installFraction(st), 0.75);
    }
    function test_flatpak_says_its_percent() {
        const st = run(["Installing 1/2… 45%  2.1 MB/s"]);
        compare(st.phase, "download");
        compare(S.installFraction(st), 0.45);
    }
    function test_an_aur_build_is_its_own_phase() {
        compare(run(["==> Making package: zen-browser-bin 1.0-1"]).phase, "build");
    }
    function test_errors_are_kept() {
        compare(run(["error: target not found: nope"]).error, "target not found: nope");
    }
    function test_done_and_failed() {
        compare(run(["@@done"]).phase, "done");
        compare(S.installFraction(run(["@@done"])), 1);
        compare(run(["@@fail install 1"]).phase, "failed");
    }

    // the shipped list (data/apps.json) is well formed
    function test_the_curated_list_is_well_formed() {
        const x = new XMLHttpRequest();
        x.open("GET", Qt.resolvedUrl("../data/apps.json"), false);
        x.send();
        const c = JSON.parse(x.responseText);
        verify(c.categories.length >= 4);
        for (const cat of c.categories) {
            verify(cat.id && cat.title && cat.icon, cat.id);
            for (const a of cat.apps) verify(a.name && a.title && a.why && a.why.length < 60, a.name);
        }
        for (const k in c.needs) { compare(k, k.toLowerCase().trim()); verify(c.needs[k].length > 0, k); }
        // editor's choice: a few picks from the categories, each with a note
        const picks = [];
        for (const cat of c.categories) for (const a of cat.apps) picks.push(a.name);
        verify(c.editors.length >= 3 && c.editors.length <= 6);
        for (const e of c.editors) { verify(picks.indexOf(e.name) >= 0, e.name + " is a pick"); verify(e.note && e.note.length < 110, e.name); }
    }

    function test_a_picks_title_beats_its_package_name() {
        const c = { categories: [{ id: "m", title: "M", icon: "x", apps: [{ name: "obs-studio", title: "OBS Studio", why: "x" }] }], needs: {} };
        compare(S.title(S.merge([repo("obs-studio")])[0], c), "OBS Studio");
        compare(S.title(S.merge([repo("kooha")])[0], c), "kooha");
    }

    function test_editors_choice_resolves_to_apps() {
        const c = { categories: [{ id: "m", title: "M", icon: "x", apps: [{ name: "obs-studio", title: "OBS Studio", why: "x" }] }], needs: {},
                    editors: [{ name: "obs-studio", note: "The one to get" }, { name: "missing", note: "Not here" }] };
        const apps = S.merge([repo("obs-studio")]);
        const ed = S.editors(apps, c);
        compare(ed.length, 1);
        compare(ed[0].app.key, "obsstudio");
        compare(ed[0].note, "The one to get");
    }

    // ── an app's details sheet: links and a readable description ──
    function test_details_from_flathub_and_the_repos() {
        const d = S.details({
            repo: { url: "https://obsproject.com", license: "GPL-2.0-or-later", version: "33.0.3-1", size: 28107352 },
            flathub: { description: "<p>OBS is free.</p><ul><li>Record</li><li>Stream</li></ul>", homepage: "https://obsproject.com", vcs: "https://github.com/obsproject/obs-studio", bugtracker: "https://github.com/obsproject/obs-studio/issues", developer: "OBS Project", id: "com.obsproject.Studio" }
        }, "Short summary");
        compare(d.description, "OBS is free.\n\n• Record\n• Stream");
        compare(d.links.map(l => l.label), ["Website", "Source code", "Report a bug", "Flathub"]);
        compare(d.links[1].url, "https://github.com/obsproject/obs-studio");
        compare(d.developer, "OBS Project");
        verify(d.facts.some(f => f.label === "License" && f.value === "GPL-2.0-or-later"));
    }
    function test_a_github_homepage_is_the_source_code() {
        const d = S.details({ repo: { url: "https://github.com/dec05eba/gpu-screen-recorder", license: "GPL3" } }, "Fast recorder");
        compare(d.links.map(l => l.label), ["Source code"]);
        compare(d.description, "Fast recorder");
    }
    function test_the_aur_page_and_its_facts() {
        const d = S.details({ aur: { name: "zen-browser-bin", url: "https://zen-browser.app", votes: 345, maintainer: "someone", updated: 1795000000 } }, "Zen");
        compare(d.links.map(l => l.label), ["Website", "AUR page"]);
        compare(d.links[1].url, "https://aur.archlinux.org/packages/zen-browser-bin");
        verify(d.facts.some(f => f.label === "Votes" && f.value === "345"));
    }
    function test_duplicate_links_are_dropped() {
        const d = S.details({ repo: { url: "https://x.org/" }, flathub: { homepage: "https://x.org", id: "org.x.X" } }, "");
        compare(d.links.map(l => l.label), ["Website", "Flathub"]);
    }

    // a rollback (pacman -U from the cache): nothing to download, downgrades
    function test_a_rollback_from_the_cache_fills_the_bar_with_its_downgrades() {
        let st = S.installStart();
        for (const l of ["loading packages...", "Packages (2) mesa-3:26.2.6-1  zlib-1.3-1", "downgrading mesa...", "downgrading zlib..."]) st = S.installStep(st, l);
        compare(st.phase, "install");
        compare(st.i, 2);
        compare(S.installFraction(st), 1);
    }
    function test_downloads_still_count_as_half_when_there_are_some() {
        let st = S.installStart();
        for (const l of ["Packages (1) obs-studio-33-1", " obs-studio-33-1-x86_64 downloading...", "installing obs-studio..."]) st = S.installStep(st, l);
        compare(S.installFraction(st), 1);
        st = S.installStep(S.installStep(S.installStart(), "Packages (2) a-1-1 b-1-1"), " a-1-1-x86_64 downloading...");
        compare(S.installFraction(st), 0.25);
    }
}
