# Arrange

## Problem Statement
How might we let someone arrange windows and screens directly in bead, without
opening their Hyprland config?

## Recommended Direction
One view, built in three steps that each ship on their own:

1. **Overview you can act in.** Drag a window thumbnail onto another
   workspace (or monitor) to move it there. Keys on the selected window:
   `f` float, `x` close, `p` pin.
2. **Displays tab.** A to-scale map of the monitors: drag to arrange; per
   monitor resolution, refresh rate, scale and rotation. Every change asks
   "Keep these settings?" and reverts by itself after 15 s. Saving writes a
   bead-owned Lua file that the user's config `require`s once (added by the
   user, with consent), loaded after their own monitor settings.
3. **Arrange.** Merge the two: windows drawn inside the monitor map.

Hyprland 0.57 here uses a Lua config; the monitors are hand-tuned in
`~/.config/caelestia/hypr-user.lua` (portrait HDMI-A-1, pinned cm/sdr
values). bead never edits that file.

## Key Assumptions to Validate
- [ ] Monitors can still be changed at runtime under the Lua config
      (`hyprctl keyword monitor` or an eval route) — test on a harmless
      setting, with the user's OK
- [ ] A bead-owned Lua file required after `hypr-user.lua` overrides only
      what bead sets
- [ ] The 15 s revert rescues a bad mode — test on HDMI-A-1 only

## MVP Scope
Step 1, plus a Displays tab with refresh rate, scale, position by drag and
the revert timer.

## Not Doing (and Why)
- Snap zones — they fight Hyprland's tiling
- Remembering exact window positions in layouts — tiling moves them anyway
- A window-rule editor — niche; config syntax is fine for the few who need it
- HDR, colour management, mirroring — the user's cm/sdr values stay theirs
- Editing the user's own monitor file — bead writes only its own file

## Open Questions
- Does step 3 replace Super+Tab's Overview, or get its own shortcut?
