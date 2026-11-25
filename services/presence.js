.pragma library

// What Discord presence may say you're working on (services/Discord.qml):
// a project name from an editor's or a terminal's title, else "". Never a
// file or a path. Tested in tests/tst_presence.qml.

const terminals = /^(kitty|foot|alacritty|ghostty|wezterm|org\.wezfurlong\.wezterm|konsole|xterm|com\.mitchellh\.ghostty)$/i;

function project(appId, title) {
    const id = (appId || "").toLowerCase(), t = title || "";
    // VS Code and friends: "file - folder - Visual Studio Code", or "folder - VSCodium"
    if (/^(code|code-oss|codium|vscodium|cursor)$/.test(id)) {
        const parts = t.split(" - ");
        return parts.length >= 2 ? parts[parts.length - 2].trim() : "";
    }
    // Zed: "project — path"
    if (id.includes("zed")) return t.split(" — ")[0].trim();
    if (terminals.test(id)) {
        const m = /~?\/?(?:home\/[^/]+\/)?Projects\/([^/\s]+)/.exec(t);
        return m ? m[1] : "";
    }
    return "";
}
