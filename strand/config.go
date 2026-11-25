package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ── Glint ↔ Claude Code ──

// claudeHooks adds Glint's hook to ~/.claude/settings.json for each event it
// handles, skipping any event that already runs a toast hook.
func claudeHooks() (string, error) {
	path := filepath.Join(home, ".claude", "settings.json")
	m := map[string]any{}
	if b, err := os.ReadFile(path); err == nil {
		if err := json.Unmarshal(b, &m); err != nil {
			return "", fmt.Errorf("%s isn't valid JSON, so strand left it alone: %w", path, err)
		}
	}
	hook := "~/.local/share/glint/claude-hook.sh"
	if shareDir != filepath.Join(home, ".local", "share") {
		hook = filepath.Join(shareDir, "glint", "claude-hook.sh")
	}
	events := []struct {
		name, matcher string
		timeout       int
	}{
		{"PermissionRequest", "", 300},
		{"PreToolUse", "AskUserQuestion", 300},
		{"PostToolUse", "AskUserQuestion", 10},
		{"Stop", "", 10},
		{"Notification", "", 10},
	}
	hooks, _ := m["hooks"].(map[string]any)
	if hooks == nil {
		hooks = map[string]any{}
	}
	var added []string
	for _, ev := range events {
		list, _ := hooks[ev.name].([]any)
		if mentions(list, "claude-hook.sh", "claude-toast.sh") {
			continue
		}
		entry := map[string]any{"hooks": []any{map[string]any{"type": "command", "command": hook, "timeout": ev.timeout}}}
		if ev.matcher != "" {
			entry["matcher"] = ev.matcher
		}
		hooks[ev.name] = append(list, entry)
		added = append(added, ev.name)
	}
	linked, err := linkLegacyHook()
	if err != nil {
		return "", err
	}
	if linked != "" {
		linked = "; " + linked
	}
	if len(added) == 0 {
		return "Claude Code already has toast hooks: left alone" + linked, nil
	}
	m["hooks"] = hooks
	if err := backup(path); err != nil {
		return "", err
	}
	b, _ := json.MarshalIndent(m, "", "  ")
	os.MkdirAll(filepath.Dir(path), 0o755)
	if err := os.WriteFile(path, append(b, '\n'), 0o600); err != nil {
		return "", err
	}
	return "hooked: " + strings.Join(added, ", ") + linked, nil
}

// linkLegacyHook: older installs copied the hook to
// ~/.claude/hooks/claude-toast.sh, and a copy never updates (a new toast,
// an old hook). Swap glint's own copy for a link to the installed hook, after
// a backup. Returns what it did, or "" when there was nothing to do.
func linkLegacyHook() (string, error) {
	old := filepath.Join(home, ".claude", "hooks", "claude-toast.sh")
	fi, err := os.Lstat(old)
	if err != nil || !fi.Mode().IsRegular() {
		return "", nil // missing, or a link already
	}
	b, err := os.ReadFile(old)
	if err != nil || !strings.Contains(string(b), "Glint bridge") {
		return "", nil // not glint's: someone's own script
	}
	if err := backup(old); err != nil {
		return "", err
	}
	dest := filepath.Join(shareDir, "glint", "claude-hook.sh")
	if err := os.Remove(old); err != nil {
		return "", err
	}
	if err := os.Symlink(dest, old); err != nil {
		return "", err
	}
	return "the old copy of the hook in ~/.claude/hooks now links to the installed one", nil
}

func mentions(v any, needles ...string) bool {
	b, _ := json.Marshal(v)
	for _, n := range needles {
		if strings.Contains(string(b), n) {
			return true
		}
	}
	return false
}

// ── Hyprland ──

func hyprTarget(lua bool) string {
	if lua {
		return "~/.config/hypr/bead.lua, required from hyprland.lua"
	}
	return "~/.config/hypr/bead.conf, sourced from hyprland.conf"
}

type bind struct{ keys, what, global, exec string }

// a polkit agent, unless one already runs (pkexec needs one to ask for the password)
const polkitAgent = `sh -c 'pgrep -f "polkit.*agent|polkit-gnome|polkit-kde|lxpolkit|soteria" >/dev/null || exec /usr/lib/hyprpolkitagent/hyprpolkitagent'`

var binds = []bind{
	{"SUPER + SUPER_L", "launcher (release)", "launcher", ""},
	{"SUPER + Tab", "workspace overview", "overview", ""},
	{"SUPER + Space", "voice command (hold)", "voice", ""},
	{"SUPER + A", "dictate (hold)", "dictate", ""},
	{"SUPER + K", "dashboard", "", "bead dashboard toggle"},
	{"SUPER + N", "notifications", "", "bead notifs toggle"},
	{"SUPER + L", "lock", "", "bead lock"},
	{"SUPER + V", "clipboard", "", "bead clip"},
	{"SUPER + Period", "emoji", "", "bead emoji"},
	{"SUPER + SHIFT + S", "screenshot area", "", "bead shot area"},
	{"Print", "screenshot area", "", "bead shot area"},
	{"SUPER + SHIFT + C", "colour picker", "", "bead pick"},
	{"SUPER + ALT + R", "record screen", "", "bead record screen sound"},
	{"XF86AudioPlay", "play / pause", "mediaToggle", ""},
	{"XF86AudioNext", "next track", "mediaNext", ""},
	{"XF86AudioPrev", "previous track", "mediaPrev", ""},
	{"XF86MonBrightnessUp", "brightness up", "", "bead brightness up"},
	{"XF86MonBrightnessDown", "brightness down", "", "bead brightness down"},
}

