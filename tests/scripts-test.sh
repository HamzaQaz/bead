#!/bin/bash
# bead update and bead uninstall, in a throwaway home with a throwaway
# "origin" repository. Run by make test. Never touches the real home: every
# XDG folder points inside the temp dir.
set -u
cd "$(dirname "$0")/.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME=$T/home XDG_CONFIG_HOME=$T/home/.config XDG_STATE_HOME=$T/home/.local/state XDG_DATA_HOME=$T/home/.local/share
mkdir -p "$HOME"
fails=0
is() { if [ "$2" = "$3" ]; then echo "  ✓ $1"; else echo "  ✗ $1: got [$2], want [$3]"; fails=$((fails + 1)); fi; }
q() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

# origin: this working copy (as git sees it), released as v0.1.0
mkdir -p "$T/origin"
# safe.directory: HOME is the throwaway one, so CI's ~/.gitconfig (which trusts
# a checkout owned by another user) is not read
git -c safe.directory="$PWD" ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do
	if [ -e "$f" ]; then cp --parents "$f" "$T/origin"; fi
done
cp shaders/*.qsb "$T/origin/shaders/" 2>/dev/null
echo 0.1.0 >"$T/origin/VERSION"
q "$T/origin" init -q; q "$T/origin" -c user.name=t -c user.email=t@t add -A
q "$T/origin" -c user.name=t -c user.email=t@t commit -qm one; q "$T/origin" tag v0.1.0
git clone -q "$T/origin" "$T/src" 2>/dev/null; q "$T/src" -c advice.detachedHead=false checkout -q v0.1.0
make -s -C "$T/src" install PREFIX="$HOME/.local" >/dev/null 2>&1
B=$HOME/.local/bin

echo "bead update"
is "installed version" "$("$B/bead" version)" "0.1.0"
is "knows its checkout" "$(cat "$HOME/.local/share/bead/source")" "$T/src"
is "up to date" "$("$B/bead-update" --check)" "uptodate 0.1.0 0.1.0"
echo 0.2.0 >"$T/origin/VERSION"
q "$T/origin" -c user.name=t -c user.email=t@t commit -qam two; q "$T/origin" tag v0.2.0
is "a newer release" "$("$B/bead-update" --check)" "available 0.1.0 0.2.0"
echo "# mine" >>"$T/src/Makefile"
"$B/bead-update" >/dev/null 2>&1; is "leaves a changed checkout alone" "$?" "1"
q "$T/src" checkout -- Makefile
"$B/bead-update" >/dev/null 2>&1
is "updates" "$("$B/bead" version)" "0.2.0"
is "then up to date" "$("$B/bead-update" --check)" "uptodate 0.2.0 0.2.0"
q "$T/src" -c user.name=t -c user.email=t@t commit -q --allow-empty -m dev
is "a development checkout is yours" "$("$B/bead-update" --check | cut -d' ' -f1)" "dev"
rm "$HOME/.local/share/bead/source"
is "no checkout known" "$("$B/bead-update" --check | cut -d' ' -f1)" "nosource"

echo "bead uninstall"
mkdir -p "$XDG_CONFIG_HOME/hypr" "$XDG_CONFIG_HOME/bead" "$HOME/.claude"
printf -- '-- mine\nrequire("bead")\n' >"$XDG_CONFIG_HOME/hypr/hyprland.lua"
echo '-- bead' >"$XDG_CONFIG_HOME/hypr/bead.lua"
echo '{}' >"$XDG_CONFIG_HOME/bead/settings.json"
cat >"$HOME/.claude/settings.json" <<'J'
{"model": "x", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "~/.local/share/glint/claude-hook.sh"}]}, {"hooks": [{"type": "command", "command": "mine.sh"}]}],
 "Notification": [{"hooks": [{"type": "command", "command": "~/.local/share/glint/claude-hook.sh"}]}]}}
J
"$B/bead-uninstall" --dry-run >/dev/null
is "a dry run changes nothing" "$(test -d "$HOME/.local/share/bead" && grep -c 'require("bead")' "$XDG_CONFIG_HOME/hypr/hyprland.lua")" "1"
"$B/bead-uninstall" >/dev/null 2>&1
is "shell gone" "$(ls "$HOME/.local/share" | grep -c '^bead')" "0"
is "commands gone" "$(ls "$B" 2>/dev/null | grep -c bead)" "0"
is "your hyprland.lua keeps the rest" "$(cat "$XDG_CONFIG_HOME/hypr/hyprland.lua")" "-- mine"
is "hyprland.lua backed up" "$(ls "$XDG_CONFIG_HOME/hypr" | grep -c 'hyprland.lua.bak-')" "1"
is "bead.lua gone" "$(test -e "$XDG_CONFIG_HOME/hypr/bead.lua" && echo there)" ""
is "only Glint's hooks gone" "$(python3 -c 'import json,sys;m=json.load(open(sys.argv[1]));print(m["model"],list(m["hooks"]),len(m["hooks"]["Stop"]))' "$HOME/.claude/settings.json")" "x ['Stop'] 1"
is "settings kept" "$(test -f "$XDG_CONFIG_HOME/bead/settings.json" && echo kept)" "kept"
echo "lock at login"
L=$(dirname "$0")/../services/lock-at-login.sh
E=$T/etc-root; me=$(id -un)
at() { rm -f "$T/mark"; BEAD_ETC=$E sh "$L" "$1" "$T/mark" && echo lock || echo no; }
is "auto, a login screen: no lock" "$(at auto)" "no"
mkdir -p "$E/etc"; printf '[Autologin]\nUser=%s\nSession=hyprland\n' "$me" >"$E/etc/sddm.conf"
is "auto, SDDM autologin: lock" "$(at auto)" "lock"
is "only once per login" "$(BEAD_ETC=$E sh "$L" auto "$T/mark" && echo lock || echo no)" "no"
printf '[Autologin]\nUser=someone-else\n' >"$E/etc/sddm.conf"
is "someone else's autologin: no lock" "$(at auto)" "no"
printf '[General]\nUser=%s\n' "$me" >"$E/etc/sddm.conf"
is "User= outside [Autologin]: no lock" "$(at auto)" "no"
rm "$E/etc/sddm.conf"; mkdir -p "$E/etc/greetd"
printf '[initial_session]\ncommand = "Hyprland"\nuser = "%s"\n' "$me" >"$E/etc/greetd/config.toml"
is "auto, greetd initial session: lock" "$(at auto)" "lock"
rm -r "$E/etc/greetd"; mkdir -p "$E/etc/gdm"
printf '[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin=%s\n' "$me" >"$E/etc/gdm/custom.conf"
is "auto, GDM autologin: lock" "$(at auto)" "lock"
printf '[daemon]\nAutomaticLoginEnable=False\nAutomaticLogin=%s\n' "$me" >"$E/etc/gdm/custom.conf"
is "GDM autologin turned off: no lock" "$(at auto)" "no"
rm -r "$E/etc/gdm"; mkdir -p "$E/etc/systemd/system/getty@tty1.service.d"
printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty -o "-p -f -- \\\\u" --noclear --autologin %s %%I $TERM\n' "$me" >"$E/etc/systemd/system/getty@tty1.service.d/autologin.conf"
is "auto, getty autologin: lock" "$(at auto)" "lock"
rm -r "$E/etc/systemd"
is "on: always lock" "$(at on)" "lock"
is "off: never" "$(at off)" "no"

[ "$fails" = 0 ] && echo "scripts-test: passed" || { echo "scripts-test: $fails failed"; exit 1; }
