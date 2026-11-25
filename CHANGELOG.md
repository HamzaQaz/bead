# Changelog

bead follows [Semantic Versioning](https://semver.org). Each release's
section is what `bead update` shows as "what's new".

## Unreleased

### Utilities
- Focus modes in the Utilities panel: tap Work, Game, Night (or your own) to
  turn one on or off, with a line saying why one is on.

### Fixes
- Bluetooth headphones that blink out for a moment (a game or a call starting)
  no longer move your sound to another device and keep it there.

## 0.5.0

### Widgets
- Keep an eye on a server, a build or a number: Settings → Widgets makes one
  from a template (Server up, Number from a URL, GitHub, Toggle, Command),
  with a preview before you add it.
- Pinned widgets sit on the resting island, four at most with "+N" for the
  rest. Click one for the dashboard's new Widgets tab, or to flip a toggle;
  right-click checks it again.
- A command that hangs shows "timed out" after 5 s and is stopped.

### Shelf
- Drop files, folders or text on the island and they're held there while you
  switch windows. Drag one into any app (Discord, a browser, a file manager)
  and it leaves the shelf, with an undo; folders stay.
- While the shelf holds something, hovering the island shows it instead of the
  media card, and the resting island shows how much is on it. Clear empties it.
- Right after a screenshot, a recording, a finished download or a copied image,
  the island offers it for a few seconds: drag it straight out, or keep it.

### Details
- Values that change while you look (the clocks, widget readings) roll to the
  new text instead of snapping, and a reading turning good or bad eases into
  its colour. Motion off turns this off too.

### Fixes
- The island no longer cuts off the Discord call faces for a moment when you
  join a call.
- The notification history test no longer depends on the time zone, so CI
  passes again.

## 0.4.0

### Claude Code questions
- Answer Claude's questions from the toast and stay where you are: the pick
  reaches the Claude terminal without switching to it.
- Type your own answer in the toast, and an "Open terminal" button when you
  do want to go there. Question toasts wait 120 s instead of 280 s.
- Old installs' copy of the Claude Code hook is replaced by a link to the
  installed one, and `bead update` rebuilds glint, so the hook stays current.

### Focus modes
- Work, Game and Night (and your own): a look preset, Do Not Disturb with
  chosen apps let through, night light and a wallpaper, switched together and
  put back exactly when the mode ends.
- On by hand (Settings, launcher, island, `qs ipc call focus`), on a schedule,
  or while an app is open. The island shows the mode and says when it changes.

### Menus
- Settings uses dropdowns for long choices (icons, presets, apps, fonts).
- One right-click menu in bead's style: text fields (cut, copy, paste), tray
  apps (their own menu), bar buttons, the island, Settings rows and modes.

### Customise
- Settings has a Customise section: Look & feel, Motion, Island, Pop-ups and
  Bar, about 75 options in all, each page with a live preview and "Try it"
  buttons that show the real island or pop-ups.
- Per-app notification rules: normal, corner only, island only, stays, or
  history only.
- Presets (bead, Minimal, Showcase, Calm, Snappy, Focus) and your own; share a
  look by copying it or saving a file, and paste one someone shared.
- Pinning a tray app animates it into the bar.
- Links (an AUR package's changes, the App Store) bring the browser forward.

### Update history and rollback
- The Updates panel has a History tab: every update pacman made (from its
  log, bead's or not), with its packages and versions.
- Undo an update, or roll back one package, from the package cache; it runs
  on the island like an update.
- The version you rolled back from is held back: bead's updates skip it
  until a newer one comes out. Release a hold from the History tab.

## 0.3.0

### App Store
- A new App Store window (Apps tab, the launcher's "install obs", or
  `qs ipc call store open`): search by name or by need ("screen recorder",
  "notes"), one result per app across the repos, Flathub and the AUR, the
  repos preferred, each with a line on why it fits.
- A store front of hand-picked apps by category, a featured banner and
  Editor's choice.
- Click an app for its details: description, screenshot, website, source
  code and bug tracker links, version, license and size.
- Installs show on the island's update card: waiting for your password,
  downloading, installing, then Open. AUR packages never open a terminal.
- AUR packages are checked before building: that they exist, their votes,
  age and maintainer, and their build files for risky commands.

### Fixes
- The welcome intro is smoother: the frame's bottom edge fills in from both
  corners to the middle, and the dark lifts evenly instead of snapping.
- The welcome card fades out gently when it closes.

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
