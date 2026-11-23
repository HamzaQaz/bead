//@ pragma UseQApplication
// bead: a desktop shell built from sileo-style pills, replacing Caelestia one
// piece at a time. Colours come from Caelestia's wallpaper scheme.
import Quickshell
import qs.modules.notifications

ShellRoot {
    // Live reloads break module imports and icon loading mid-session, and would
    // drop the notification name; `make install` restarts bead instead.
    settings.watchFiles: false

    Notifications {}
}
