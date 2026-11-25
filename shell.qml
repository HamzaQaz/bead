//@ pragma UseQApplication
// bead: a desktop shell for Hyprland built from sileo-style pills. Colours
// come from the wallpaper (Tint, bin/bead-tint).
import Quickshell
import qs.modules.background
import qs.modules.bar
import qs.modules.island
import qs.modules.lock
import qs.modules.mixer
import qs.modules.notifications
import qs.modules.settings
import qs.modules.welcome
import qs.services

ShellRoot {
    // Live reloads break module imports and icon loading mid-session, and would
    // drop the notification name; `make install` restarts bead instead.
    settings.watchFiles: false

    Notifications {}
    History {}
    Bar {}
    Island {}
    LockScreen {}
    Background {}
    Welcome {}
    // the Settings window, made when it opens (services/SettingsApp.qml)
    LazyLoader { active: SettingsApp.open; SettingsWindow {} }
    LazyLoader { active: AudioFx.open; MixerWindow {} }
    readonly property string wallKind: Wallpaper.kind  // starts the Wallpaper singleton (restores the choice)

    // services that must run without anything showing them
    readonly property bool idleOn: Idle.active
    readonly property var specialApps: Specials.apps  // registers the special-workspace shortcuts
    // the launcher's ; and : modes open instantly: their data is loaded up front
    readonly property int clipWarm: Clipboard.entries.length
    readonly property int emojiWarm: Emoji.all.length
    // the lock screen shows the weather straight away, even right after a restart
    readonly property bool weatherWarm: Weather.ready
    readonly property int updatesWarm: Updates.count // starts the update checks
    readonly property string releaseWarm: Release.version // bead's own version: "what's new" and the daily release check
    readonly property bool warmScreen: NightLight.warm // starts the night light's schedule
    readonly property bool gaming: GameMode.active // starts watching for games
    readonly property string clipSeen: ClipHints.last // starts reading copies
}
