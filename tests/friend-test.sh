#!/bin/bash
# make friend-test: install bead the way a friend would, on a fresh Arch
# (a throwaway podman container), then check it landed and that bead doctor
# finds nothing missing but what needs a real session (Hyprland, sound, polkit).
# Needs podman; pulls archlinux:latest and the packages (~1.5 GB the first time).
set -eu
cd "$(dirname "$0")/.."
command -v podman >/dev/null || { echo "friend-test needs podman" >&2; exit 1; }
src=$(mktemp -d); trap 'rm -rf "$src"' EXIT
# the working copy as git sees it (tracked and new files, not ignored ones),
# so it tests what you're about to commit
git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do
	if [ -e "$f" ]; then cp --parents "$f" "$src"; fi
done

chmod -R a+rX "$src"
podman run --rm -i -v "$src:/src:ro,Z" docker.io/library/archlinux:latest sh -eu <<'IN'
pacman -Syu --noconfirm --needed sudo lua >/dev/null
useradd -m friend
echo 'friend ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/friend
su friend -c 'cp -r /src ~/bead && mkdir -p ~/.config/hypr && echo "-- hyprland.lua" >~/.config/hypr/hyprland.lua'
echo "── install.sh --yes"
su friend -c 'cd ~/bead && ./install.sh --yes' </dev/null
echo "── checks"
fail=0
ok() { if su friend -c "$2" >/dev/null 2>&1; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }
ok "shell installed"            'test -f ~/.local/share/bead/shell.qml'
ok "shaders built"              'ls ~/.local/share/bead/shaders/*.qsb'
ok "bead on the path"           'test -x ~/.local/bin/bead && test -x ~/.local/bin/bead-doctor'
ok "bead.lua written"           'test -f ~/.config/hypr/bead.lua'
ok "bead.lua parses"            'luac -p ~/.config/hypr/bead.lua'
ok "hyprland.lua requires it"   'grep -q "require(\"bead\")" ~/.config/hypr/hyprland.lua'
ok "glint built"                'command -v glint || test -x ~/.local/bin/glint'
echo "── bead doctor"
su friend -c '~/.local/bin/bead-doctor --tsv' >/tmp/doc || true
# what a container can't have: a running Hyprland, sound, a polkit agent
left=$(awk -F'\t' '$1=="missing" && $2=="core" && $3!="hyprland" && $3!="pipewire" && $3!="polkit" {print "  ✗ " $4 " → " $5}' /tmp/doc)
if [ -n "$left" ]; then echo "$left"; fail=1; else echo "  ✓ nothing missing but what needs a session"; fi
awk -F'\t' '$1=="missing" && $2!="core" {print "  – " $4 " (" $2 ")"}' /tmp/doc
[ "$fail" = 0 ] && echo "friend-test: passed" || { echo "friend-test: FAILED"; exit 1; }
IN
