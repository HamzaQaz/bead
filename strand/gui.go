package main

// strand's side of the graphical installer (installer/, a Quickshell window).
// The window runs strand in one of three modes and reads JSON from it:
//
//	strand --gui describe                  the machine and the parts (one object)
//	strand --gui plan --parts a,b          what installing those would do (one object)
//	strand --gui run  --parts a,b [--pearl way]
//	                                       do it, as a stream of events (one per line);
//	                                       first reads {"password","apiKey"} on stdin
//
// The password: checked with `sudo -v`, then handed to sudo (and to paru or
// yay through --sudoflags -A) by an askpass helper, which is this program run
// as strand-askpass. It asks for it over a socket in a folder only you can
// open; the password stays in memory and is never written down.

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
)

const askpassName = "strand-askpass"

type guiPart struct {
	ID      string `json:"id"`
	Name    string `json:"name"`
	Blurb   string `json:"blurb"`
	On      bool   `json:"on"`
	Core    bool   `json:"core"`
	Needs   string `json:"needs,omitempty"`
	Disable string `json:"disable,omitempty"`
}

type guiWay struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Blurb string `json:"blurb"`
}

type guiStep struct {
	Title  string `json:"title"`
	Detail string `json:"detail"`
}

// selected: the parts the window chose (core always), as the TUI would have them
func selected(s system, ids []string, pearl string) (model, choices) {
	m := newModel(s, false)
	want := map[string]bool{}
	for _, id := range ids {
		want[id] = true
	}
	for _, p := range m.parts {
		if !p.core {
			p.on = want[p.id]
		}
	}
	for i, w := range pearlWays {
		if w.id == pearl {
			m.pearl = i
		}
	}
	c := m.chosen()
	c.noconfirm = true // no terminal to answer pacman's questions in
	return m, c
}

func gui(mode string, s system, ids []string, pearl string) int {
	out := json.NewEncoder(os.Stdout)
	if !s.arch && mode != "describe" {
		out.Encode(map[string]any{"ev": "failed", "error": "bead's installer supports Arch-based systems (pacman) only"})
		return 1
	}
	switch mode {
	case "describe":
		m := newModel(s, false)
		var parts []guiPart
		for _, p := range m.parts {
			parts = append(parts, guiPart{p.id, p.name, p.blurb, p.on, p.core, p.needs, p.disable})
		}
		var ways []guiWay
		for _, w := range pearlWays {
			ways = append(ways, guiWay{w.id, w.name, w.blurb})
		}
		_, err := os.Stat(filepath.Join(shareDir, "bead", "shell.qml"))
		out.Encode(map[string]any{
			"arch": s.arch, "helper": s.helper, "terminal": s.terminal, "packaged": s.packaged,
			"hyprLua": s.hyprLua, "hyprBinds": s.hyprBinds, "claude": s.claude, "repo": s.repo,
			"installed": err == nil, "user": os.Getenv("USER"),
			"parts": parts, "pearl": ways,
		})
		return 0
	case "plan":
		m, c := selected(s, ids, pearl)
		steps, repo, aur, mb := plan(s, m.parts, c)
		var gs []guiStep
		for _, st := range steps {
			gs = append(gs, guiStep{st.title, st.detail})
		}
		out.Encode(map[string]any{
			"steps": gs, "repo": repo, "aur": aur, "downloadMB": mb,
			"needsPassword":    len(repo) > 0 || len(aur) > 0,
			"aurWithoutHelper": len(aur) > 0 && s.helper == "",
		})
		return 0
	case "run":
		return guiRun(s, ids, pearl)
	}
	fmt.Fprintln(os.Stderr, "strand: --gui describe|plan|run")
	return 2
}

// events: one JSON object per line, from several goroutines
type events struct {
	mu  sync.Mutex
	enc *json.Encoder
}

func (e *events) send(v map[string]any) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.enc.Encode(v)
}

func guiRun(s system, ids []string, pearl string) int {
	ev := &events{enc: json.NewEncoder(os.Stdout)}
	var secrets struct {
		Password string `json:"password"`
		APIKey   string `json:"apiKey"`
	}
	line, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	json.Unmarshal([]byte(line), &secrets)

	m, c := selected(s, ids, pearl)
	c.apiKey = secrets.APIKey
	steps, repo, aur, _ := plan(s, m.parts, c)

	// sudo, by askpass
	if len(repo) > 0 || len(aur) > 0 {
		ap, stop, err := serveAskpass(secrets.Password)
		if err != nil {
			ev.send(map[string]any{"ev": "failed", "error": "couldn't set up the password helper: " + err.Error()})
			return 1
		}
		defer stop()
		os.Setenv("SUDO_ASKPASS", ap)
		chk := exec.Command("sudo", "-k", "-A", "-v")
		if b, err := chk.CombinedOutput(); err != nil {
			ev.send(map[string]any{"ev": "badpass", "error": strings.TrimSpace(string(b))})
			return 3
		}
		for i := range steps {
			steps[i].cmd = askpassed(steps[i].cmd, s.helper)
		}
	}

	var titles []guiStep
	for _, st := range steps {
		titles = append(titles, guiStep{st.title, st.detail})
	}
	ev.send(map[string]any{"ev": "plan", "steps": titles})
	for i, st := range steps {
		ev.send(map[string]any{"ev": "step", "i": i, "state": "running"})
		var err error
		switch {
		case st.cmd != nil:
			err = stream(st.cmd, func(l string) { ev.send(map[string]any{"ev": "log", "i": i, "line": l}) },
				func(p float64) { ev.send(map[string]any{"ev": "progress", "i": i, "pct": p}) })
		case st.run != nil:
			var o string
			o, err = st.run()
			for _, l := range strings.Split(strings.TrimSpace(o), "\n") {
				if l != "" {
					ev.send(map[string]any{"ev": "log", "i": i, "line": l})
				}
			}
		}
		if err != nil {
			ev.send(map[string]any{"ev": "step", "i": i, "state": "failed", "error": err.Error()})
			ev.send(map[string]any{"ev": "failed", "step": i, "error": st.title + " failed: " + err.Error()})
			return 1
		}
		ev.send(map[string]any{"ev": "step", "i": i, "state": "done"})
	}
	ev.send(map[string]any{"ev": "done"})
	return 0
}

