#!/bin/sh
# The friend test's inside: run as root on a fresh Arch (a podman container from
# tests/friend-test.sh, or a CI job), with bead's working copy at /src.
#   friend-inside.sh user      ./install.sh --yes, as a new user
#   friend-inside.sh package   makepkg -si (packaging/PKGBUILD), then bead-setup --yes
# Then: the files landed, bead.lua parses and is loaded, and bead doctor finds
# nothing missing but what needs a real session.
set -eu
mode=${1:-user}
pacman -Syu --noconfirm --needed sudo lua base-devel git >/dev/null
id friend >/dev/null 2>&1 || useradd -m friend
echo 'friend ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/friend
as() { su friend -c "$1"; }
as 'rm -rf ~/bead && cp -r /src ~/bead && mkdir -p ~/.config/hypr && echo "-- hyprland.lua" >~/.config/hypr/hyprland.lua'

if [ "$mode" = package ]; then
	echo "── makepkg (packaging/PKGBUILD, from this working copy)"
	# a git repo of the working copy, tagged, for the PKGBUILD to clone
	as 'cd ~/bead && git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm build && git tag -f "v$(cat VERSION)" >/dev/null'
	as 'mkdir -p ~/pkg && cp ~/bead/packaging/PKGBUILD ~/bead/packaging/bead.install ~/pkg/ && sed -i "s|^source=.*|source=(\"\$_name::git+file://$HOME/bead\")|" ~/pkg/PKGBUILD'
	as 'cd ~/pkg && makepkg -si --noconfirm' </dev/null
	echo "── bead-setup --yes"
	as 'cd ~ && bead-setup --yes' </dev/null
	bin=/usr/bin share=/usr/share/bead
else
	echo "── install.sh --yes"
	as 'cd ~/bead && ./install.sh --yes' </dev/null
	bin='~/.local/bin' share='~/.local/share/bead'
fi

echo "── checks"
fail=0
ok() { if as "$2" >/dev/null 2>&1; then echo "  ✓ $1"; else echo "  ✗ $1"; fail=1; fi; }
ok "shell installed"          "test -f $share/shell.qml"
ok "shaders built"            "ls $share/shaders/*.qsb"
ok "commands in place"        "test -x $bin/bead && test -x $bin/bead-doctor && test -x $bin/bead-update"
ok "bead --version"           "test \"\$($bin/bead version)\" = \"\$(cat ~/bead/VERSION)\""
ok "bead.lua written"         'test -f ~/.config/hypr/bead.lua'
ok "bead.lua parses"          'luac -p ~/.config/hypr/bead.lua'
ok "bead.lua calls this bead" "grep -q '$bin/bead\\|/.local/bin/bead' ~/.config/hypr/bead.lua"
ok "hyprland.lua requires it" 'grep -q "require(\"bead\")" ~/.config/hypr/hyprland.lua'
ok "glint in place"           "test -x $bin/glint"
ok "Tint made colours"        'test -s ~/.local/state/bead/scheme.json'
echo "── bead doctor"
as "$bin/bead-doctor --tsv" >/tmp/doc || true
# what a container can't have: a running Hyprland, sound, a polkit agent
left=$(awk -F'\t' '$1=="missing" && $2=="core" && $3!="hyprland" && $3!="pipewire" && $3!="polkit" {print "  ✗ " $4 " → " $5}' /tmp/doc)
if [ -n "$left" ]; then echo "$left"; fail=1; else echo "  ✓ nothing missing but what needs a session"; fi
awk -F'\t' '$1=="missing" && $2!="core" {print "  – " $4 " (" $2 ")"}' /tmp/doc
if [ "$mode" = user ]; then
	echo "── bead uninstall"
	as '~/.local/bin/bead-uninstall >/dev/null'
	ok "bead is gone"             'test ! -e ~/.local/share/bead && test ! -e ~/.local/bin/bead'
	ok "hyprland.lua is yours again" '! grep -q "require(\"bead\")" ~/.config/hypr/hyprland.lua'
fi
[ "$fail" = 0 ] && echo "friend-test ($mode): passed" || { echo "friend-test ($mode): FAILED"; exit 1; }
