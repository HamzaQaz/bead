package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// the askpass helper hands sudo the password over the private socket
func TestAskpassHandsOverThePassword(t *testing.T) {
	bin := filepath.Join(t.TempDir(), "strand")
	if out, err := exec.Command("go", "build", "-o", bin, ".").CombinedOutput(); err != nil {
		t.Fatalf("build: %v\n%s", err, out)
	}
	// serve from a copy of this test's view: point Executable at the built binary
	t.Setenv("XDG_RUNTIME_DIR", t.TempDir())
	ap, stop, err := serveAskpass("hunter2 with spaces")
	if err != nil {
		t.Fatal(err)
	}
	defer stop()
	// the link points at the test binary; run the built strand under the helper's name instead
	link := filepath.Join(filepath.Dir(ap), "other", askpassName)
	os.MkdirAll(filepath.Dir(link), 0o700)
	if err := os.Symlink(bin, link); err != nil {
		t.Fatal(err)
	}
	out, err := exec.Command(link, "[sudo] password:").Output()
	if err != nil {
		t.Fatal(err)
	}
	if strings.TrimSuffix(string(out), "\n") != "hunter2 with spaces" {
		t.Fatalf("got %q", out)
	}
	if fi, _ := os.Stat(filepath.Dir(ap)); fi.Mode().Perm() != 0o700 {
		t.Fatalf("folder mode %v", fi.Mode().Perm())
	}
	stop()
	if _, err := os.Stat(filepath.Dir(ap)); !os.IsNotExist(err) {
		t.Fatal("folder left behind")
	}
}

func TestAskpassedCommands(t *testing.T) {
	cases := map[string][]string{
		"sudo pacman -S --needed x": {"sudo", "-A", "pacman", "-S", "--needed", "x"},
		"paru -S --needed y":        {"paru", "--sudoflags", "-A", "--skipreview", "-S", "--needed", "y"},
		"yay -S z":                  {"yay", "--sudoflags", "-A", "--answerdiff", "None", "--answerclean", "None", "-S", "z"},
		"sh -c true":                {"sh", "-c", "true"},
	}
	for in, want := range cases {
		f := strings.Fields(in)
		got := askpassed(exec.Command(f[0], f[1:]...), "").Args
		if strings.Join(got, " ") != strings.Join(want, " ") {
			t.Errorf("%s: got %v", in, got)
		}
	}
}

func TestStreamSplitsProgressFromLines(t *testing.T) {
	var lines []string
	var pcts []float64
	cmd := exec.Command("sh", "-c", `echo one; printf '###  12.5%%\r####  50.0%%\r'; echo two`)
	if err := stream(cmd, func(l string) { lines = append(lines, l) }, func(p float64) { pcts = append(pcts, p) }); err != nil {
		t.Fatal(err)
	}
	if strings.Join(lines, "|") != "one|two" || len(pcts) != 2 || pcts[1] != 50 {
		t.Fatalf("lines %v pcts %v", lines, pcts)
	}
}