// askpassed: the same command, asking for the password through SUDO_ASKPASS
func askpassed(cmd *exec.Cmd, helper string) *exec.Cmd {
	if cmd == nil {
		return nil
	}
	args := cmd.Args
	switch filepath.Base(cmd.Path) {
	case "sudo":
		args = append([]string{"sudo", "-A"}, args[1:]...)
	case "paru":
		args = append([]string{"paru", "--sudoflags", "-A", "--skipreview"}, args[1:]...)
	case "yay":
		args = append([]string{"yay", "--sudoflags", "-A", "--answerdiff", "None", "--answerclean", "None"}, args[1:]...)
	default:
		return cmd
	}
	return exec.Command(args[0], args[1:]...)
}

var percent = regexp.MustCompile(`(\d{1,3}(?:\.\d)?)%`)

// stream runs cmd, passing on each line it prints (a progress bar's \r
// updates become progress, not lines)
func stream(cmd *exec.Cmd, line func(string), progress func(float64)) error {
	r, w := io.Pipe()
	cmd.Stdout, cmd.Stderr = w, w
	cmd.Stdin = nil
	if err := cmd.Start(); err != nil {
		return err
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		sc := bufio.NewScanner(r)
		sc.Buffer(make([]byte, 64*1024), 1024*1024)
		sc.Split(splitLines)
		for sc.Scan() {
			t := strings.TrimSpace(stripANSI(sc.Text()))
			if t == "" {
				continue
			}
			if p := percent.FindStringSubmatch(t); p != nil && strings.Trim(t, "#=-> 0123456789.%") == "" {
				var f float64
				fmt.Sscan(p[1], &f)
				progress(f)
				continue
			}
			line(t)
		}
	}()
	err := cmd.Wait()
	w.Close()
	<-done
	return err
}

// splitLines: lines end at \n or \r
func splitLines(data []byte, atEOF bool) (int, []byte, error) {
	for i, b := range data {
		if b == '\n' || b == '\r' {
			return i + 1, data[:i], nil
		}
	}
	if atEOF && len(data) > 0 {
		return len(data), data, nil
	}
	return 0, nil, nil
}

var ansi = regexp.MustCompile(`\x1b\[[0-9;?]*[A-Za-z]`)

func stripANSI(s string) string { return ansi.ReplaceAllString(s, "") }

// serveAskpass: a private folder holding the askpass helper (a link to this
// program) and a socket that gives the password to whoever connects; only
// this user can get into the folder. stop removes both.
func serveAskpass(password string) (string, func(), error) {
	base := os.Getenv("XDG_RUNTIME_DIR")
	if base == "" {
		base = os.TempDir()
	}
	dir, err := os.MkdirTemp(base, "strand-")
	if err != nil {
		return "", nil, err
	}
	os.Chmod(dir, 0o700)
	self, err := os.Executable()
	if err != nil {
		os.RemoveAll(dir)
		return "", nil, err
	}
	ap := filepath.Join(dir, askpassName)
	if err := os.Symlink(self, ap); err != nil {
		os.RemoveAll(dir)
		return "", nil, err
	}
	sock := filepath.Join(dir, "pass.sock")
	ln, err := net.Listen("unix", sock)
	if err != nil {
		os.RemoveAll(dir)
		return "", nil, err
	}
	os.Chmod(sock, 0o600)
	os.Setenv("STRAND_ASKPASS_SOCK", sock)
	go func() {
		for {
			c, err := ln.Accept()
			if err != nil {
				return
			}
			io.WriteString(c, password+"\n")
			c.Close()
		}
	}()
	return ap, func() { ln.Close(); os.RemoveAll(dir) }, nil
}

// askpassClient: run as strand-askpass (by sudo): print the password
func askpassClient() int {
	c, err := net.Dial("unix", os.Getenv("STRAND_ASKPASS_SOCK"))
	if err != nil {
		return 1
	}
	defer c.Close()
	io.Copy(os.Stdout, c)
	return 0
}
