package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// fakeHome points strand's paths at a temp folder for one test.
func fakeHome(t *testing.T) string {
	t.Helper()
	h := t.TempDir()
	oldHome, oldConf, oldBead := home, configDir, beadConf
	home, configDir, beadConf = h, filepath.Join(h, ".config"), filepath.Join(h, ".config", "bead")
	setPackaged(false) // bin and share under the fake home
	t.Cleanup(func() { home, configDir, beadConf = oldHome, oldConf, oldBead; setPackaged(false) })
	return h
}

func TestClaudeHooks(t *testing.T) {
	h := fakeHome(t)
	path := filepath.Join(h, ".claude", "settings.json")
	os.MkdirAll(filepath.Dir(path), 0o755)
	// an existing Stop hook of someone else's, and a theme setting to keep
	os.WriteFile(path, []byte(`{"theme":"dark","hooks":{"Stop":[{"hooks":[{"type":"command","command":"other.sh"}]}]}}`), 0o600)
	if _, err := claudeHooks(); err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	b, _ := os.ReadFile(path)
	json.Unmarshal(b, &m)
	if m["theme"] != "dark" {
		t.Error("lost an unrelated setting")
	}
	hooks := m["hooks"].(map[string]any)
	if n := len(hooks["Stop"].([]any)); n != 2 {
		t.Errorf("Stop should keep its hook and gain ours: %d entries", n)
	}
	pre := hooks["PreToolUse"].([]any)[0].(map[string]any)
	if pre["matcher"] != "AskUserQuestion" {
		t.Errorf("PreToolUse matcher: %v", pre["matcher"])
	}
	// running again adds nothing
	if out, _ := claudeHooks(); !strings.Contains(out, "already") {
		t.Errorf("second run: %q", out)
	}
	backups, _ := filepath.Glob(path + ".bak-strand-*")
	if len(backups) != 1 {
		t.Errorf("want one backup, got %d", len(backups))
	}
}

func TestHyprBinds(t *testing.T) {
	for _, lua := range []bool{true, false} {
		h := fakeHome(t)
		hypr := filepath.Join(h, ".config", "hypr")
		os.MkdirAll(hypr, 0o755)
		main, file, inc := "hyprland.conf", "bead.conf", "source = ~/.config/hypr/bead.conf"
		if lua {
			main, file, inc = "hyprland.lua", "bead.lua", `require("bead")`
		}
		os.WriteFile(filepath.Join(hypr, main), []byte("# mine\n"), 0o644)
		if _, err := hyprBinds(lua); err != nil {
			t.Fatal(err)
		}
		hyprBinds(lua) // twice: no duplicate include
		cur, _ := os.ReadFile(filepath.Join(hypr, main))
		if strings.Count(string(cur), inc) != 1 || !strings.HasPrefix(string(cur), "# mine") {
			t.Errorf("%s: %q", main, cur)
		}
		out, _ := os.ReadFile(filepath.Join(hypr, file))
		t.Logf("%s:\n%s", file, out)
		for _, want := range []string{"bead:launcher", "dashboard toggle", "cliphist", "hyprpolkitagent"} {
			if !strings.Contains(string(out), want) {
				t.Errorf("%s lacks %q", file, want)
			}
		}
		// the polkit line reaches the shell with plain quotes: escaped in Lua's
		// string, left as they are in hyprland.conf
		if lua && !strings.Contains(string(out), `pgrep -f \"polkit`) || !lua && !strings.Contains(string(out), `pgrep -f "polkit`) {
			t.Errorf("%s: polkit line quoted wrongly", file)
		}
		// and the Lua parses
		if lua {
			if _, err := exec.LookPath("luac"); err == nil {
				if b, err := exec.Command("luac", "-p", filepath.Join(hypr, file)).CombinedOutput(); err != nil {
					t.Errorf("bead.lua doesn't parse: %s", b)
				}
			}
		}
	}
}

func TestSetSetting(t *testing.T) {
	fakeHome(t)
	os.MkdirAll(beadConf, 0o755)
	os.WriteFile(filepath.Join(beadConf, "settings.json"), []byte(`{"units":"auto"}`), 0o644)
	if _, err := pearlSetup("api", " sk-test \n"); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(filepath.Join(beadConf, "settings.json"))
	if !strings.Contains(string(b), `"askVia": "api"`) || !strings.Contains(string(b), `"units": "auto"`) {
		t.Errorf("settings: %s", b)
	}
	st, _ := os.Stat(filepath.Join(beadConf, "anthropic-key"))
	if st.Mode().Perm() != 0o600 {
		t.Errorf("key file mode %v", st.Mode().Perm())
	}
}

