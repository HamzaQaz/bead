// strand: the installer for bead (a Quickshell shell for Hyprland).
//
//	strand            choose parts, review the plan, install
//	strand --dry-run  walk through it without changing anything
//	strand --repo DIR install from a bead checkout elsewhere (default: the
//	                  folder above strand's, or the current one)
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"

	tea "github.com/charmbracelet/bubbletea"
)

func main() {
	dry := flag.Bool("dry-run", false, "show what would happen; change nothing")
	repo := flag.String("repo", "", "the bead checkout to install from")
	flag.Parse()

	dir, err := findRepo(*repo)
	if err != nil {
		fmt.Fprintln(os.Stderr, "strand:", err)
		os.Exit(1)
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
