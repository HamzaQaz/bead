// strand: the installer for bead (a Quickshell shell for Hyprland).
//
//	strand            choose parts, review the plan, install
//	strand --dry-run  walk through it without changing anything
//	strand --repo DIR install from a bead checkout elsewhere (default: the
//	                  folder above strand's, or the current one)
//	strand --yes [--with murmur,huddle] [--without binds]
//	                  no questions: the default parts (plus/minus these), in plain text
//	strand --gui describe|plan|run [--parts a,b] [--pearl way]
//	                  for the graphical installer (installer/): JSON, see gui.go
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	if filepath.Base(os.Args[0]) == askpassName { // sudo asking for the password (gui.go)
		os.Exit(askpassClient())
	}
	dry := flag.Bool("dry-run", false, "show what would happen; change nothing")
	repo := flag.String("repo", "", "the bead checkout to install from")
	yes := flag.Bool("yes", false, "install the default parts without asking (plain output)")
	with := flag.String("with", "", "with --yes: parts to add, comma-separated")
	without := flag.String("without", "", "with --yes: parts to leave out, comma-separated")
	guiMode := flag.String("gui", "", "for the graphical installer: describe | plan | run (JSON)")
	parts := flag.String("parts", "", "with --gui: the parts chosen, comma-separated (core is always in)")
	pearl := flag.String("pearl", "claude", "with --gui: how Pearl answers (claude | api | local)")
	flag.Parse()

	dir, err := findRepo(*repo)
	if err != nil {
		fmt.Fprintln(os.Stderr, "strand:", err)
		os.Exit(1)
	}
	if *guiMode != "" {
		os.Exit(gui(*guiMode, detect(dir), split(*parts), *pearl))
	}
	if *yes {
		os.Exit(headless(detect(dir), *dry, split(*with), split(*without)))
	}
	m, err := tea.NewProgram(newModel(detect(dir), *dry), tea.WithAltScreen()).Run()
	if err != nil {
		fmt.Fprintln(os.Stderr, "strand:", err)
		os.Exit(1)
	}
	if fm, ok := m.(model); ok && fm.screen == finished && !fm.dry {
		fmt.Println("bead is threaded. Start it with: bead start")
	}
}

// findRepo looks for bead's shell.qml: --repo, the current folder, its parent
// (running from strand/), or next to the executable.
func findRepo(flagged string) (string, error) {
	var tries []string
	if flagged != "" {
		tries = []string{flagged}
	} else {
		wd, _ := os.Getwd()
		tries = append(tries, wd, filepath.Dir(wd))
		if exe, err := os.Executable(); err == nil {
			tries = append(tries, filepath.Dir(exe), filepath.Dir(filepath.Dir(exe)))
		}
	}
	for _, d := range tries {
		if _, err := os.Stat(filepath.Join(d, "shell.qml")); err == nil {
			return filepath.Abs(d)
		}
	}
	return "", fmt.Errorf("can't find the bead checkout (shell.qml); run strand from it or pass --repo")
}

func split(s string) []string {
	var out []string
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

// headless installs without the TUI: default parts, adjusted by --with/--without.
func headless(s system, dry bool, with, without []string) int {
	if !s.arch {
		fmt.Fprintln(os.Stderr, "strand: Arch-based systems (pacman) only")
		return 1
	}
	parts := allParts()
	known := map[string]*part{}
	for _, p := range parts {
		known[p.id] = p
		if p.id == "glint-claude" {
			p.on = s.claude
		}
	}
	for _, id := range with {
		if p, ok := known[id]; ok {
			p.on = true
		} else {
			fmt.Fprintln(os.Stderr, "strand: no part called", id)
			return 2
		}
	}
	for _, id := range without {
		if p, ok := known[id]; ok && !p.core {
			p.on = false
		}
	}
	m := newModel(s, dry)
	m.parts = parts
	c := m.chosen()
	c.noconfirm = true
	steps, repo, aur, mb := plan(s, parts, c)
	var on []string
	for _, p := range parts {
		if c.has(p.id) {
			on = append(on, p.name)
		}
	}
	fmt.Println("strand: installing", strings.Join(on, ", "))
	if len(repo) > 0 {
		fmt.Println("  packages:", strings.Join(repo, " "))
	}
	if len(aur) > 0 {
		fmt.Println("  AUR:", strings.Join(aur, " "))
	}
	if mb > 0 {
		fmt.Printf("  downloads: %d MB\n", mb)
	}
	for i, st := range steps {
		fmt.Printf("\n[%d/%d] %s: %s\n", i+1, len(steps), st.title, st.detail)
		if dry {
			continue
		}
		var out string
		var err error
		switch {
		case st.cmd != nil && st.interactive:
			st.cmd.Stdin, st.cmd.Stdout, st.cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
			err = st.cmd.Run()
		case st.run != nil:
			out, err = st.run()
		default:
			var b []byte
			b, err = st.cmd.CombinedOutput()
			out = string(b)
		}
		if out = strings.TrimSpace(out); out != "" {
			fmt.Println(out)
		}
		if err != nil {
			fmt.Fprintf(os.Stderr, "strand: %s failed: %v\n", st.title, err)
			return 1
		}
	}
	fmt.Println("\nbead is threaded. Start it with: bead start")
	return 0
}
