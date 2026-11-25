# Windows that belong to their monitor

## Problem Statement
How might bead show and move windows per monitor (each screen its own workspaces, title and windows) with one smooth, crash-free source of truth?

## Recommended Direction
A `Windows` service becomes the one place bead reads windows from: per monitor, per workspace, the focused one, stable identities, one refresh per Hyprland event, and never the per-window `.workspace` binding that crashed Quickshell 0.3.2 on Qt 6.12. The bar, title, overview and launcher all read it.

On top of that, each monitor owns a group of ten workspaces (the main monitor 1–10, the others 11–20, 21–30… left to right). Each bar shows only its own group, numbered 1–10, with one empty slot to grow into. bead offers `bead:ws<N>` / `bead:move<N>` global shortcuts that act on the focused monitor's group; the user's keybinds call them through a one-line change they make (bead never edits Hyprland config). Each bar's title shows that monitor's own window, even when focus is on the other screen.

The overview lays workspaces out by monitor, side by side as the screens sit. Dragging a window onto the other monitor's column sends it there. The launcher lists this monitor's windows first, and "Bring here" means this monitor's current workspace.

## Key Assumptions to Validate
- [ ] Opening workspace 11 from DP-1 via bead lands it on HDMI (try `focusworkspaceoncurrentmonitor`, else a runtime workspace rule)
- [ ] `HyprlandWorkspace.toplevels` stays correct through open, close, move and special workspaces (log against `hyprctl clients` for a day)
- [ ] One refresh per event is smooth (watch bar glyphs while opening and closing 5 windows quickly)

## MVP Scope
In:
- the `Windows` service
- per-monitor bars and titles
- `bead:ws` / `bead:move` shortcuts, with a Settings toggle "Workspaces per monitor"
- Super+scroll stays within the monitor's 1–10; Ctrl+Super+scroll jumps between monitors' groups
- overview columns by monitor, with drag across
- launcher "here" ordering

Out: everything below.

## Not Doing (and Why)
- Windows as dock icons in the bar: changes bead's look; not what's broken
- Editing the user's keybinds.lua: bead never edits Hyprland config; it gives the line
- Special workspaces per monitor: they're scratchpads and stay global
- Remembering which monitor an app opened on last: later, if needed

## Decided
- Super+scroll at the end of a monitor's group stays on that monitor (2026-11-24)
