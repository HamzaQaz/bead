.pragma library
// What demo mode shows instead of yours (services/Demo.qml): believable, and
// nobody's. Plain data, so tests can read it too.

const user = "you";
const host = "bead";

// the history, newest first; `ago` is minutes before demo mode came on
const notifications = [
    { appName: "Spotify", appIcon: "spotify", summary: "Now playing", body: "Slow Light · Coastal Hours", ago: 2 },
    { appName: "Discord", appIcon: "discord", summary: "#design", body: "Maya: the new island animation is so smooth 🔥", ago: 6 },
    { appName: "Discord", appIcon: "discord", summary: "#design", body: "Maya: can we ship it friday?", ago: 7 },
    { appName: "Calendar", appIcon: "org.gnome.Calendar", summary: "Standup in 10 minutes", body: "Daily sync · Meet", ago: 12 },
    { appName: "Firefox", appIcon: "firefox", summary: "Download complete", body: "hyprland-wallpapers.zip (48 MB)", ago: 25 },
    { appName: "System updates", appIcon: "system-software-update", summary: "12 updates available", body: "mesa, pipewire, hyprland and 9 more", ago: 41 },
    { appName: "Steam", appIcon: "steam", summary: "Your friend is now playing", body: "alex started playing Hades II", ago: 63 },
    { appName: "Thunderbird", appIcon: "thunderbird", summary: "Re: weekend plans", body: "Sam: sounds good, see you saturday at 7", ago: 95 }
];

// pop-ups the demo reel sends, one at a time (tools/clip.sh: `demo notify N`)
const popups = [
    { appName: "Discord", appIcon: "discord", summary: "#design", body: "Maya: the new island animation is so smooth 🔥" },
    { appName: "Calendar", appIcon: "org.gnome.Calendar", summary: "Standup in 10 minutes", body: "Daily sync · Meet" },
    { appName: "Thunderbird", appIcon: "thunderbird", summary: "Re: weekend plans", body: "Sam: sounds good, see you saturday at 7" }
];

const wifi = [
    { ssid: "Lighthouse", strength: 92, secure: true, connected: true },
    { ssid: "Lighthouse 5G", strength: 78, secure: true },
    { ssid: "Corner Café", strength: 54, secure: false },
    { ssid: "Apt 4B", strength: 31, secure: true }
];

const bluetooth = [
    { name: "Studio Headphones", icon: "audio-headphones", connected: true, battery: 80 },
    { name: "MX Keys", icon: "input-keyboard", paired: true },
    { name: "Living Room Speaker", icon: "audio-speakers", paired: true }
];

const clipboard = [
    "git push origin main",
    "https://hyprland.org",
    "#f0a6d8",
    "Meeting notes: ship the island update friday",
    "hl.dsp.exec_cmd(\"kitty\")"
];

function history(now) {
    return notifications.map((n, i) => Object.assign({}, n, {
        key: (now - n.ago * 60000) * 1000 + i,
        time: now - n.ago * 60000,
        image: "",
        urgency: 1,
        actions: [],
        demo: true
    }));
}

function popup(i, now) {
    const n = popups[((i % popups.length) + popups.length) % popups.length];
    return Object.assign({}, n, { key: now * 1000 + 999, time: now, image: "", urgency: 1, actions: [], demo: true });
}

// the dashboard
const city = "Lisbon";
const procs = [
    { pid: 4102, name: "firefox", cpu: 18, memMb: 1240 },
    { pid: 2210, name: "Hyprland", cpu: 9, memMb: 210 },
    { pid: 3318, name: "spotify", cpu: 6, memMb: 520 },
    { pid: 2876, name: "qs", cpu: 4, memMb: 380 },
    { pid: 5021, name: "code", cpu: 3, memMb: 760 }
];
const monitor = "Studio Display 27\"";
// the apps tab lists only these (by name, the ones that are installed)
const apps = ["Firefox", "kitty", "Spotify", "Discord", "Visual Studio Code", "Steam", "Thunar File Manager", "OBS Studio", "GIMP", "Blender", "Obsidian", "VLC media player"];
