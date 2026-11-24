package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

var home, _ = os.UserHomeDir()

func xdg(env, fallback string) string {
	if v := os.Getenv(env); v != "" {
		return v
	}
	return filepath.Join(home, fallback)
}

var (
	configDir = xdg("XDG_CONFIG_HOME", ".config")
	beadConf  = filepath.Join(configDir, "bead")
	modelsDir = filepath.Join(xdg("XDG_DATA_HOME", ".local/share"), "bead-models")
)

// What strand found on this machine.
type system struct {
	arch      bool   // pacman present
	helper    string // paru / yay, "" if none
	hyprLua   bool   // Hyprland's Lua config (hyprland.lua) rather than hyprland.conf
	hyprBinds bool   // the config already binds bead's shortcuts
	claude    bool   // Claude Code installed (~/.claude)
	repo      string // the bead checkout we install from
}

func have(cmd string) bool { _, err := exec.LookPath(cmd); return err == nil }

func detect(repo string) system {
	s := system{arch: have("pacman"), repo: repo}
	for _, h := range []string{"paru", "yay"} {
		if have(h) {
			s.helper = h
			break
		}
	}
	hypr := filepath.Join(configDir, "hypr")
	_, err := os.Stat(filepath.Join(hypr, "hyprland.lua"))
	s.hyprLua = err == nil
	s.hyprBinds = exec.Command("grep", "-rqs", "bead:launcher", hypr).Run() == nil
	_, err = os.Stat(filepath.Join(home, ".claude"))
	s.claude = err == nil
	return s
}

// missing returns the packages not yet satisfied (pacman -T understands
// "provides", so quickshell-git counts as quickshell), split by where they come from.
func missing(pkgs []string) (repo, aur []string) {
	if len(pkgs) == 0 {
		return nil, nil
	}
	out, _ := exec.Command("pacman", append([]string{"-T"}, pkgs...)...).Output()
	for _, p := range strings.Fields(string(out)) {
		if exec.Command("pacman", "-Si", p).Run() == nil {
			repo = append(repo, p)
		} else {
			aur = append(aur, p)
		}
	}
	return
}

// ── the plan: what will happen, in order ──

type step struct {
	title  string
	detail string
	// interactive steps hand the terminal over (sudo prompts, download progress)
	interactive bool
	cmd         *exec.Cmd
	run         func() (string, error)
}

type choices struct {
	parts  map[string]bool
	pearl  string // claude | api | local
	apiKey string
}

func (c choices) has(id string) bool { return c.parts[id] }

func plan(s system, parts []*part, c choices) (steps []step, repoPkgs, aurPkgs []string, downloadMB int) {
	var want []string
	for _, p := range parts {
		if c.has(p.id) {
			want = append(want, p.pkgs...)
		}
	}
	sort.Strings(want)
	repoPkgs, aurPkgs = missing(want)

	if len(repoPkgs) > 0 {
		steps = append(steps, step{
			title: "Packages", detail: strings.Join(repoPkgs, " "), interactive: true,
			cmd: exec.Command("sudo", append([]string{"pacman", "-S", "--needed"}, repoPkgs...)...),
		})
	}
	if len(aurPkgs) > 0 {
		st := step{title: "AUR packages", detail: strings.Join(aurPkgs, " "), interactive: true}
		if s.helper != "" {
			st.cmd = exec.Command(s.helper, append([]string{"-S", "--needed"}, aurPkgs...)...)
		} else {
			st.run = func() (string, error) {
				return "", fmt.Errorf("these come from the AUR and no helper (paru or yay) is installed: %s", strings.Join(aurPkgs, " "))
			}
		}
		steps = append(steps, st)
	}

	// make is looked up when the step runs: on a bare system the packages step installs it
	mk := func(target string) func() (string, error) {
		return func() (string, error) { return output(exec.Command("make", "-C", s.repo, target))() }
	}
	steps = append(steps, step{title: "Build and install bead", detail: "shaders, then ~/.local/share/bead and ~/.local/bin", run: func() (string, error) {
		os.MkdirAll(filepath.Join(xdg("XDG_PICTURES_DIR", "Pictures"), "Wallpapers"), 0o755) // where bead looks for them
		return mk("install")()
	}})

	if c.has("glint") {
		steps = append(steps, step{title: "Glint", detail: "build the glint command", run: mk("install-glint")})
	}
	if c.has("glint-claude") {
		steps = append(steps, step{title: "Glint for Claude Code", detail: "hooks in ~/.claude/settings.json (backed up first)", run: claudeHooks})
	}
	if c.has("murmur") {
		for _, m := range murmurModels {
			dst := filepath.Join(modelsDir, m.file)
			if _, err := os.Stat(dst); err == nil {
				continue
			}
			downloadMB += m.mb
			steps = append(steps, step{
				title: "Download " + m.name, detail: fmt.Sprintf("%d MB from huggingface.co", m.mb), interactive: true,
				cmd: exec.Command("sh", "-c", `mkdir -p "$(dirname "$1")" && curl -fL --progress-bar -o "$1.part" "$2" && mv "$1.part" "$1"`, "sh", dst, m.url),
			})
		}
	}
	if c.has("huddle") {
		steps = append(steps, step{title: "Huddle", detail: "~/.config/bead/discord.json for your Discord app", run: huddleConfig})
	}
	if c.has("pearl") {
		way, key := c.pearl, c.apiKey
		name := way
		for _, w := range pearlWays {
			if w.id == way {
				name = w.name
			}
		}
		steps = append(steps, step{title: "Pearl", detail: "answers with " + name, run: func() (string, error) { return pearlSetup(way, key) }})
	}
	if c.has("tint") {
		steps = append(steps, step{title: "Tint", detail: "colours from your first wallpaper", run: tintFirst})
	}
	if c.has("binds") {
		if s.hyprBinds {
			steps = append(steps, step{title: "Hyprland keybinds", detail: "already set up: left alone", run: func() (string, error) { return "your config already binds bead", nil }})
		} else {
			lua := s.hyprLua
			steps = append(steps, step{title: "Hyprland keybinds", detail: hyprTarget(lua), run: func() (string, error) { return hyprBinds(lua) }})
		}
	}
	return
}

