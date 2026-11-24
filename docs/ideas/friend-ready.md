# Friend-ready

## Problem Statement
How might we make bead install and work on a friend's Arch machine on the
first try, with nothing from its author?

## Recommended Direction
Four parts, in order:

1. **`bead doctor`** — checks every assumption bead makes (Hyprland and its
   Lua config, Quickshell, fonts, a polkit agent, PipeWire, BlueZ, a
   terminal, xdg-open, checkupdates, each optional part's needs) and prints
   each failure with a one-line fix. The same checks show as a card in
   Settings.
2. **No Caelestia** — bead never reads Caelestia's files. Colours come from
   Tint, or a built-in palette until Tint has run; the wallpaper from bead's
   own state, or bead's default.
3. **Clean-room test** — `make friend-test` builds an Arch container
   (podman), runs `install.sh --yes` as a fresh user, then checks files
   landed, configs parse, everything lints, and `bead doctor` reports
   nothing missing but "Hyprland not running".
4. **Welcome check** — a last step before "Done" runs the doctor, lists
   what's missing with Install for each package, or says "All set".

## Key Assumptions to Validate
- [ ] The doctor's list is complete — grep every external command bead runs
      and make sure each is checked or optional
- [ ] bead looks right with no Caelestia files — run with them hidden
- [ ] archlinux:latest + base-devel is close enough to a friend's machine

## MVP Scope
All four; the doctor covers required pieces plus each optional part's needs.

## Not Doing (and Why)
- AUR package / release — after this passes; publishing is public
- `bead uninstall` — worth doing, separately
- Non-Arch distributions — strand is pacman-only by design
- Running the shell in CI — no GPU or Wayland in a container

## Open Questions
- Doctor fixes: packages only (pkexec), never config edits — those are
  strand's job.
