# Launcher actions and the colour ripple

## Problem Statement
How might we let you act on a launcher result without leaving the keyboard, and make a
wallpaper change feel like bead reacting rather than snapping?

## Recommended Direction
Build launcher actions first. Tab on the selected row slides it aside into a short list
of what can be done with it: an app (open on a workspace, quit), a window (bring here,
move to a workspace, close), a file (open its folder, copy its path). Escape or
Shift+Tab goes back. The selected row shows a small "Tab" hint so it can be found.

Then the ripple: when the palette changes, Theme fades from the old colours to the new
in one place, surfaces start their fade a moment later the further they are from the
island, and a band of light crosses the island and the bar.

## Key Assumptions to Validate
- [ ] Tab as "actions" doesn't break a habit. Test: use it for a week; Down still moves.
- [ ] Fading all colours through one function stays smooth. Test: measure frame times
      during a wallpaper change before building the stagger.
- [ ] Three or four actions per kind are enough. Test: note any you reach for and miss.

## MVP Scope
In: actions for apps, windows and files; Tab / Shift+Tab / Escape; the hint; the logic
that lists actions for a result, written test-first with qmltestrunner.

Then: a global colour fade; the stagger and the sweep only if the fade is smooth.

Out: actions for clipboard, emoji and calculator rows; user-defined actions.

## Not Doing (and Why)
- **The digest card:** the digest exists as a toast; a card adds looks, not function.
- **A per-pixel wave on every window:** a shader per surface for a one-second effect.
- **A "Today" tab, workspace peek, empty-state pass:** not picked this round.

## Open Questions
- Does "quit" close every window of the app, or ask first when there are several?
- Which workspaces does "open on workspace N" offer: all, or only 1 to 5?
