# App Store

## Problem Statement
How might we make getting a new app in bead feel like an app store: find the
right app by what it does, and see it install, without knowing which of the
repos, the AUR or Flathub it lives in?

## Recommended Direction
A window of its own ("App Store"), like the mixer and Settings. Search takes
a name or a need ("screen recorder", "notes") and shows **one result per app**
(the repo, AUR and Flathub packages of the same app merged, the best source
picked, the others one tap away), each with a one-line reason it fits. With an
empty search it's a store front: curated categories (Editors, Gaming, Media,
Chat, Creative, Utilities) of a few good picks each.

Installing uses the island's update card, not a small chip: the app's icon,
Downloading → Installing with a bar and percent, then "Telegram installed ·
Open". The AUR doesn't open a terminal: its build files are shown first and
confirmed with one tap, as with updates. Passwords go through bead's own
polkit prompt.

The launcher gets a shortcut: "install obs" opens the window already searched.

## Key Assumptions to Validate
- [ ] Need-based search works from local data: Flathub's appstream (names,
      summaries, keywords, categories) plus pacman descriptions and a small
      bead-curated synonym list ("recorder" → screen recording). Test: 20
      everyday searches find the expected app in the top 3.
- [ ] Merging packages into one app is reliable: match by desktop id / app id
      / normalised name ("obs-studio", "com.obsproject.Studio"). Test against
      the 50 most popular apps.
- [ ] Progress can be read for each source: pacman (download, then
      "installing x"), flatpak (percent lines), paru (download/build stages),
      reusing services/sysupdate.js's parser.
- [ ] A curated list stays small enough to maintain (~6 categories × ~6 apps,
      in data/apps.json).

## MVP Scope
In:
- StoreWindow: search, one-result-per-app list with icon, title, the reason,
  source badge and size; Install / Open / Remove.
- Empty search: curated categories (data/apps.json).
- Installs through a runner like bead-sysupdate, shown on the island's update
  card (icon, stage, progress, result with Open), AUR review step included.
- Launcher "install <query>" → the window, searched.
- Tests first for the pure parts: merging, ranking with reasons, progress
  parsing, the curated list's shape.

Out: everything in Not Doing.

## Not Doing (and Why)
- Recommendations from what you've installed: guessing from your history is
  noisy; search-based reasons and curated picks cover discovery.
- Ratings and reviews: no trustworthy local source, and it'd need a server.
- Screenshots: heavy to fetch and cache; later, from Flathub's appstream.
- Managing installed apps beyond Install / Open / Remove: the dashboard's Apps
  tab already lists them.
- Queueing several installs at once: one at a time, as today.

## Open Questions
- Should Flathub be preferred over the repos when both have an app (sandboxed,
  newer) or the repos (smaller, native)? Default: repos, Flatpak for apps only
  on Flathub.
