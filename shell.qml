//@ pragma UseQApplication
// bead: a desktop shell built from sileo-style pills, replacing Caelestia one
// piece at a time. Colours come from Caelestia's wallpaper scheme.
import Quickshell
import qs.modules.dashboard
import qs.modules.notifications
import qs.modules.osd

ShellRoot {
    // Live reloads break module imports and icon loading mid-session, and would
    // drop the notification name; `make install` restarts bead instead.
    settings.watchFiles: false

    Notifications {}
    History {}
    Osd {}
    Dashboard {}
}
