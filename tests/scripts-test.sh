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
git ls-files -z --cached --others --exclude-standard | while IFS= read -r -d '' f; do
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
[ "$fails" = 0 ] && echo "scripts-test: passed" || { echo "scripts-test: $fails failed"; exit 1; }