func hyprBinds(lua bool) (string, error) {
	hypr := filepath.Join(configDir, "hypr")
	var file, main, include string
	var b strings.Builder
	if lua {
		file, main, include = filepath.Join(hypr, "bead.lua"), filepath.Join(hypr, "hyprland.lua"), `require("bead")`
		b.WriteString("-- bead (written by strand). Edit freely; strand won't overwrite it.\n")
		if binDir == filepath.Join(home, ".local", "bin") {
			b.WriteString(`local bead = os.getenv("HOME") .. "/.local/bin/bead"` + "\n")
		} else {
			fmt.Fprintf(&b, "local bead = %q\n", filepath.Join(binDir, "bead"))
		}
		b.WriteString("hl.on(\"hyprland.start\", function()\n")
		b.WriteString("    hl.exec_cmd(bead .. \" start\")\n")
		fmt.Fprintf(&b, "    hl.exec_cmd(%q) -- asks for your password when installing (if you have no agent yet)\n", polkitAgent)
		b.WriteString("    hl.exec_cmd(\"wl-paste --type text --watch cliphist store\") -- clipboard history (Super+V)\n")
		b.WriteString("    hl.exec_cmd(\"wl-paste --type image --watch cliphist store\")\n")
		b.WriteString("end)\n\n")
		for _, k := range binds {
			opts := ""
			if k.keys == "SUPER + SUPER_L" {
				opts = ", { release = true }"
			} else if strings.HasPrefix(k.keys, "XF86") || k.keys == "Print" {
				opts = ", { locked = true }"
			}
			if k.global != "" {
				fmt.Fprintf(&b, "hl.bind(%q, hl.dsp.global(\"bead:%s\")%s) -- %s\n", k.keys, k.global, opts, k.what)
			} else {
				fmt.Fprintf(&b, "hl.bind(%q, hl.dsp.exec_cmd(bead .. %q)%s) -- %s\n", k.keys, strings.TrimPrefix(k.exec, "bead"), opts, k.what)
			}
		}
	} else {
		file, main, include = filepath.Join(hypr, "bead.conf"), filepath.Join(hypr, "hyprland.conf"), "source = ~/.config/hypr/bead.conf"
		b.WriteString("# bead (written by strand). Edit freely; strand won't overwrite it.\n")
		bin := "~/.local/bin/"
		if binDir != filepath.Join(home, ".local", "bin") {
			bin = binDir + "/"
		}
		b.WriteString("exec-once = " + bin + "bead start\n")
		b.WriteString("exec-once = " + polkitAgent + " # asks for your password when installing (if you have no agent yet)\n")
		b.WriteString("exec-once = wl-paste --type text --watch cliphist store # clipboard history (Super+V)\n")
		b.WriteString("exec-once = wl-paste --type image --watch cliphist store\n\n")
		for _, k := range binds {
			flag := "bind"
			if k.keys == "SUPER + SUPER_L" {
				flag = "bindr"
			} else if strings.HasPrefix(k.keys, "XF86") || k.keys == "Print" {
				flag = "bindl"
			}
			mods, key := confKeys(k.keys)
			if k.global != "" {
				fmt.Fprintf(&b, "%s = %s, %s, global, bead:%s # %s\n", flag, mods, key, k.global, k.what)
			} else {
				fmt.Fprintf(&b, "%s = %s, %s, exec, %s%s # %s\n", flag, mods, key, bin, k.exec, k.what)
			}
		}
	}
	made, err := writeNew(file, b.String(), 0o644)
	if err != nil {
		return "", err
	}
	note := "wrote " + file
	if !made {
		note = file + " already there: left alone"
	}
	cur, err := os.ReadFile(main)
	if err != nil {
		return note + "; couldn't read " + main + ", so add this line yourself: " + include, nil
	}
	if strings.Contains(string(cur), include) {
		return note, nil
	}
	if err := backup(main); err != nil {
		return "", err
	}
	f, err := os.OpenFile(main, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		return "", err
	}
	defer f.Close()
	_, err = fmt.Fprintf(f, "\n%s\n", include)
	return note + " and added it to " + filepath.Base(main), err
}

// "SUPER + SHIFT + S" -> "SUPER SHIFT", "S"
func confKeys(k string) (string, string) {
	parts := strings.Split(k, " + ")
	return strings.Join(parts[:len(parts)-1], " "), parts[len(parts)-1]
}
