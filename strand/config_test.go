package main

import (
	"encoding/json"
	"os"
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
	t.Cleanup(func() { home, configDir, beadConf = oldHome, oldConf, oldBead })
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
		for _, want := range []string{"bead:launcher", "dashboard toggle", "cliphist"} {
			if !strings.Contains(string(out), want) {
				t.Errorf("%s lacks %q", file, want)
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
