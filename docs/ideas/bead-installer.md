# bead's installer

## Problem Statement
How might we find, install, update and remove apps from bead without a terminal?

## Recommended Direction
A `+` mode in the launcher searches the repos, Flathub and the AUR together;
each result shows its source (Repo, Flathub, AUR · unreviewed), size and
whether it's installed. Return installs; progress shows in the island as a
live activity, then a notification with Open. Tab on an app row offers
Uninstall. A dot in the bar says updates are waiting; its panel lists them
with one Update button and tags kernel or driver updates "restart after". A
dashboard Apps tab lists installed apps by size and last use, plus updates.

Passwords never pass through bead: repo installs use `pkexec`, so the existing
polkit agent asks; Flatpaks install per user (`--user`) and need none. AUR
installs always show the PKGBUILD first and need an explicit "Build it"; paru
runs with pkexec for its root steps and never skips review.

## Key Assumptions to Validate
- [ ] paru's `--sudo pkexec` works without a terminal: try a tiny AUR package
- [ ] Searching all three sources returns in under a second: time each; cache Flathub
- [ ] Progress can be parsed from pacman's and flatpak's output: capture it, test the parser

## MVP Scope
In: `+` search and install, uninstall from the app row, the updates dot and
panel, the dashboard Apps tab.

## Not Doing (and Why)
- bead's own password prompt: needs Quickshell polkit support, unverified
- Ratings and reviews: no good source, little value
- Scheduled automatic updates: updates should be a choice
- Downgrades: rare, risky

## Open Questions
- "Last used" comes from the launcher's own history (assumed yes)