// The keys sheet in bead (data/keys.json) must list every key strand writes,
// saying the same thing about it.
func TestKeysSheetListsEveryBind(t *testing.T) {
	raw, err := os.ReadFile(filepath.Join("..", "data", "keys.json"))
	if err != nil {
		t.Fatal(err)
	}
	var sheet []struct{ Keys, What, Group string }
	if err := json.Unmarshal(raw, &sheet); err != nil {
		t.Fatal(err)
	}
	listed := map[string]string{}
	for _, k := range sheet {
		if k.Group == "" {
			t.Errorf("%s has no group", k.Keys)
		}
		listed[k.Keys] = k.What
	}
	for _, b := range binds {
		if what, ok := listed[b.keys]; !ok {
			t.Errorf("data/keys.json is missing %s (%s)", b.keys, b.what)
		} else if what != b.what {
			t.Errorf("%s: the sheet says %q, strand writes %q", b.keys, what, b.what)
		}
	}
}

// --yes runs unattended: pacman and the AUR helper mustn't stop to ask.
// The interactive installer leaves the questions to them.
func TestPlanNoConfirm(t *testing.T) {
	s := system{arch: true, helper: "paru", repo: "/x"}
	core := []*part{{id: "core", core: true, on: true, pkgs: []string{"definitely-not-a-package-xyz"}}}
	for _, quiet := range []bool{false, true} {
		steps, _, _, _ := plan(s, core, choices{parts: map[string]bool{"core": true}, noconfirm: quiet})
		for _, st := range steps {
			if st.cmd == nil {
				continue
			}
			args := strings.Join(st.cmd.Args, " ")
			if strings.Contains(args, "--noconfirm") != quiet {
				t.Errorf("noconfirm=%v: %s", quiet, args)
			}
		}
	}
}

// No terminal on the machine: the core part brings kitty (bead opens AUR
// builds and updates in one). One already there: nothing extra.
func TestPlanBringsATerminal(t *testing.T) {
	core := []*part{{id: "core", core: true, on: true, pkgs: []string{"definitely-not-a-package-xyz"}}}
	c := choices{parts: map[string]bool{"core": true}}
	for _, has := range []bool{false, true} {
		all := strings.Join(wanted(system{arch: true, terminal: has, repo: "/x"}, core, c), " ")
		if strings.Contains(all, "kitty") == has {
			t.Errorf("terminal=%v: packages %q", has, all)
		}
	}
}

// Tint's first run: your own wallpaper if there is one, else bead's.
func TestFirstWallpaper(t *testing.T) {
	mine, beads := t.TempDir(), t.TempDir()
	os.WriteFile(filepath.Join(beads, "bead.jpg"), []byte("x"), 0o644)
	if got := firstWallpaper(mine, beads); got != filepath.Join(beads, "bead.jpg") {
		t.Errorf("none of mine: got %q", got)
	}
	os.WriteFile(filepath.Join(mine, "notes.txt"), []byte("x"), 0o644)
	os.WriteFile(filepath.Join(mine, "sea.PNG"), []byte("x"), 0o644)
	if got := firstWallpaper(mine, beads); got != filepath.Join(mine, "sea.PNG") {
		t.Errorf("mine first: got %q", got)
	}
	if got := firstWallpaper(t.TempDir()); got != "" {
		t.Errorf("nothing anywhere: got %q", got)
	}
}

// A packaged bead (no Makefile next to shell.qml): keybinds call /usr/bin/bead,
// and strand doesn't try to build what the package already installed.
func TestPackaged(t *testing.T) {
	h := fakeHome(t)
	repo := t.TempDir()
	os.WriteFile(filepath.Join(repo, "shell.qml"), nil, 0o644)
	s := detect(repo)
	defer setPackaged(false)
	if !s.packaged {
		t.Fatal("no Makefile: should count as packaged")
	}
	hypr := filepath.Join(h, ".config", "hypr")
	os.MkdirAll(hypr, 0o755)
	os.WriteFile(filepath.Join(hypr, "hyprland.lua"), []byte("-- mine\n"), 0o644)
	if _, err := hyprBinds(true); err != nil {
		t.Fatal(err)
	}
	out, _ := os.ReadFile(filepath.Join(hypr, "bead.lua"))
	if !strings.Contains(string(out), `local bead = "/usr/bin/bead"`) {
		t.Errorf("bead.lua doesn't call /usr/bin/bead:\n%s", out)
	}
	if w := wanted(system{packaged: true, terminal: true}, []*part{{id: "core", core: true, on: true, pkgs: []string{"make"}}}, choices{parts: map[string]bool{"core": true}}); len(w) != 0 {
		t.Errorf("packaged: core packages wanted again: %v", w)
	}
	steps, _, _, _ := plan(s, []*part{{id: "core", core: true, on: true}, {id: "glint", on: true}}, choices{parts: map[string]bool{"core": true, "glint": true}})
	for _, st := range steps {
		if st.title == "Build and install bead" || st.title == "Glint" {
			t.Errorf("packaged, but plans %q", st.title)
		}
	}
}
