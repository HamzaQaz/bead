# Changelog

bead follows [Semantic Versioning](https://semver.org). Each release's
section is what `bead update` shows as "what's new".

## 0.2.0

### System updates, on the island
- Updating no longer opens a terminal. The island shows which package is
  updating, a progress bar and the log; AUR updates are listed first with
  their changes, one tap to go on. Flatpaks update too.
- bead now answers admin password prompts itself, in a redesigned password
  view on the island (your avatar, a ring while it checks, a shake when it's
  wrong).
- When an update wants a restart: restart now, tonight at 3:00, or at a time
  you pick, with a reminder 5 minutes before. Cancel it from the bar.

### Sound
- A mixer window (Sound → Advanced): every output, input and app; play on two
  outputs at once (two headphones); mic noise suppression, EQ presets and
  boost; and hearing yourself.

### Messages
- Discord: a panel with your calls, an inbox of DMs and mentions (Reply opens
  the chat), voice channels with people in them, incoming calls on the island
  with Answer and Decline, and music or project presence. It explains why it
  can't connect, and suggests Do Not Disturb when it hears nothing for hours.
- WhatsApp and Telegram (optional, Settings → Notifications): an inbox in the
  bar from their notifications, with replies where the app allows them.

### Windows and monitors
- Each monitor has its own workspaces, windows and title in the bar.

### Also
- bead greets you at login and locks when the machine logs in by itself.
- Demo mode, a new welcome, and smoother notifications.
- The media card's cover sits inside the island with a margin.

## 0.1.0

The first release: a whole desktop shell for Hyprland, built with Quickshell.

### The shell
- A screen frame and side bar in soft pills: workspaces, tray, Wi-Fi,
  Bluetooth (with pairing), sound, battery, devices and utilities panels.
- The island: a launcher (apps, windows, files, maths, clipboard, emoji,
  actions, keys, and asking Claude), live activities, media with a glow in the
  cover's colour, Discord calls, timers, and a workspace overview on Super+Tab
  (arrow keys to pick a window; f floats, p pins, x closes it).
- A dashboard with tabs for media, weather, performance, timers, wallpapers,
  apps, displays and settings, all usable from the keyboard.
- Notifications that grow out of the frame, stacked per app, with inline
  reply, Later, Do Not Disturb with a digest, and a grouped history.
- bead's own lock screen and idle handling.
- A Settings window of its own, like a desktop's settings app: Wi-Fi,
  Bluetooth, Sound, Displays, Wallpaper, Appearance, Notifications, Night
  light, Power & idle, Assistant, Keyboard shortcuts, Updates and About, with
  a search across all of them. Open it from the launcher, the dashboard, or
  `bead settings [page]`.

### Colour and look
- Tint draws the colours from your wallpaper (vibrant, muted or mono), and a
  new palette ripples out from the island.
- Six wallpapers of bead's own (glossy ribbons with a glass bead), or add yours.
- The album cover, blurred, fills the background of the media tab, the
  dashboard's player and the island's media card; the weather's sky spans the
  whole tab.
- A first-run welcome with an intro where the bead becomes the shell.

### Voice and AI (optional)
- Murmur: voice commands and dictation, offline on your GPU.
- Pearl: ask a question from the launcher with "?".
- Glint: toasts from the terminal and Claude Code.

### Installing and keeping it running
- `./install.sh` opens a graphical installer that walks you through it
  (`--tui` for the terminal one), with a clean-room test behind it
  (`make friend-test`).
- `bead doctor` checks what bead needs and says how to fix what's missing.
- `bead update` brings a git checkout up to the newest release.
- `bead uninstall` takes bead off again.
