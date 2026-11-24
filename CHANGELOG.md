# Changelog

bead follows [Semantic Versioning](https://semver.org). Each release's
section is what `bead update` shows as "what's new".

## 0.1.0

The first release: a whole desktop shell for Hyprland, built with Quickshell.

### The shell
- A screen frame and side bar in soft pills: workspaces, tray, Wi-Fi,
  Bluetooth (with pairing), sound, battery, devices and utilities panels.
- The island: a launcher (apps, windows, files, maths, clipboard, emoji,
  actions, keys, and asking Claude), live activities, media with a glow in the
  cover's colour, Discord calls, timers, and a workspace overview on Super+Tab.
- A dashboard with tabs for media, weather, performance, timers, wallpapers,
  apps, displays and settings, all usable from the keyboard.
- Notifications that grow out of the frame, stacked per app, with inline
  reply, Later, Do Not Disturb with a digest, and a grouped history.
- bead's own lock screen and idle handling.

### Colour and look
- Tint draws the colours from your wallpaper (vibrant, muted or mono), and a
  new palette ripples out from the island.
- Six wallpapers of bead's own, or add yours.
- A first-run welcome with an intro where the bead becomes the shell.

### Voice and AI (optional)
- Murmur: voice commands and dictation, offline on your GPU.
- Pearl: ask a question from the launcher with "?".
- Glint: toasts from the terminal and Claude Code.

### Installing and keeping it running
- `./install.sh` (strand) installs everything, with a clean-room test behind
  it (`make friend-test`).
- `bead doctor` checks what bead needs and says how to fix what's missing.
- `bead update` brings a git checkout up to the newest release.
- `bead uninstall` takes bead off again.
