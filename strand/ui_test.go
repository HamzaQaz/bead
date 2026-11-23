package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

func press(t *testing.T, m tea.Model, keys ...string) tea.Model {
	t.Helper()
	for _, k := range keys {
		var msg tea.KeyMsg
		switch k {
		case "enter":
			msg = tea.KeyMsg{Type: tea.KeyEnter}
		case "down":
			msg = tea.KeyMsg{Type: tea.KeyDown}
		case " ":
			msg = tea.KeyMsg{Type: tea.KeySpace, Runes: []rune(" ")}
		default:
			msg = tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(k)}
		}
		var cmd tea.Cmd
		m, cmd = m.Update(msg)
		m = drain(m, cmd)
	}
	return m
}

// drain runs commands that finish a dry-run step (skips spinner ticks).
func drain(m tea.Model, cmd tea.Cmd) tea.Model {
	for cmd != nil {
		msg := cmd()
		if b, ok := msg.(tea.BatchMsg); ok {
			var next tea.Cmd
			for _, c := range b {
				if c == nil {
					continue
				}
				if r := c(); r != nil {
					if _, ok := r.(stepDone); ok {
						m, next = m.Update(r)
					}
				}
			}
			cmd = next
			continue
		}
		if _, ok := msg.(stepDone); !ok {
			return m
		}
		m, cmd = m.Update(msg)
	}
	return m
}

// A dry run through every screen: nothing on the system changes.
func TestDryRun(t *testing.T) {
	repo, _ := filepath.Abs("..")
	var m tea.Model = newModel(detect(repo), true)
	m, _ = m.Update(tea.WindowSizeMsg{Width: 100, Height: 50})
	show := os.Getenv("SHOW") != ""
	step := func(name string) {
		if show {
			t.Logf("── %s ──%s", name, m.View())
		}
	}
	step("welcome")
	m = press(t, m, "enter")
	step("parts")
	// cursor to Murmur (index 4) and Huddle (5): turn both on
	m = press(t, m, "down", "down", "down", "down", " ", "down", " ")
	step("parts toggled")
	m = press(t, m, "enter")
	step("pearl")
	m = press(t, m, "down", "enter")
	m = press(t, m, "s", "k", "-", "x")
	step("key")
	m = press(t, m, "enter")
	step("review")
	m = press(t, m, "enter")
	step("finished")
	fm := m.(model)
	if fm.screen != finished {
		t.Fatalf("expected finished, got screen %d (failed step %d)", fm.screen, fm.failed)
	}
	for _, st := range fm.steps {
		if st.status != "ok" || !strings.HasPrefix(st.note, "would") {
			t.Errorf("step %q: status %q note %q", st.title, st.status, st.note)
		}
	}
	if c := fm.chosen(); !c.has("murmur") || !c.has("huddle") || c.pearl != "api" || c.apiKey != "sk-x" {
		t.Errorf("choices wrong: %+v", c)
	}
}

func TestConfKeys(t *testing.T) {
	if m, k := confKeys("SUPER + SHIFT + S"); m != "SUPER SHIFT" || k != "S" {
		t.Fatal(m, k)
	}
	if m, k := confKeys("Print"); m != "" || k != "Print" {
		t.Fatal(m, k)
	}
}