func output(cmd *exec.Cmd) func() (string, error) {
	return func() (string, error) {
		out, err := cmd.CombinedOutput()
		return string(out), err
	}
}

// backup copies a file aside before strand changes it.
func backup(path string) error {
	b, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	} else if err != nil {
		return err
	}
	return os.WriteFile(path+".bak-strand-"+time.Now().Format("20060102-150405"), b, 0o600)
}

// writeNew writes a file only if it doesn't exist yet.
func writeNew(path, data string, mode os.FileMode) (bool, error) {
	if _, err := os.Stat(path); err == nil {
		return false, nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return false, err
	}
	return true, os.WriteFile(path, []byte(data), mode)
}

func huddleConfig() (string, error) {
	path := filepath.Join(beadConf, "discord.json")
	made, err := writeNew(path, "{\n  \"client_id\": \"PASTE\",\n  \"client_secret\": \"PASTE\"\n}\n", 0o600)
	if err != nil {
		return "", err
	}
	if !made {
		return "discord.json already there: left alone", nil
	}
	return "made " + path + ": add your app's id and secret (see below)", nil
}

// settings.json is bead's own (config/Settings.qml); strand only sets keys.
func setSetting(key string, value any) error {
	path := filepath.Join(beadConf, "settings.json")
	m := map[string]any{}
	if b, err := os.ReadFile(path); err == nil {
		if err := json.Unmarshal(b, &m); err != nil {
			return fmt.Errorf("%s isn't valid JSON: %w", path, err)
		}
	}
	m[key] = value
	b, _ := json.MarshalIndent(m, "", "    ")
	os.MkdirAll(beadConf, 0o755)
	return os.WriteFile(path, append(b, '\n'), 0o644)
}

func pearlSetup(way, key string) (string, error) {
	if way == "api" && key != "" {
		path := filepath.Join(beadConf, "anthropic-key")
		os.MkdirAll(beadConf, 0o755)
		if err := os.WriteFile(path, []byte(strings.TrimSpace(key)+"\n"), 0o600); err != nil {
			return "", err
		}
	}
	if err := setSetting("askVia", way); err != nil {
		return "", err
	}
	msg := "Pearl answers via " + way
	if way == "claude" && !have("claude") {
		msg += " (install Claude Code and sign in for it to work)"
	}
	return msg, nil
}

func tintFirst() (string, error) {
	dir := filepath.Join(xdg("XDG_PICTURES_DIR", "Pictures"), "Wallpapers")
	entries, _ := os.ReadDir(dir)
	for _, e := range entries {
		ext := strings.ToLower(filepath.Ext(e.Name()))
		if ext == ".png" || ext == ".jpg" || ext == ".jpeg" || ext == ".webp" {
			out, err := exec.Command(filepath.Join(home, ".local/bin/bead-tint"), filepath.Join(dir, e.Name())).CombinedOutput()
			return string(out), err
		}
	}
	return "no wallpapers in " + dir + " yet: Tint runs when you pick one", nil
}
